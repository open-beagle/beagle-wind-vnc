#!/usr/bin/env python3
"""Persistent gst-wayland-display owner for the KDE6 runtime.

This process owns the embedded Smithay compositor, its Wayland socket, the
CUDA-backed framebuffer, and NVENC.  Browser/WebRTC sessions only consume the
localhost H.264/RTP stream, so a peer reconnect cannot destroy the desktop.
"""

import json
import logging
import os
import signal
import socket
import threading
import time

import gi

gi.require_version("GLib", "2.0")
gi.require_version("Gst", "1.0")
gi.require_version("GstVideo", "1.0")
from gi.repository import GLib, GObject, Gst, GstVideo


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s smithay-display %(message)s",
)
LOG = logging.getLogger("smithay-display")

RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
READY_FILE = os.environ.get(
    "BDWIND_SMITHAY_READY_FILE",
    os.path.join(RUNTIME_DIR, "bdwind-smithay-display.env"),
)
STATUS_FILE = os.environ.get(
    "BDWIND_SMITHAY_STATUS_FILE",
    os.path.join(RUNTIME_DIR, "bdwind-smithay-display.json"),
)
CONTROL_SOCKET = os.environ.get(
    "BDWIND_SMITHAY_CONTROL_SOCKET",
    os.path.join(RUNTIME_DIR, "bdwind-smithay-control.sock"),
)


def env_int(name, default, minimum=None, maximum=None):
    try:
        value = int(os.environ.get(name, default))
    except (TypeError, ValueError):
        value = int(default)
    if minimum is not None:
        value = max(minimum, value)
    if maximum is not None:
        value = min(maximum, value)
    return value


def set_if_present(element, name, value):
    properties = {prop.name for prop in element.list_properties()}
    if name in properties:
        element.set_property(name, value)
        return True
    return False


