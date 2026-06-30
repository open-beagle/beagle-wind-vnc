#!/usr/bin/env python3
import os
import re
import signal
import socket
import shlex
import sys
import threading
import time
import uuid
import array
import struct
from pathlib import Path

import dbus
import dbus.mainloop.glib
from gi.repository import GLib


BUS_NAME = "org.freedesktop.portal.Desktop"
OBJ_PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.portal.ScreenCast"
REQ_IFACE = "org.freedesktop.portal.Request"
OUT_FILE = "/tmp/kde6-portal-virtual.env"
FD_BROKER_SOCKET = "/tmp/kde6-portal-pipewire.sock"
KDE_SCREENCAST_INTERFACE = "zkde_screencast_unstable_v1"
SAFE_ENV_RE = re.compile(r"^[A-Za-z0-9_./:@,+-]*$")
LAST_VALUES = {}
WL_DISPLAY_ID = 1
WL_REGISTRY_ID = 2
WL_DISPLAY_SYNC = 0
WL_DISPLAY_GET_REGISTRY = 1
WL_REGISTRY_BIND = 0
WL_REGISTRY_GLOBAL = 0
WL_CALLBACK_DONE = 0
KWIN_FAKE_INPUT_AUTHENTICATE = 0
KWIN_FAKE_INPUT_KEYBOARD_KEY = 10
KWIN_FAKE_INPUT_KEYBOARD_KEYSYM = 12
WL_KEYBOARD_KEY_STATE_RELEASED = 0
WL_KEYBOARD_KEY_STATE_PRESSED = 1
KEY_ENTER = 28
KEYSYM_RETURN = 0xFF0D
STOP_EVENT = threading.Event()


def env_value(value):
    text = "" if value is None else str(value)
    if SAFE_ENV_RE.match(text):
        return text
    return shlex.quote(text)


def write_env(values):
    LAST_VALUES.clear()
    LAST_VALUES.update(values)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        for key, value in values.items():
            f.write(f"{key}={env_value(value)}\n")


def set_status(values, phase, error="", response=""):
    values["BDWIND_PORTAL_PROBE_PHASE"] = phase
    values["BDWIND_PORTAL_RESPONSE"] = "" if response is None else str(response)
    if error or not values.get("BDWIND_PORTAL_ERROR"):
        values["BDWIND_PORTAL_ERROR"] = error
    write_env(values)


def bool_env(name, default=False):
    value = os.environ.get(name)
    if value is None:
        return default
    return value.lower() in ("1", "true", "yes", "on")


def int_env(name, default):
    try:
        return int(os.environ.get(name, str(default)))
    except ValueError:
        return default


def float_env(name, default):
    try:
        return float(os.environ.get(name, str(default)))
    except ValueError:
        return default


def install_signal_handlers():
    def stop(_signum, _frame):
        STOP_EVENT.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            signal.signal(sig, stop)
        except Exception:
            pass


def take_unix_fd(fd):
    if fd is None:
        return None
    if hasattr(fd, "take"):
        return fd.take()
    return int(fd)


def open_pipewire_remote_fd(screencast, session):
    fd = screencast.OpenPipeWireRemote(session, {})
    fd_num = take_unix_fd(fd)
    if fd_num is None:
        raise RuntimeError("OpenPipeWireRemote returned no fd")
    return fd_num


def send_fd(conn, fd_num, node_id):
    fds = array.array("i", [fd_num])
    payload = f"node_id={node_id}\nfd=SCM_RIGHTS\n".encode("utf-8")
    conn.sendmsg([payload], [(socket.SOL_SOCKET, socket.SCM_RIGHTS, fds)])


