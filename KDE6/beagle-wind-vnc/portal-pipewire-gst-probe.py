#!/usr/bin/env python3
import array
import json
import os
import socket
import subprocess
import sys
import threading
import time


BROKER_SOCKET = "/tmp/kde6-portal-pipewire.sock"
OUT_JSON = "/tmp/kde6-portal-pipewire-gst-probe.json"
OUT_ENV = "/tmp/kde6-portal-pipewire-gst-probe.env"


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


def close_fd(fd_num):
    if fd_num is None or fd_num < 0:
        return
    try:
        os.close(fd_num)
    except OSError:
        pass


def recv_fd(sock_path):
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.connect(sock_path)
    fds = array.array("i")
    msg, ancdata, _flags, _addr = client.recvmsg(4096, socket.CMSG_SPACE(fds.itemsize))
    for level, cmsg_type, data in ancdata:
        if level == socket.SOL_SOCKET and cmsg_type == socket.SCM_RIGHTS:
            fds.frombytes(data[: len(data) - (len(data) % fds.itemsize)])
    client.close()

    text = msg.decode("utf-8", errors="replace")
    fields = {}
    for line in text.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            fields[key] = value
    if not fds:
        raise RuntimeError(f"broker did not send fd: {text}")
    if not fields.get("node_id"):
        raise RuntimeError(f"broker did not send node_id: {text}")
    return fds[0], fields["node_id"]


def load_gst():
    import gi

    gi.require_version("Gst", "1.0")
    from gi.repository import Gst, GLib

    Gst.init(None)
    return Gst, GLib


def stringify(value):
    if value is None:
        return ""
    return str(value)


def read_pw_dump():
    try:
        proc = subprocess.run(
            ["pw-dump"],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
        )
    except Exception as exc:
        return [], f"pw-dump failed: {exc}"
    if proc.returncode != 0:
        return [], proc.stderr.strip() or f"pw-dump exited {proc.returncode}"
    try:
        return json.loads(proc.stdout), ""
    except Exception as exc:
        return [], f"pw-dump json parse failed: {exc}"


def obj_props(obj):
    return (obj.get("info") or {}).get("props") or {}


def obj_state(obj):
    return stringify((obj.get("info") or {}).get("state"))


def obj_permissions(obj):
    return "".join(obj.get("permissions") or [])


def safe_props(props, keys):
    result = {}
    for key in keys:
        if key in props:
            result[key] = stringify(props.get(key))
    return result


def same_id(value, expected):
    try:
        return int(value) == int(expected)
    except Exception:
        return stringify(value) == stringify(expected)


def collect_pipewire_context(node_id):
    data, error = read_pw_dump()
    context = {
        "dump_error": error,
        "node": {},
        "ports": [],
    }
    node_keys = (
        "object.id",
        "object.serial",
        "object.path",
        "node.name",
        "media.name",
        "media.class",
        "client.id",
        "stream.is-live",
        "node.driver",
        "object.register",
        "library.name",
    )
    port_keys = (
        "node.id",
        "object.id",
        "object.serial",
        "object.path",
        "port.alias",
        "port.direction",
        "port.group",
        "port.id",
        "port.name",
    )
    for obj in data:
        props = obj_props(obj)
        obj_id = obj.get("id")
        obj_type = stringify(obj.get("type"))
        if "PipeWire:Interface:Node" in obj_type and same_id(obj_id, node_id):
            context["node"] = {
                "id": stringify(obj_id),
                "type": obj_type,
                "state": obj_state(obj),
                "permissions": obj_permissions(obj),
                "props": safe_props(props, node_keys),
            }
        if "PipeWire:Interface:Port" in obj_type and same_id(props.get("node.id"), node_id):
            context["ports"].append(
                {
                    "id": stringify(obj_id),
                    "type": obj_type,
                    "direction": stringify((obj.get("info") or {}).get("direction")),
                    "permissions": obj_permissions(obj),
                    "props": safe_props(props, port_keys),
                }
            )
    return context


def add_candidate(candidates, seen, label, mode, path="", target=""):
    path = stringify(path)
    target = stringify(target)
    key = (mode, path, target)
    if key in seen:
        return
    seen.add(key)
    candidates.append(
        {
            "label": label,
            "mode": mode,
            "path": path,
            "target": target,
        }
    )


def add_manual_candidate(candidates, seen, label, link_source):
    link_source = stringify(link_source)
    if not link_source:
        return
    key = ("manual-link", link_source)
    if key in seen:
        return
    seen.add(key)
    candidates.append(
        {
            "label": label,
            "mode": "manual-link",
            "path": "",
            "target": "",
            "link_source": link_source,
        }
    )