class SmithayDisplay:
    def __init__(self):
        Gst.init(None)
        self.width = env_int("DISPLAY_SIZEW", 1920, 320, 7680)
        self.height = env_int("DISPLAY_SIZEH", 1080, 240, 4320)
        self.framerate = env_int("DISPLAY_REFRESH", 60, 1, 240)
        self.bitrate = env_int("BDWIND_SMITHAY_VIDEO_BITRATE", 12000, 100, 100000)
        self.rtp_port = env_int("BDWIND_SMITHAY_RTP_PORT", 51000, 1024, 65535)
        self.render_node = os.environ.get(
            "BDWIND_SMITHAY_RENDER_NODE", "/dev/dri/renderD128"
        )
        self.cuda_device_id = env_int("BDWIND_SMITHAY_CUDA_DEVICE_ID", 0, 0, 31)
        self.cursor_mode = os.environ.get(
            "BDWIND_SMITHAY_CURSOR_MODE", "hidden"
        ).strip().lower()
        if self.cursor_mode not in ("embedded", "hidden"):
            raise ValueError(
                "BDWIND_SMITHAY_CURSOR_MODE must be embedded or hidden"
            )
        self.pipeline = Gst.Pipeline.new("bdwind-smithay-display")
        self.mainloop = GLib.MainLoop()
        self.started_mono_ns = time.monotonic_ns()
        self.frame_count = 0
        self.encoded_count = 0
        self.input_count = 0
        self.keyunit_count = 0
        self.last_frame_mono_ns = 0
        self.last_input_mono_ns = 0
        self.wayland_display = ""
        self._control_stop = threading.Event()
        self._control_thread = None
        self._control_sock = None
        self._build_pipeline()

    def _make(self, factory, name):
        element = Gst.ElementFactory.make(factory, name)
        if element is None:
            raise RuntimeError("required GStreamer element is unavailable: %s" % factory)
        self.pipeline.add(element)
        return element

    def _build_pipeline(self):
        self.source = self._make("waylanddisplaysrc", "smithay-display-source")
        capsfilter = self._make("capsfilter", "smithay-display-cuda-caps")
        queue = self._make("queue", "smithay-display-encode-queue")
        self.encoder = self._make("nvh264enc", "smithay-display-nvenc")
        encoder_caps = self._make("capsfilter", "smithay-display-h264-caps")
        parser = self._make("h264parse", "smithay-display-h264-parse")
        payloader = self._make("rtph264pay", "smithay-display-rtp-pay")
        sink = self._make("udpsink", "smithay-display-rtp-sink")

        self.source.set_property("render-node", self.render_node)
        set_if_present(self.source, "cuda-device-id", self.cuda_device_id)
        self.source.set_property("cursor-mode", self.cursor_mode)
        capsfilter.set_property(
            "caps",
            Gst.Caps.from_string(
                "video/x-raw(memory:CUDAMemory),format=BGRA,"
                "width=%d,height=%d,framerate=%d/1"
                % (self.width, self.height, self.framerate)
            ),
        )

        queue.set_property("max-size-buffers", 1)
        queue.set_property("max-size-bytes", 0)
        queue.set_property("max-size-time", 0)
        queue.set_property("leaky", "downstream")

        self.encoder.set_property("bitrate", self.bitrate)
        set_if_present(self.encoder, "max-bitrate", self.bitrate)
        set_if_present(self.encoder, "rate-control", "vbr")
        set_if_present(self.encoder, "rc-mode", "vbr")
        set_if_present(self.encoder, "gop-size", self.framerate * 2)
        set_if_present(self.encoder, "strict-gop", False)
        set_if_present(self.encoder, "b-adapt", False)
        set_if_present(self.encoder, "bframes", 0)
        set_if_present(self.encoder, "b-frames", 0)
        set_if_present(self.encoder, "rc-lookahead", 0)
        set_if_present(self.encoder, "zerolatency", True)
        set_if_present(self.encoder, "zero-reorder-delay", True)
        set_if_present(self.encoder, "repeat-sequence-header", True)
        set_if_present(self.encoder, "aud", False)
        set_if_present(self.encoder, "cabac", True)
        set_if_present(self.encoder, "preset", "p1")
        set_if_present(self.encoder, "tune", "ultra-low-latency")
        set_if_present(self.encoder, "multi-pass", "disabled")
        vbv = max(1, int((self.bitrate + self.framerate - 1) / self.framerate * 1.5))
        set_if_present(self.encoder, "vbv-buffer-size", vbv)

        encoder_caps.set_property(
            "caps",
            Gst.Caps.from_string(
                "video/x-h264,profile=main,stream-format=byte-stream,alignment=au"
            ),
        )
        set_if_present(parser, "disable-passthrough", True)
        set_if_present(parser, "config-interval", -1)
        payloader.set_property("pt", 96)
        payloader.set_property("mtu", env_int("BDWIND_RTP_MTU", 1200, 576, 1400))
        set_if_present(payloader, "aggregate-mode", "zero-latency")
        set_if_present(payloader, "config-interval", -1)
        sink.set_property("host", "127.0.0.1")
        sink.set_property("port", self.rtp_port)
        sink.set_property("sync", False)
        sink.set_property("async", False)
        set_if_present(sink, "qos", False)

        elements = [
            self.source,
            capsfilter,
            queue,
            self.encoder,
            encoder_caps,
            parser,
            payloader,
            sink,
        ]
        for left, right in zip(elements, elements[1:]):
            if not left.link(right):
                raise RuntimeError(
                    "failed to link %s -> %s" % (left.get_name(), right.get_name())
                )

        source_pad = self.source.get_static_pad("src")
        encoder_pad = self.encoder.get_static_pad("src")
        source_pad.add_probe(Gst.PadProbeType.BUFFER, self._on_source_buffer)
        encoder_pad.add_probe(Gst.PadProbeType.BUFFER, self._on_encoded_buffer)

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect("message", self._on_bus_message)

    def _on_source_buffer(self, _pad, _info):
        self.frame_count += 1
        self.last_frame_mono_ns = time.monotonic_ns()
        return Gst.PadProbeReturn.OK

    def _on_encoded_buffer(self, _pad, _info):
        self.encoded_count += 1
        return Gst.PadProbeReturn.OK

    def _write_atomic(self, path, content):
        temporary = path + ".tmp"
        with open(temporary, "w", encoding="utf-8") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)

    def _publish_ready(self, structure):
        fields = {}
        for index in range(structure.n_fields()):
            name = structure.nth_field_name(index)
            fields[name] = str(structure.get_value(name))
        display = fields.get("WAYLAND_DISPLAY", "")
        if not display:
            raise RuntimeError("wayland.src message did not contain WAYLAND_DISPLAY")
        socket_path = os.path.join(RUNTIME_DIR, display)
        if not os.path.exists(socket_path):
            raise RuntimeError("published Wayland socket does not exist: %s" % socket_path)
        self.wayland_display = display
        lines = [
            "export BDWIND_SMITHAY_WAYLAND_DISPLAY=%s" % display,
            "export BDWIND_SMITHAY_RTP_PORT=%d" % self.rtp_port,
            "export BDWIND_SMITHAY_CONTROL_SOCKET=%s" % CONTROL_SOCKET,
            "export BDWIND_SMITHAY_WIDTH=%d" % self.width,
            "export BDWIND_SMITHAY_HEIGHT=%d" % self.height,
            "export BDWIND_SMITHAY_REFRESH=%d" % self.framerate,
        ]
        self._write_atomic(READY_FILE, "\n".join(lines) + "\n")
        LOG.info(
            "ready outer_display=%s framebuffer=%dx%d@%d "
            "memory=CUDAMemory encoder=nvh264enc rtp=127.0.0.1:%d",
            display,
            self.width,
            self.height,
            self.framerate,
            self.rtp_port,
        )

    def _on_bus_message(self, _bus, message):
        if message.type == Gst.MessageType.APPLICATION:
            structure = message.get_structure()
            if structure and structure.has_name("wayland.src"):
                try:
                    self._publish_ready(structure)
                except Exception:
                    LOG.exception("failed to publish Smithay readiness")
                    self.mainloop.quit()
        elif message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            LOG.error(
                "pipeline error source=%s error=%s debug=%s",
                message.src.get_name() if message.src else "unknown",
                error,
                debug,
            )
            self.mainloop.quit()
        elif message.type == Gst.MessageType.EOS:
            LOG.error("unexpected EOS")
            self.mainloop.quit()

    def _custom_event(self, name, fields):
        structure = Gst.Structure.new_empty(name)
        for key, value in fields.items():
            if key in ("button", "key", "id"):
                typed_value = GObject.Value()
                typed_value.init(GObject.TYPE_UINT)
                typed_value.set_uint(int(value))
                structure.set_value(key, typed_value)
            else:
                structure.set_value(key, value)
        return Gst.Event.new_custom(Gst.EventType.CUSTOM_UPSTREAM, structure)

    def _dispatch_input(self, command):
        kind = command.get("type")
        fields = {}
        if kind in ("MouseMoveAbsolute", "MouseMoveRelative"):
            fields = {
                "pointer_x": float(command["x"]),
                "pointer_y": float(command["y"]),
            }
        elif kind == "MouseButton":
            fields = {
                "button": int(command["button"]),
                "pressed": bool(command["pressed"]),
            }
        elif kind == "MouseAxis":
            fields = {
                "x": float(command.get("x", 0.0)),
                "y": float(command.get("y", 0.0)),
            }
        elif kind == "KeyboardKey":
            fields = {
                "key": int(command["key"]),
                "pressed": bool(command["pressed"]),
            }
        elif kind in ("TouchDown", "TouchMotion"):
            fields = {
                "id": int(command["id"]),
                "x": float(command["x"]),
                "y": float(command["y"]),
            }
        elif kind == "TouchUp":
            fields = {"id": int(command["id"])}
        elif kind in ("TouchFrame", "TouchCancel"):
            fields = {}
        else:
            LOG.warning("unsupported input command: %r", kind)
            return False
        pad = self.source.get_static_pad("src")
        accepted = bool(pad.send_event(self._custom_event(kind, fields)))
        self.input_count += 1
        self.last_input_mono_ns = time.monotonic_ns()
        if not accepted:
            LOG.warning("input event was not accepted type=%s", kind)
        return accepted

    def _force_keyunit(self, reason):
        self.keyunit_count += 1
        try:
            event = GstVideo.video_event_new_upstream_force_key_unit(
                Gst.CLOCK_TIME_NONE,
                True,
                self.keyunit_count,
            )
        except Exception:
            structure = Gst.Structure.new_empty("GstForceKeyUnit")
            structure.set_value("all-headers", True)
            structure.set_value("count", self.keyunit_count)
            event = Gst.Event.new_custom(Gst.EventType.CUSTOM_UPSTREAM, structure)
        pad = self.encoder.get_static_pad("src")
        accepted = bool(pad.send_event(event))
        LOG.info(
            "force-key-unit reason=%s count=%d accepted=%s",
            reason,
            self.keyunit_count,
            accepted,
        )
        return accepted

    def _set_bitrate(self, bitrate):
        bitrate = max(100, min(100000, int(bitrate)))
        self.encoder.set_property("bitrate", bitrate)
        set_if_present(self.encoder, "max-bitrate", bitrate)
        vbv = max(1, int((bitrate + self.framerate - 1) / self.framerate * 1.5))
        set_if_present(self.encoder, "vbv-buffer-size", vbv)
        self.bitrate = bitrate
        LOG.info("bitrate=%d vbv-buffer-size=%d", bitrate, vbv)

    def _dispatch_control(self, command):
        kind = command.get("type")
        if kind == "batch":
            for event in command.get("events", []):
                self._dispatch_input(event)
        elif kind == "force-keyunit":
            self._force_keyunit(command.get("reason", "control"))
        elif kind == "bitrate":
            self._set_bitrate(command["kbps"])
        elif kind == "ping":
            LOG.debug("control ping")
        else:
            self._dispatch_input(command)
        return False

    def _control_worker(self):
        try:
            os.unlink(CONTROL_SOCKET)
        except FileNotFoundError:
            pass
        control = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
        control.settimeout(0.5)
        control.bind(CONTROL_SOCKET)
        os.chmod(CONTROL_SOCKET, 0o600)
        self._control_sock = control
        LOG.info("control socket=%s", CONTROL_SOCKET)
        while not self._control_stop.is_set():
            try:
                payload = control.recv(65535)
            except socket.timeout:
                continue
            except OSError:
                break
            try:
                command = json.loads(payload.decode("utf-8"))
                GLib.idle_add(self._dispatch_control, command)
            except Exception:
                LOG.exception("invalid control datagram")

    def _write_status(self):
        now_ns = time.monotonic_ns()
        elapsed = max(0.001, (now_ns - self.started_mono_ns) / 1_000_000_000)
        status = {
            "ready": bool(self.wayland_display),
            "outerWaylandDisplay": self.wayland_display,
            "framebuffer": "%dx%d" % (self.width, self.height),
            "refreshHz": self.framerate,
            "memory": "CUDAMemory",
            "encoder": "nvh264enc",
            "cursorMode": self.cursor_mode,
            "bitrateKbps": self.bitrate,
            "rtpPort": self.rtp_port,
            "frames": self.frame_count,
            "encodedFrames": self.encoded_count,
            "averageSourceFps": round(self.frame_count / elapsed, 3),
            "inputs": self.input_count,
            "keyunitRequests": self.keyunit_count,
            "lastFrameAgeMs": (
                round((now_ns - self.last_frame_mono_ns) / 1_000_000, 3)
                if self.last_frame_mono_ns
                else None
            ),
            "lastInputAgeMs": (
                round((now_ns - self.last_input_mono_ns) / 1_000_000, 3)
                if self.last_input_mono_ns
                else None
            ),
        }
        try:
            self._write_atomic(
                STATUS_FILE,
                json.dumps(status, ensure_ascii=False, sort_keys=True) + "\n",
            )
        except Exception:
            LOG.exception("failed to write status")
        return not self._control_stop.is_set()

    def stop(self, *_args):
        self.mainloop.quit()

    def run(self):
        os.makedirs(RUNTIME_DIR, mode=0o700, exist_ok=True)
        for path in (READY_FILE, STATUS_FILE):
            try:
                os.unlink(path)
            except FileNotFoundError:
                pass
        self._control_thread = threading.Thread(
            target=self._control_worker,
            name="smithay-display-control",
            daemon=True,
        )
        self._control_thread.start()
        GLib.timeout_add_seconds(1, self._write_status)
        state = self.pipeline.set_state(Gst.State.PLAYING)
        if state == Gst.StateChangeReturn.FAILURE:
            raise RuntimeError("failed to start Smithay display pipeline")
        signal.signal(signal.SIGINT, self.stop)
        signal.signal(signal.SIGTERM, self.stop)
        try:
            self.mainloop.run()
        finally:
            self._control_stop.set()
            if self._control_sock is not None:
                self._control_sock.close()
            self.pipeline.set_state(Gst.State.NULL)
            if self._control_thread is not None:
                self._control_thread.join(timeout=1.0)
            for path in (READY_FILE, STATUS_FILE, CONTROL_SOCKET):
                try:
                    os.unlink(path)
                except FileNotFoundError:
                    pass


if __name__ == "__main__":
    SmithayDisplay().run()