def serve_fd_broker(values, screencast, session, fallback_fd):
    sock_path = values.get("BDWIND_PORTAL_FD_BROKER_SOCKET", FD_BROKER_SOCKET)
    node_id = values.get("BDWIND_PW_NODE_ID", "")
    try:
        os.unlink(sock_path)
    except FileNotFoundError:
        pass

    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(sock_path)
    os.chmod(sock_path, 0o600)
    server.listen(8)
    server.settimeout(1.0)
    print(f"[portal-probe] fd broker listening on {sock_path}", flush=True)

    try:
        while not STOP_EVENT.is_set():
            try:
                conn, _ = server.accept()
            except socket.timeout:
                continue
            except OSError:
                break
            with conn:
                fd_num = None
                try:
                    fd_num = open_pipewire_remote_fd(screencast, session)
                    send_fd(conn, fd_num, node_id)
                    print(f"[portal-probe] fd broker sent fresh PipeWire fd={fd_num}", flush=True)
                except Exception as exc:
                    print(f"[portal-probe] fd broker fresh fd failed: {exc}", flush=True)
                    try:
                        dup_fd = os.dup(fallback_fd)
                        send_fd(conn, dup_fd, node_id)
                        print(f"[portal-probe] fd broker sent duplicated fallback fd={dup_fd}", flush=True)
                        fd_num = dup_fd
                    except Exception as fallback_exc:
                        try:
                            conn.sendall(f"error={fallback_exc}\n".encode("utf-8"))
                        except Exception:
                            pass
                finally:
                    if fd_num is not None:
                        try:
                            os.close(fd_num)
                        except Exception:
                            pass
    finally:
        server.close()
        try:
            os.unlink(sock_path)
        except FileNotFoundError:
            pass


def run_gst_selftest(fd_num, node_id):
    if not bool_env("BDWIND_PORTAL_GST_SELFTEST", False):
        return
    try:
        import gi

        gi.require_version("Gst", "1.0")
        from gi.repository import Gst, GLib

        Gst.init(None)
        pipeline = Gst.Pipeline.new("portal-selftest")
        src = Gst.ElementFactory.make("pipewiresrc", "portal-selftest-src")
        sink = Gst.ElementFactory.make("fakesink", "portal-selftest-sink")
        if src is None or sink is None:
            raise RuntimeError("pipewiresrc or fakesink is missing")
        test_fd = os.dup(fd_num)
        src.set_property("fd", test_fd)
        src.set_property("path", str(node_id))
        src.set_property("always-copy", True)
        src.set_property("do-timestamp", True)
        src.set_property("num-buffers", int_env("BDWIND_PORTAL_GST_SELFTEST_BUFFERS", 1))
        sink.set_property("sync", False)
        pipeline.add(src)
        pipeline.add(sink)
        if not src.link(sink):
            raise RuntimeError("failed to link pipewiresrc to fakesink")

        loop = GLib.MainLoop()
        result = {"ok": False}
        bus = pipeline.get_bus()
        bus.add_signal_watch()

        def on_message(_bus, message):
            if message.type == Gst.MessageType.ERROR:
                err, debug = message.parse_error()
                result["error"] = f"{err}: {debug}"
                loop.quit()
            elif message.type == Gst.MessageType.EOS:
                result["ok"] = True
                loop.quit()
            return True

        bus.connect("message", on_message)

        def on_timeout():
            result["error"] = "selftest timed out"
            loop.quit()
            return False

        GLib.timeout_add_seconds(int_env("BDWIND_PORTAL_GST_SELFTEST_TIMEOUT", 8), on_timeout)
        pipeline.set_state(Gst.State.PLAYING)
        loop.run()
        pipeline.set_state(Gst.State.NULL)
        try:
            os.close(test_fd)
        except Exception:
            pass
        if result.get("ok"):
            print("[portal-probe] gst selftest ok", flush=True)
        else:
            print(f"[portal-probe] gst selftest failed: {result.get('error', 'unknown')}", flush=True)
    except Exception as exc:
        print(f"[portal-probe] gst selftest failed: {exc}", flush=True)


def keep_session_alive(values, owned_fds, screencast, session):
    values["BDWIND_PORTAL_PROBE_PID"] = str(os.getpid())
    values["BDWIND_PORTAL_FD_BROKER_SOCKET"] = values.get("BDWIND_PORTAL_FD_BROKER_SOCKET", FD_BROKER_SOCKET)
    set_status(values, "keepalive")
    print(
        "[portal-probe] keepalive enabled; holding Portal session and "
        f"PipeWire fd(s) until shutdown: {owned_fds}",
        flush=True,
    )
    run_gst_selftest(owned_fds[0], values.get("BDWIND_PW_NODE_ID", ""))
    serve_fd_broker(values, screencast, session, owned_fds[0])
    set_status(values, "stopping")
    print("[portal-probe] keepalive stopping", flush=True)


def pad4(length):
    return (4 - (length % 4)) % 4


def pack_wayland_string(value):
    raw = value.encode("utf-8") + b"\x00"
    return struct.pack("I", len(raw)) + raw + (b"\x00" * pad4(len(raw)))


def make_wayland_msg(obj_id, opcode, payload=b""):
    return struct.pack("II", obj_id, ((8 + len(payload)) << 16) | opcode) + payload


