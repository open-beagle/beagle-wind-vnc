#!/usr/bin/env python3
import array
import os
import socket
import sys


BROKER_SOCKET = "/tmp/kde6-portal-pipewire.sock"


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


def main():
    sock_path = os.environ.get("BDWIND_PORTAL_FD_BROKER_SOCKET", BROKER_SOCKET)
    fd_num, node_id = recv_fd(sock_path)
    print(f"[portal-gst-probe] received fd={fd_num} node_id={node_id}", flush=True)

    import gi

    gi.require_version("Gst", "1.0")
    from gi.repository import Gst, GLib

    Gst.init(None)
    pipeline = Gst.Pipeline.new("portal-pipewire-probe")
    src = Gst.ElementFactory.make("pipewiresrc", "portal-src")
    sink = Gst.ElementFactory.make("fakesink", "sink")
    if src is None or sink is None:
        raise RuntimeError("pipewiresrc or fakesink is missing")
    src.set_property("fd", fd_num)
    connect_mode = os.environ.get("BDWIND_PORTAL_GST_CONNECT_MODE", "path")
    target_object = os.environ.get("BDWIND_PORTAL_GST_TARGET_OBJECT", "")
    if connect_mode in ("path", "both"):
        src.set_property("path", str(node_id))
    if connect_mode in ("target", "both"):
        src.set_property("target-object", target_object or str(node_id))
    src.set_property("always-copy", True)
    src.set_property("do-timestamp", True)
    src.set_property("num-buffers", int(os.environ.get("BDWIND_PORTAL_GST_PROBE_BUFFERS", "3")))
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

    timeout_sec = int(os.environ.get("BDWIND_PORTAL_GST_PROBE_TIMEOUT", "12"))

    def on_timeout():
        result["error"] = f"timed out after {timeout_sec}s"
        loop.quit()
        return False

    GLib.timeout_add_seconds(timeout_sec, on_timeout)
    pipeline.set_state(Gst.State.PLAYING)
    loop.run()
    pipeline.set_state(Gst.State.NULL)
    os.close(fd_num)

    if not result.get("ok"):
        raise RuntimeError(result.get("error", "probe failed"))
    print(
        f"[portal-gst-probe] pipewiresrc received buffers and reached EOS "
        f"mode={connect_mode} target={target_object or node_id}",
        flush=True,
    )
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:
        print(f"[portal-gst-probe] ERROR: {exc}", file=sys.stderr, flush=True)
        sys.exit(1)
