# KDE6 Wayland Image

This directory contains the KDE Plasma 6 Wayland image for the next KDE6 retest round.

The goal is not to replace the current production X11 image yet. This image exists to validate:

1. XDG Desktop Portal ScreenCast `VIRTUAL` source type.
2. KWin virtual output behavior and future resize support.
3. NVIDIA Allocator / GBM behavior under `kwin_wayland --virtual`.
4. GStreamer 1.28.4 PipeWire / DMABuf / GL / CUDA bridge routes.

## Build

```bash
cd vnc
docker build -f .beagle/kde6-wayland.Dockerfile -t beagle-wind-vnc:1.2.0 .
```

The Dockerfile defaults to `ubuntu:26.04` because Ubuntu 24.04 does not provide KDE Plasma 6 as the normal desktop stack.
It downloads `bdwind-gstreamer-1.28.4-ubuntu2604.tar.gz` into `/opt/gstreamer` during build and verifies `gst-launch-1.0 --version`.
If the tarball is missing or the version is not 1.28.4, the image build must fail instead of falling back to the distribution GStreamer packages.
`pipewiresrc` is also checked during build. Review its `Filename` line in the build log because that plugin is provided by PipeWire packaging rather than the GStreamer monorepo tarball.

To override the artifact URL:

```bash
docker build -f .beagle/kde6-wayland.Dockerfile \
  --build-arg GSTREAMER_TARBALL_URL=https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gstreamer-1.28.4-ubuntu2604.tar.gz \
  -t beagle-wind-vnc:1.2.0 .
```

## Run

Minimal local run:

```bash
docker run --rm -it \
  --name kde6-wayland \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --shm-size=4g \
  --gpus all \
  --device /dev/dri \
  -e BDWIND_PASSWORD=mypasswd \
  -e DISPLAY_SIZEW=1920 \
  -e DISPLAY_SIZEH=1080 \
  -e BDWIND_PORTAL_VIRTUAL_PROBE=true \
  -e BDWIND_ENABLE_WEBRTC=false \
  beagle-wind-vnc:1.2.0
```

GStreamer 1.28.4 is baked into the image. Enable WebRTC after Portal has returned a PipeWire node:

```bash
docker run --rm -it \
  --name kde6-wayland \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --shm-size=4g \
  --gpus all \
  --device /dev/dri \
  -e BDWIND_ENABLE_WEBRTC=true \
  -e BDWIND_PIPEWIRE_ALWAYS_COPY=0 \
  -p 48080:8080 \
  beagle-wind-vnc:1.2.0
```

## Modes

`BDWIND_KDE6_MODE=kwin-virtual` starts KWin directly:

```text
kwin_wayland --virtual --width $DISPLAY_SIZEW --height $DISPLAY_SIZEH --xwayland
```

`BDWIND_KDE6_MODE=plasma-wayland` starts the regular Plasma Wayland session:

```text
startplasma-wayland
```

Use `kwin-virtual` for Portal virtual monitor and PipeWire ScreenCast tests first. Use `plasma-wayland` only when validating the full session.

## Portal Virtual Probe

When `BDWIND_PORTAL_VIRTUAL_PROBE=true`, supervisor runs:

```text
/etc/beagle-wind-vnc/portal-virtual-monitor.py
```

The probe checks `org.freedesktop.portal.ScreenCast.AvailableSourceTypes` and attempts:

```text
CreateSession
  -> SelectSources(types=4)
  -> Start
  -> OpenPipeWireRemote
```

Results are written to:

```text
/tmp/kde6-portal-virtual.env
```

Expected useful values:

```text
BDWIND_PORTAL_VIRTUAL_AVAILABLE=1
BDWIND_PW_NODE_ID=<node-id>
BDWIND_PW_FD_PRESENT=1
```

## Retest Matrix

After Portal can provide a PipeWire node, retest the GStreamer routes documented in `docs/debugs/KDE6.Wayland.md`:

```text
pipewiresrc always-copy=true  -> videorate -> NVENC
pipewiresrc always-copy=false -> videorate -> NVENC
pipewiresrc -> glupload -> gldownload -> videorate -> NVENC
pipewiresrc -> cudaupload -> cudaconvert -> videorate -> NVENC
```

## Current Risk

KWin virtual output resize is still the main open risk. Creating a virtual monitor through Portal is standard API, but running resize depends on KWin support for resizing virtual outputs.