class KWinFakeInput:
    def __init__(self):
        runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "")
        display_name = os.environ.get("WAYLAND_DISPLAY", "")
        if not runtime_dir or not display_name:
            raise RuntimeError("XDG_RUNTIME_DIR/WAYLAND_DISPLAY is not set")
        socket_path = display_name if display_name.startswith("/") else str(Path(runtime_dir) / display_name)

        self._next_id = 3
        self._recv_buf = b""
        self._callback_id = 0
        self._fake_input_name = 0
        self._fake_input_id = 0
        self._sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self._sock.connect(socket_path)

        self._send(make_wayland_msg(WL_DISPLAY_ID, WL_DISPLAY_GET_REGISTRY, struct.pack("I", WL_REGISTRY_ID)))
        self._callback_id = self._alloc_id()
        self._send(make_wayland_msg(WL_DISPLAY_ID, WL_DISPLAY_SYNC, struct.pack("I", self._callback_id)))
        self._read_until_sync()

        if not self._fake_input_name:
            raise RuntimeError("org_kde_kwin_fake_input global is not available")

        self._fake_input_id = self._bind(self._fake_input_name, "org_kde_kwin_fake_input", 6)
        self._send(
            make_wayland_msg(
                self._fake_input_id,
                KWIN_FAKE_INPUT_AUTHENTICATE,
                pack_wayland_string("bdwind-kde6-portal-probe") + pack_wayland_string("Auto-accept KDE Portal VIRTUAL probe"),
            )
        )

    def _alloc_id(self):
        obj_id = self._next_id
        self._next_id += 1
        return obj_id

    def _send(self, data):
        self._sock.sendall(data)

    def _recv(self, size):
        while len(self._recv_buf) < size:
            chunk = self._sock.recv(4096)
            if not chunk:
                raise RuntimeError("Wayland socket closed")
            self._recv_buf += chunk
        data = self._recv_buf[:size]
        self._recv_buf = self._recv_buf[size:]
        return data

    def _read_until_sync(self):
        while True:
            header = self._recv(8)
            obj_id, size_opcode = struct.unpack("II", header)
            size = size_opcode >> 16
            opcode = size_opcode & 0xFFFF
            payload = self._recv(size - 8) if size > 8 else b""
            if obj_id == WL_REGISTRY_ID and opcode == WL_REGISTRY_GLOBAL:
                name = struct.unpack_from("I", payload, 0)[0]
                str_len = struct.unpack_from("I", payload, 4)[0]
                interface = payload[8 : 8 + str_len - 1].decode("utf-8")
                if interface == "org_kde_kwin_fake_input":
                    self._fake_input_name = name
            elif obj_id == self._callback_id and opcode == WL_CALLBACK_DONE:
                return

    def _bind(self, name, interface, version):
        new_id = self._alloc_id()
        payload = struct.pack("I", name) + pack_wayland_string(interface) + struct.pack("II", version, new_id)
        self._send(make_wayland_msg(WL_REGISTRY_ID, WL_REGISTRY_BIND, payload))
        return new_id

    def key(self, keycode, pressed):
        self._send(
            make_wayland_msg(
                self._fake_input_id,
                KWIN_FAKE_INPUT_KEYBOARD_KEY,
                struct.pack("II", keycode, WL_KEYBOARD_KEY_STATE_PRESSED if pressed else WL_KEYBOARD_KEY_STATE_RELEASED),
            )
        )

    def keysym(self, keysym, pressed):
        self._send(
            make_wayland_msg(
                self._fake_input_id,
                KWIN_FAKE_INPUT_KEYBOARD_KEYSYM,
                struct.pack("II", keysym, WL_KEYBOARD_KEY_STATE_PRESSED if pressed else WL_KEYBOARD_KEY_STATE_RELEASED),
            )
        )

    def close(self):
        try:
            self._sock.close()
        except Exception:
            pass