def build_candidates(node_id, context):
    candidates = []
    seen = set()
    node = context.get("node") or {}
    node_props = node.get("props") or {}

    add_candidate(candidates, seen, "default", "default")
    add_candidate(candidates, seen, "node-path", "path", path=node_id)
    add_candidate(candidates, seen, "node-target-id", "target", target=node_id)

    for key, label in (
        ("object.serial", "node-target-serial"),
        ("node.name", "node-target-name"),
        ("media.name", "node-target-media-name"),
        ("object.path", "node-target-object-path"),
    ):
        value = node_props.get(key)
        if value:
            add_candidate(candidates, seen, label, "target", target=value)
            if key == "object.serial":
                add_candidate(candidates, seen, "node-both-serial", "both", path=node_id, target=value)

    for index, port in enumerate(context.get("ports") or []):
        port_props = port.get("props") or {}
        prefix = f"port{index}"
        port_id = port.get("id")
        if port_id:
            add_candidate(candidates, seen, f"{prefix}-path-id", "path", path=port_id)
            add_candidate(candidates, seen, f"{prefix}-target-id", "target", target=port_id)
        for key, label in (
            ("object.serial", "target-serial"),
            ("object.path", "target-object-path"),
            ("port.alias", "target-alias"),
            ("port.name", "target-name"),
        ):
            value = port_props.get(key)
            if value:
                add_candidate(candidates, seen, f"{prefix}-{label}", "target", target=value)

        if bool_env("BDWIND_PORTAL_GST_INCLUDE_MANUAL_LINK", False):
            add_manual_candidate(
                candidates,
                seen,
                f"{prefix}-manual-link",
                os.environ.get("BDWIND_PORTAL_GST_LINK_SOURCE")
                or port_props.get("port.alias")
                or port_props.get("object.path"),
            )

    for target in os.environ.get("BDWIND_PORTAL_GST_EXTRA_TARGETS", "").split(","):
        target = target.strip()
        if target:
            add_candidate(candidates, seen, f"extra-{target}", "target", target=target)

    return candidates


def set_optional_property(element, name, env_name, parse=str):
    if env_name not in os.environ:
        return
    element.set_property(name, parse(os.environ[env_name]))


