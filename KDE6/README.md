# KDE6 Smithay Runtime

This image runs KDE Plasma 6 as a nested Wayland desktop on top of
`gst-wayland-display`.

The video path is:

```text
Plasma / applications
  -> nested KWin
  -> waylanddisplaysrc (embedded Smithay compositor)
  -> BGRA CUDAMemory
  -> NVIDIA H.264 NVENC
  -> localhost RTP
  -> existing BDWind GStreamer/WebRTC service
  -> browser
```

Portal/PipeWire is not the video capture backend and is not a runtime fallback.
PipeWire remains available for audio, while desktop portals may still be used
for non-video desktop services such as file selection.

## Invariants

1. `smithay-display` owns the outer Wayland display and survives browser peer
   disconnects.
2. KWin connects to that outer display and exposes the fixed inner socket
   `bdwind-kde6` to Plasma and applications.
3. Raw frames stay in `memory:CUDAMemory` until NVENC.
4. Only pre-encoded H.264/RTP crosses the display/WebRTC process boundary.
5. The raw pre-encode queue is latest-frame-only and may drop stale raw frames.
   The encoded H.264 queue is bounded and non-leaky so it never corrupts the
   reference chain by dropping an encoded access unit.
6. Input is injected into the Smithay seat through source upstream/navigation
   events, not Portal RemoteDesktop or `/dev/uinput`.
7. No capture backend switch is offered. A failure is repaired on the Smithay
   path rather than switching back to Portal video.
8. The Smithay encoder automatically loads the bundled CDI/NVENC ioctl hook
   when `nvh264enc` is selected. The preload is scoped to that process and is
   not inherited by KWin, PipeWire, DBus, or monitoring tools.

## Pinned dependencies

- GStreamer: `1.28.6`
- `gst-wayland-display` stable commit:
  `b15285a2f1bb4dae5725b049915a4971664fafc6`
- Current NVIDIA validation target: RTX 4090 / driver `595.58.03`

The image build must fail when the required GStreamer artifact or
`waylanddisplaysrc` CUDA support is unavailable. It must not silently use a
distribution GStreamer build or a system-memory framebuffer.

## Build

From the `vnc` repository:

```bash
docker build \
  -f .beagle/kde6.Dockerfile \
  -t beagle-wind-vnc:1.2.0 \
  .
```

The image uses Ubuntu 26.04 because it provides the KDE Plasma 6 stack used by
this runtime. GStreamer is installed under `/opt/gstreamer`.

The immutable GStreamer artifact URL, seven-character source commit, and
SHA-256 checksum are pinned once in `.beagle/kde6-gstreamer.lock`. A release
artifact must come from a clean checkout and contain the full source commit at
`gstreamer/share/bdwind/bdwind-gstreamer.commit` plus the immutable builder
digest at `gstreamer/share/bdwind/bdwind-gstreamer.builder`. From the parent
workspace, build, verify, publish and update that lock with:

```bash
./scripts/build-kde6-gstreamer.sh
./scripts/publish-kde6-gstreamer.sh
```

Commit the resulting lock-file change before building the KDE6 image.

The WebRTC frontend follows the same release process and is pinned in
`.beagle/kde6-webrtc.lock`:

```bash
./scripts/publish-kde6-webrtc.sh
```

## Run

Minimal NVIDIA run:

```bash
docker run --rm -it \
  --name kde6 \
  --hostname kde6 \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --shm-size=4g \
  --gpus all \
  --device /dev/dri \
  -e BDWIND_PASSWORD=mypasswd \
  -e DISPLAY_SIZEW=1920 \
  -e DISPLAY_SIZEH=1080 \
  -e DISPLAY_REFRESH=60 \
  -e BDWIND_ENABLE_WEBRTC=true \
  -p 48080:8080 \
  beagle-wind-vnc:1.2.0
```

Important runtime settings:

```text
BDWIND_CAPTURE_SOURCE=smithay-rtp
BDWIND_WAYLAND_INPUT_BACKEND=smithay-events
BDWIND_SMITHAY_RTP_PORT=51000
BDWIND_SMITHAY_VIDEO_BITRATE=12000
BDWIND_SMITHAY_RENDER_NODE=/dev/dri/renderD128
BDWIND_SMITHAY_CUDA_DEVICE_ID=0
BDWIND_ENABLE_RESIZE=false
BDWIND_NVENC_HOOK=auto
```

The live Smithay bitrate bridge accepts `100..50000` kbps. The control panel
filters higher legacy presets for this backend.

`BDWIND_CAPTURE_SOURCE` and `BDWIND_WAYLAND_INPUT_BACKEND` are fixed by the
KDE6 runtime scripts. They are not compatibility toggles.