def inject_enter_after_delay(delay):
    def worker():
        attempts = max(1, int_env("BDWIND_PORTAL_AUTO_ACCEPT_ATTEMPTS", 12))
        interval = max(0.1, float_env("BDWIND_PORTAL_AUTO_ACCEPT_INTERVAL", 0.75))
        print(
            f"[portal-probe] auto-accept waits {delay:.1f}s, then sends ENTER "
            f"{attempts} time(s) every {interval:.2f}s",
            flush=True,
        )
        time.sleep(delay)
        try:
            fake = KWinFakeInput()
            for _ in range(attempts):
                fake.key(KEY_ENTER, True)
                time.sleep(0.05)
                fake.key(KEY_ENTER, False)
                time.sleep(0.05)
                fake.keysym(KEYSYM_RETURN, True)
                time.sleep(0.05)
                fake.keysym(KEYSYM_RETURN, False)
                time.sleep(interval)
            fake.close()
            print("[portal-probe] auto-accept injected ENTER sequence via org_kde_kwin_fake_input", flush=True)
            return
        except Exception as exc:
            print(f"[portal-probe] fake-input auto-accept failed: {exc}", flush=True)

        try:
            import evdev
            from evdev import UInput, ecodes as e

            ui = UInput({e.EV_KEY: [e.KEY_ENTER]}, name="bdwind-kde6-portal-accept")
            time.sleep(0.2)
            for _ in range(attempts):
                ui.write(e.EV_KEY, e.KEY_ENTER, 1)
                ui.syn()
                time.sleep(0.05)
                ui.write(e.EV_KEY, e.KEY_ENTER, 0)
                ui.syn()
                time.sleep(interval)
            ui.close()
            print("[portal-probe] auto-accept injected ENTER sequence via evdev/uinput", flush=True)
        except Exception as exc:
            print(f"[portal-probe] auto-accept failed: {exc}", flush=True)

    threading.Thread(target=worker, daemon=True).start()


def find_portal_desktop_file():
    names = (
        "org.freedesktop.impl.portal.desktop.kde.desktop",
        "xdg-desktop-portal-kde.desktop",
    )
    dirs = []

    xdg_data_home = os.environ.get("XDG_DATA_HOME")
    if xdg_data_home:
        dirs.append(Path(xdg_data_home) / "applications")

    for data_dir in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":"):
        if data_dir:
            dirs.append(Path(data_dir) / "applications")

    for directory in dirs:
        for name in names:
            candidate = directory / name
            if candidate.is_file():
                return candidate
    return None


def read_desktop_value(path, key):
    if not path:
        return ""
    prefix = key + "="
    try:
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line.startswith(prefix):
                    return line[len(prefix) :]
    except OSError:
        return ""
    return ""


def collect_environment(values):
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "")
    wayland_display = os.environ.get("WAYLAND_DISPLAY", "")
    wayland_socket = str(Path(runtime_dir) / wayland_display) if runtime_dir and wayland_display else ""
    desktop_file = find_portal_desktop_file()
    interfaces = read_desktop_value(desktop_file, "X-KDE-Wayland-Interfaces")
    exec_line = read_desktop_value(desktop_file, "Exec")

    values.update(
        {
            "BDWIND_XDG_RUNTIME_DIR": runtime_dir,
            "BDWIND_WAYLAND_DISPLAY": wayland_display,
            "BDWIND_WAYLAND_SOCKET": wayland_socket,
            "BDWIND_WAYLAND_SOCKET_PRESENT": "1" if wayland_socket and Path(wayland_socket).is_socket() else "0",
            "BDWIND_XDG_CURRENT_DESKTOP": os.environ.get("XDG_CURRENT_DESKTOP", ""),
            "BDWIND_XDG_SESSION_TYPE": os.environ.get("XDG_SESSION_TYPE", ""),
            "BDWIND_XDG_DATA_HOME": os.environ.get("XDG_DATA_HOME", ""),
            "BDWIND_XDG_DATA_DIRS": os.environ.get("XDG_DATA_DIRS", ""),
            "BDWIND_PORTAL_KDE_DESKTOP_FILE": str(desktop_file) if desktop_file else "",
            "BDWIND_PORTAL_KDE_DESKTOP_EXEC": exec_line,
            "BDWIND_PORTAL_KDE_WAYLAND_INTERFACES": interfaces,
            "BDWIND_PORTAL_KDE_HAS_SCREENCAST_INTERFACE": "1"
            if KDE_SCREENCAST_INTERFACE in interfaces.split(",")
            else "0",
        }
    )

    print(
        "[portal-probe] env "
        f"runtime={runtime_dir} wayland={wayland_display} socket_present={values['BDWIND_WAYLAND_SOCKET_PRESENT']} "
        f"desktop={values['BDWIND_PORTAL_KDE_DESKTOP_FILE']} "
        f"interfaces={interfaces or '<none>'}",
        flush=True,
    )
    write_env(values)