def find_pipewire_input_port(client_name):
    try:
        proc = subprocess.run(
            ["pw-link", "-iI"],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except Exception:
        return ""
    for line in proc.stdout.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and client_name in parts[1]:
            return parts[0]
    return ""


def run_manual_linker(result, client_name, source_port):
    timeout_sec = int_env("BDWIND_PORTAL_GST_LINK_TIMEOUT", 6)
    deadline = time.time() + max(1, timeout_sec)
    input_port = ""
    while time.time() < deadline and not input_port:
        input_port = find_pipewire_input_port(client_name)
        if not input_port:
            time.sleep(0.2)

    result["manual_link_source"] = source_port
    result["manual_link_input"] = input_port
    if not input_port:
        result["manual_link_error"] = f"input port for {client_name} not found"
        return

    try:
        proc = subprocess.run(
            ["pw-link", "-w", source_port, input_port],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
        )
    except Exception as exc:
        result["manual_link_error"] = str(exc)
        return

    result["manual_link_returncode"] = str(proc.returncode)
    result["manual_link_stdout"] = proc.stdout.strip()
    result["manual_link_stderr"] = proc.stderr.strip()
    if proc.returncode != 0:
        result["manual_link_error"] = proc.stderr.strip() or f"pw-link exited {proc.returncode}"


def run_gst_once(Gst, GLib, fd_num, node_id, candidate):
    timeout_sec = int_env("BDWIND_PORTAL_GST_PROBE_TIMEOUT", 12)
    buffer_goal = int_env("BDWIND_PORTAL_GST_PROBE_BUFFERS", 1)
    always_copy = bool_env("BDWIND_PORTAL_GST_ALWAYS_COPY", True)

    pipeline = Gst.Pipeline.new("portal-pipewire-probe")
    src = Gst.ElementFactory.make("pipewiresrc", "portal-src")
    sink = Gst.ElementFactory.make("fakesink", "sink")
    if src is None or sink is None:
        raise RuntimeError("pipewiresrc or fakesink is missing")

    mode = candidate.get("mode", "path")
    if mode == "manual-link":
        close_fd(fd_num)
        fd_num = None

    if fd_num is not None:
        src.set_property("fd", fd_num)

    path = candidate.get("path") or str(node_id)
    target = candidate.get("target") or str(node_id)
    client_name = f"bdwind-kde6-gst-probe-{os.getpid()}-{candidate.get('label', 'probe')}"
    if mode == "manual-link":
        src.set_property("autoconnect", False)
        src.set_property("client-name", client_name)
    if mode in ("path", "both"):
        src.set_property("path", path)
    if mode in ("target", "both"):
        src.set_property("target-object", target)

    src.set_property("always-copy", always_copy)
    src.set_property("do-timestamp", True)
    src.set_property("num-buffers", buffer_goal)
    set_optional_property(src, "keepalive-time", "BDWIND_PORTAL_GST_KEEPALIVE_TIME", int)
    set_optional_property(src, "resend-last", "BDWIND_PORTAL_GST_RESEND_LAST", lambda v: v.lower() in ("1", "true", "yes", "on"))
    set_optional_property(src, "use-bufferpool", "BDWIND_PORTAL_GST_USE_BUFFERPOOL", lambda v: v.lower() in ("1", "true", "yes", "on"))

    sink.set_property("sync", False)
    sink.set_property("signal-handoffs", True)

    caps_text = os.environ.get("BDWIND_PORTAL_GST_CAPS", "")
    capsfilter = None
    if caps_text:
        capsfilter = Gst.ElementFactory.make("capsfilter", "probe-caps")
        if capsfilter is None:
            raise RuntimeError("capsfilter is missing")
        caps = Gst.Caps.from_string(caps_text)
        if caps is None:
            raise RuntimeError(f"invalid BDWIND_PORTAL_GST_CAPS={caps_text}")
        capsfilter.set_property("caps", caps)

    pipeline.add(src)
    if capsfilter is not None:
        pipeline.add(capsfilter)
    pipeline.add(sink)
    if capsfilter is not None:
        linked = src.link(capsfilter) and capsfilter.link(sink)
    else:
        linked = src.link(sink)
    if not linked:
        raise RuntimeError("failed to link pipewiresrc probe pipeline")

    loop = GLib.MainLoop()
    result = {
        "ok": False,
        "buffers": 0,
        "error": "",
        "debug": "",
        "state_change": "",
        "label": candidate.get("label", ""),
        "mode": mode,
        "path": path if mode in ("path", "both") else "",
        "target": target if mode in ("target", "both") else "",
        "fd_present": "1" if fd_num is not None else "0",
        "manual_link_source": "",
        "manual_link_input": "",
        "manual_link_error": "",
    }
    bus = pipeline.get_bus()
    bus.add_signal_watch()

    def on_handoff(_sink, _buffer, _pad):
        result["buffers"] += 1
        if result["buffers"] >= buffer_goal:
            result["ok"] = True
            loop.quit()

    def on_message(_bus, message):
        if message.type == Gst.MessageType.ERROR:
            err, debug = message.parse_error()
            result["error"] = str(err)
            result["debug"] = debug or ""
            loop.quit()
        elif message.type == Gst.MessageType.EOS:
            result["ok"] = True
            loop.quit()
        return True

    sink.connect("handoff", on_handoff)
    bus.connect("message", on_message)

    def on_timeout():
        result["error"] = f"timed out after {timeout_sec}s"
        loop.quit()
        return False

    link_thread = None
    if mode == "manual-link":
        source_port = os.environ.get("BDWIND_PORTAL_GST_LINK_SOURCE") or candidate.get("link_source") or "kwin_wayland:output_1"
        link_thread = threading.Thread(
            target=run_manual_linker,
            args=(result, client_name, source_port),
            daemon=True,
        )
        link_thread.start()
    GLib.timeout_add_seconds(timeout_sec, on_timeout)
    state_ret = pipeline.set_state(Gst.State.PLAYING)
    result["state_change"] = stringify(getattr(state_ret, "value_nick", state_ret))
    loop.run()
    pipeline.set_state(Gst.State.NULL)
    if link_thread is not None:
        link_thread.join(timeout=1)
    close_fd(fd_num)

    return result


def write_outputs(payload):
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=True, indent=2, sort_keys=True)
        f.write("\n")
    results = payload.get("results") or []
    ok_results = [item for item in results if item.get("ok")]
    first_ok = ok_results[0] if ok_results else {}
    with open(OUT_ENV, "w", encoding="utf-8") as f:
        f.write(f"BDWIND_PORTAL_GST_MATRIX_TOTAL={len(results)}\n")
        f.write(f"BDWIND_PORTAL_GST_MATRIX_OK={len(ok_results)}\n")
        f.write(f"BDWIND_PORTAL_GST_NODE_ID={payload.get('node_id', '')}\n")
        f.write(f"BDWIND_PORTAL_GST_FIRST_OK_LABEL={first_ok.get('label', '')}\n")
        f.write(f"BDWIND_PORTAL_GST_FIRST_OK_MODE={first_ok.get('mode', '')}\n")
        f.write(f"BDWIND_PORTAL_GST_FIRST_OK_TARGET={first_ok.get('target', '')}\n")