`BDWIND_NVENC_HOOK=auto` enables the bundled
`/opt/gstreamer/hooks/nvenc_ioctl_hook.so` when it is present and the encoder
is `nvh264enc`. Set it to `required` to fail startup when the hook is missing,
or `off` for a controlled native-driver comparison. The runtime defaults the
hook to the `wayland-nvenc` profile with open-path rewriting, RM GPU-list
filtering, and CUDA single-device mapping enabled. Each low-level
`NVENC_HOOK_*` setting remains independently overridable.

## Process topology

Supervisor starts the relevant components in this order:

```text
dbus / PipeWire audio services
  -> smithay-display
  -> kwin-wayland
  -> plasmashell
  -> start-webrtc
```

### `smithay-display`

`/etc/beagle-wind-vnc/smithay-display.py` owns:

```text
waylanddisplaysrc
  ! video/x-raw(memory:CUDAMemory),format=BGRA,
      width=1920,height=1080,framerate=60/1
  ! queue max-size-buffers=1 leaky=downstream
  ! nvh264enc
  ! h264parse
  ! rtph264pay
  ! udpsink 127.0.0.1:51000
```

It publishes:

```text
/run/user/1000/bdwind-smithay-display.env
/run/user/1000/bdwind-smithay-display.json
/run/user/1000/bdwind-smithay-control.sock
```

The JSON status contains source/encoded frame counts, average source FPS,
framebuffer, memory type, encoder, last-frame age, input count and key-unit
requests.

### `kwin-wayland`

KWin starts only after the outer display is ready:

```bash
kwin_wayland \
  --wayland-display "${BDWIND_SMITHAY_WAYLAND_DISPLAY}" \
  --socket bdwind-kde6 \
  --xwayland \
  --fullscreen true \
  --width "${DISPLAY_SIZEW}" \
  --height "${DISPLAY_SIZEH}" \
  --output-count 1 \
  --no-lockscreen
```

Plasma and applications use `WAYLAND_DISPLAY=bdwind-kde6`; they never connect
directly to the outer Smithay socket.

### `start-webrtc`

The WebRTC process subscribes to the persistent encoded stream:

```text
udpsrc 127.0.0.1:51000
  ! rtph264depay
  ! h264parse
  ! queue max-size-buffers=0 max-size-time=120ms leaky=no
  ! rtph264pay
  ! webrtcbin
```

There is no second H.264 encode. A browser refresh rebuilds only the WebRTC
peer pipeline; `smithay-display`, KWin and Plasma remain alive.

## Input

The browser sends keyboard/pointer/touch messages over the input DataChannel.
The WebRTC service forwards normalized events to
`bdwind-smithay-control.sock`. The display daemon converts them into
GStreamer upstream/navigation events for `waylanddisplaysrc`.

Supported event families:

- keyboard down/up/repeat and release-all;
- absolute and relative pointer motion;
- pointer buttons;
- wheel;
- touch;
- force-key-unit requests.

The GStreamer bus is used for state such as the `wayland.src` message. It is
not the input transport.

## Health checks

Inside the container:

```bash
cat /run/user/1000/bdwind-smithay-display.json

supervisorctl -s unix:///tmp/supervisor.sock status \
  smithay-display kwin-wayland plasmashell start-webrtc
```

Expected source status:

```json
{
  "ready": true,
  "framebuffer": "1920x1080",
  "refreshHz": 60,
  "memory": "CUDAMemory",
  "encoder": "nvh264enc",
  "rtpPort": 51000
}
```

Relevant logs:

```text
/tmp/smithay-display.log
/tmp/kwin-wayland.log
/tmp/plasmashell.log
/tmp/start-webrtc.log
```

## Current limitations

- `waylanddisplaysrc` stable emits buffers at the negotiated fixed refresh
  cadence even when there is no damage.
- `OutputDamageTracker` data is not yet exported as `BDWindDamageMeta`.
- NVENC therefore currently runs at the fixed 60 FPS release baseline.
- Dynamic resolution is disabled.
- KWin 6.6.4 with NVIDIA 595.58.03 may log
  `GL_FRAMEBUFFER_INCOMPLETE_ATTACHMENT` or `GL_OUT_OF_MEMORY`; this is tracked
  as a long-soak risk and must not trigger a Portal video fallback.
- Relative pointer, wheel, touch, Chinese IME, audio and clipboard remain in
  the explicit human acceptance matrix.

## Acceptance

Before publishing an image, verify:

1. 1080p60 and 4K60 negotiate `memory:CUDAMemory` at the NVENC sink.
2. Browser video remains playing while Space and shortcuts are sent remotely.
3. Repeated browser reloads do not change the Smithay/KWin/Plasma PIDs.
4. Konsole typing, Dolphin scrolling, window drag/resize and idle/wakeup do
   not produce a persistent 0 FPS state.
5. The active path reports H.264 hardware encoding and no sustained packet
   loss.
6. No CPU framebuffer copy or Portal ScreenCast owner appears in the video
   path.