def wait_for_response(bus, handle, timeout_sec):
    loop = GLib.MainLoop()
    result = {}

    def on_response(response, results):
        result["response"] = int(response)
        result["results"] = results
        loop.quit()

    bus.add_signal_receiver(
        on_response,
        signal_name="Response",
        dbus_interface=REQ_IFACE,
        path=str(handle),
    )

    def on_timeout():
        result["timeout"] = True
        loop.quit()
        return False

    GLib.timeout_add_seconds(timeout_sec, on_timeout)
    loop.run()
    return result


def call_request(bus, iface, name, *args, timeout=30):
    handle = getattr(iface, name)(*args)
    response = wait_for_response(bus, handle, timeout)
    if response.get("timeout"):
        raise TimeoutError(f"{name} timed out waiting for {handle}")
    if response.get("response") != 0:
        raise PortalRequestError(name, response.get("response"), response.get("results"))
    return response.get("results", {})


class PortalRequestError(RuntimeError):
    def __init__(self, phase, response, results):
        self.phase = phase
        self.response = "" if response is None else str(response)
        self.results = results
        super().__init__(f"{phase} failed: response={self.response} results={results}")


def main():
    install_signal_handlers()
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    values = {
        "BDWIND_PORTAL_VIRTUAL_AVAILABLE": "0",
        "BDWIND_PW_NODE_ID": "",
        "BDWIND_PW_FD_PRESENT": "0",
        "BDWIND_PW_FD": "",
        "BDWIND_PW_FD_PATH": "",
        "BDWIND_PORTAL_FD_BROKER_SOCKET": FD_BROKER_SOCKET,
        "BDWIND_PORTAL_AVAILABLE_SOURCE_TYPES": "",
        "BDWIND_PORTAL_AVAILABLE_CURSOR_MODES": "",
        "BDWIND_PORTAL_PROBE_PHASE": "init",
        "BDWIND_PORTAL_RESPONSE": "",
        "BDWIND_PORTAL_ERROR": "",
        "BDWIND_PORTAL_AUTO_ACCEPT": "1" if bool_env("BDWIND_PORTAL_AUTO_ACCEPT", False) else "0",
        "BDWIND_PORTAL_AUTO_ACCEPT_ATTEMPTS": str(int_env("BDWIND_PORTAL_AUTO_ACCEPT_ATTEMPTS", 12)),
        "BDWIND_PORTAL_AUTO_ACCEPT_INTERVAL": str(float_env("BDWIND_PORTAL_AUTO_ACCEPT_INTERVAL", 0.75)),
        "BDWIND_PORTAL_KEEPALIVE": "1" if bool_env("BDWIND_PORTAL_KEEPALIVE", False) else "0",
        "BDWIND_PORTAL_PROBE_PID": str(os.getpid()),
        "BDWIND_PORTAL_RESTORE_TOKEN": "",
        "BDWIND_PW_STREAMS": "",
    }
    write_env(values)
    collect_environment(values)

    bus = dbus.SessionBus()
    obj = bus.get_object(BUS_NAME, OBJ_PATH)
    props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
    screencast = dbus.Interface(obj, IFACE)

    available = int(props.Get(IFACE, "AvailableSourceTypes"))
    cursor_modes = int(props.Get(IFACE, "AvailableCursorModes"))
    values["BDWIND_PORTAL_AVAILABLE_SOURCE_TYPES"] = str(available)
    values["BDWIND_PORTAL_AVAILABLE_CURSOR_MODES"] = str(cursor_modes)
    print(f"[portal-probe] AvailableSourceTypes={available} AvailableCursorModes={cursor_modes}", flush=True)

    if not (available & 4):
        print("[portal-probe] VIRTUAL source type is not advertised by this portal backend", flush=True)
        set_status(values, "properties", "virtual_source_type_missing")
        write_env(values)
        return 2

    values["BDWIND_PORTAL_VIRTUAL_AVAILABLE"] = "1"
    set_status(values, "create")
    write_env(values)

    token = "bdwind" + uuid.uuid4().hex
    session_token = "bdwindsession" + uuid.uuid4().hex

    create_opts = {
        "handle_token": dbus.String(token),
        "session_handle_token": dbus.String(session_token),
    }
    create = call_request(bus, screencast, "CreateSession", create_opts, timeout=15)
    session = create.get("session_handle")
    if not session:
        set_status(values, "CreateSession", "missing_session_handle")
        raise RuntimeError(f"CreateSession response did not include session_handle: {create}")
    print(f"[portal-probe] session={session}", flush=True)

    set_status(values, "select")
    select_opts = {
        "handle_token": dbus.String("bdwindselect" + uuid.uuid4().hex),
        "types": dbus.UInt32(4),
        "multiple": dbus.Boolean(False),
    }
    if cursor_modes & 2:
        select_opts["cursor_mode"] = dbus.UInt32(2)
    elif cursor_modes & 1:
        select_opts["cursor_mode"] = dbus.UInt32(1)

    call_request(bus, screencast, "SelectSources", session, select_opts, timeout=60)
    print("[portal-probe] SelectSources ok", flush=True)

    set_status(values, "start")
    start_opts = {
        "handle_token": dbus.String("bdwindstart" + uuid.uuid4().hex),
    }
    if bool_env("BDWIND_PORTAL_AUTO_ACCEPT", False):
        try:
            delay = float(os.environ.get("BDWIND_PORTAL_AUTO_ACCEPT_DELAY", "2.0"))
        except ValueError:
            delay = 2.0
        inject_enter_after_delay(delay)
    start = call_request(bus, screencast, "Start", session, "", start_opts, timeout=120)
    streams = start.get("streams", [])
    values["BDWIND_PW_STREAMS"] = str(streams)
    values["BDWIND_PORTAL_RESTORE_TOKEN"] = str(start.get("restore_token", ""))
    print(f"[portal-probe] Start ok streams={streams}", flush=True)

    if streams:
        node_id = int(streams[0][0])
        values["BDWIND_PW_NODE_ID"] = str(node_id)

    owned_fds = []
    try:
        fd_num = open_pipewire_remote_fd(screencast, session)
        if fd_num is not None:
            owned_fds.append(fd_num)
            values["BDWIND_PW_FD"] = str(fd_num)
            values["BDWIND_PW_FD_PATH"] = f"/proc/{os.getpid()}/fd/{fd_num}"
        values["BDWIND_PW_FD_PRESENT"] = "1"
    except Exception as exc:
        print(f"[portal-probe] OpenPipeWireRemote failed: {exc}", flush=True)
        values["BDWIND_PORTAL_ERROR"] = f"OpenPipeWireRemote failed: {exc}"

    if owned_fds and bool_env("BDWIND_PORTAL_KEEPALIVE", False):
        keep_session_alive(values, owned_fds, screencast, session)
    else:
        set_status(values, "done")
        write_env(values)
    print(f"[portal-probe] wrote {OUT_FILE}", flush=True)
    return 0


