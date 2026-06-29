#!/usr/bin/env python3
import os
import sys
import time
import uuid

import dbus
import dbus.mainloop.glib
from gi.repository import GLib


BUS_NAME = "org.freedesktop.portal.Desktop"
OBJ_PATH = "/org/freedesktop/portal/desktop"
IFACE = "org.freedesktop.portal.ScreenCast"
REQ_IFACE = "org.freedesktop.portal.Request"
OUT_FILE = "/tmp/kde6-portal-virtual.env"


def write_env(values):
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        for key, value in values.items():
            f.write(f"{key}={value}\n")


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
        raise RuntimeError(f"{name} failed: response={response.get('response')} results={response.get('results')}")
    return response.get("results", {})


def main():
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)

    values = {
        "BDWIND_PORTAL_VIRTUAL_AVAILABLE": "0",
        "BDWIND_PW_NODE_ID": "",
        "BDWIND_PW_FD_PRESENT": "0",
    }
    write_env(values)

    bus = dbus.SessionBus()
    obj = bus.get_object(BUS_NAME, OBJ_PATH)
    props = dbus.Interface(obj, "org.freedesktop.DBus.Properties")
    screencast = dbus.Interface(obj, IFACE)

    available = int(props.Get(IFACE, "AvailableSourceTypes"))
    cursor_modes = int(props.Get(IFACE, "AvailableCursorModes"))
    print(f"[portal-probe] AvailableSourceTypes={available} AvailableCursorModes={cursor_modes}", flush=True)

    if not (available & 4):
        print("[portal-probe] VIRTUAL source type is not advertised by this portal backend", flush=True)
        write_env(values)
        return 2

    values["BDWIND_PORTAL_VIRTUAL_AVAILABLE"] = "1"
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
        raise RuntimeError(f"CreateSession response did not include session_handle: {create}")
    print(f"[portal-probe] session={session}", flush=True)

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

    start_opts = {
        "handle_token": dbus.String("bdwindstart" + uuid.uuid4().hex),
    }
    start = call_request(bus, screencast, "Start", session, "", start_opts, timeout=120)
    streams = start.get("streams", [])
    print(f"[portal-probe] Start ok streams={streams}", flush=True)

    if streams:
        node_id = int(streams[0][0])
        values["BDWIND_PW_NODE_ID"] = str(node_id)

    try:
        fd = screencast.OpenPipeWireRemote(session, {})
        values["BDWIND_PW_FD_PRESENT"] = "1"
        try:
            fd.take()
        except Exception:
            pass
    except Exception as exc:
        print(f"[portal-probe] OpenPipeWireRemote failed: {exc}", flush=True)

    write_env(values)
    print(f"[portal-probe] wrote {OUT_FILE}", flush=True)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[portal-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        time.sleep(1)
        sys.exit(1)