def run_single(sock_path, Gst, GLib):
    use_fd = bool_env("BDWIND_PORTAL_GST_USE_FD", True)
    fd_num, node_id = recv_fd(sock_path)
    if not use_fd:
        close_fd(fd_num)
        fd_num = None
    print(f"[portal-gst-probe] received fd={fd_num if fd_num is not None else '<disabled>'} node_id={node_id}", flush=True)

    connect_mode = os.environ.get("BDWIND_PORTAL_GST_CONNECT_MODE", "path")
    target_object = os.environ.get("BDWIND_PORTAL_GST_TARGET_OBJECT", "")
    path = os.environ.get("BDWIND_PORTAL_GST_PATH", node_id)
    candidate = {
        "label": "single",
        "mode": connect_mode,
        "path": path,
        "target": target_object or node_id,
        "link_source": os.environ.get("BDWIND_PORTAL_GST_LINK_SOURCE", ""),
    }
    result = run_gst_once(Gst, GLib, fd_num, node_id, candidate)
    payload = {
        "node_id": node_id,
        "mode": "single",
        "context": collect_pipewire_context(node_id),
        "results": [result],
    }
    write_outputs(payload)

    if not result.get("ok"):
        raise RuntimeError(result.get("error") or result.get("debug") or "probe failed")
    print(
        f"[portal-gst-probe] pipewiresrc received buffer(s) "
        f"mode={result['mode']} path={result['path']} target={result['target']}",
        flush=True,
    )
    return 0


def run_matrix(sock_path, Gst, GLib):
    use_fd = bool_env("BDWIND_PORTAL_GST_USE_FD", True)
    initial_fd, node_id = recv_fd(sock_path)
    close_fd(initial_fd)
    context = collect_pipewire_context(node_id)
    candidates = build_candidates(node_id, context)
    limit = int_env("BDWIND_PORTAL_GST_MATRIX_LIMIT", len(candidates))
    candidates = candidates[: max(1, limit)]

    print(
        f"[portal-gst-probe] matrix node_id={node_id} candidates={len(candidates)} "
        f"use_fd={1 if use_fd else 0}",
        flush=True,
    )
    node_props = (context.get("node") or {}).get("props") or {}
    print(
        "[portal-gst-probe] node "
        f"state={(context.get('node') or {}).get('state', '')} "
        f"serial={node_props.get('object.serial', '')} "
        f"name={node_props.get('node.name', '')} "
        f"media={node_props.get('media.name', '')}",
        flush=True,
    )
    for port in context.get("ports") or []:
        props = port.get("props") or {}
        print(
            "[portal-gst-probe] port "
            f"id={port.get('id', '')} serial={props.get('object.serial', '')} "
            f"path={props.get('object.path', '')} alias={props.get('port.alias', '')}",
            flush=True,
        )

    results = []
    for candidate in candidates:
        fd_num = None
        if use_fd and candidate.get("mode") != "manual-link":
            fd_num, broker_node_id = recv_fd(sock_path)
            if str(broker_node_id) != str(node_id):
                candidate = dict(candidate)
                candidate["broker_node_id"] = broker_node_id
        result = run_gst_once(Gst, GLib, fd_num, node_id, candidate)
        results.append(result)
        status = "ok" if result.get("ok") else "fail"
        reason = result.get("error") or result.get("debug") or ""
        print(
            f"[portal-gst-probe] matrix {status} label={result.get('label')} "
            f"mode={result.get('mode')} path={result.get('path')} "
            f"target={result.get('target')} buffers={result.get('buffers')} "
            f"manual_link={result.get('manual_link_source')}->{result.get('manual_link_input')} "
            f"error={reason}",
            flush=True,
        )
        if result.get("ok") and bool_env("BDWIND_PORTAL_GST_MATRIX_STOP_ON_SUCCESS", True):
            break

    payload = {
        "node_id": node_id,
        "mode": "matrix",
        "use_fd": use_fd,
        "context": context,
        "candidates": candidates,
        "results": results,
    }
    write_outputs(payload)
    return 0 if any(item.get("ok") for item in results) else 1


def main():
    sock_path = os.environ.get("BDWIND_PORTAL_FD_BROKER_SOCKET", BROKER_SOCKET)
    Gst, GLib = load_gst()
    if bool_env("BDWIND_PORTAL_GST_MATRIX", False):
        return run_matrix(sock_path, Gst, GLib)
    return run_single(sock_path, Gst, GLib)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[portal-gst-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        sys.exit(1)