if __name__ == "__main__":
    values_for_error = {
        "BDWIND_PORTAL_VIRTUAL_AVAILABLE": "0",
        "BDWIND_PW_NODE_ID": "",
        "BDWIND_PW_FD_PRESENT": "0",
        "BDWIND_PW_FD": "",
        "BDWIND_PW_FD_PATH": "",
        "BDWIND_PORTAL_FD_BROKER_SOCKET": FD_BROKER_SOCKET,
        "BDWIND_PORTAL_PROBE_PHASE": "fatal",
        "BDWIND_PORTAL_RESPONSE": "",
        "BDWIND_PORTAL_ERROR": "",
        "BDWIND_PORTAL_PROBE_PID": str(os.getpid()),
    }
    try:
        sys.exit(main())
    except PortalRequestError as exc:
        print(f"[portal-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        try:
            current = LAST_VALUES.copy()
            current.update(
                {
                    "BDWIND_PORTAL_PROBE_PHASE": exc.phase,
                    "BDWIND_PORTAL_RESPONSE": exc.response,
                    "BDWIND_PORTAL_ERROR": str(exc),
                }
            )
            write_env(current)
        except Exception:
            values_for_error["BDWIND_PORTAL_ERROR"] = str(exc)
            write_env(values_for_error)
        time.sleep(1)
        sys.exit(1)
    except TimeoutError as exc:
        print(f"[portal-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        try:
            current = LAST_VALUES.copy() or values_for_error
            current["BDWIND_PORTAL_PROBE_PHASE"] = "timeout"
            current["BDWIND_PORTAL_ERROR"] = str(exc)
            write_env(current)
        except Exception:
            pass
        time.sleep(1)
        sys.exit(1)
    except Exception as exc:
        print(f"[portal-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        try:
            current = LAST_VALUES.copy() or values_for_error
            current["BDWIND_PORTAL_PROBE_PHASE"] = "fatal"
            current["BDWIND_PORTAL_ERROR"] = str(exc)
            collect_environment(current)
            write_env(current)
        except Exception:
            pass
        time.sleep(1)
        sys.exit(1)
