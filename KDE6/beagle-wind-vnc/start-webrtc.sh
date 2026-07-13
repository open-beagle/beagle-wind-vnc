#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

if [ "${BDWIND_ENABLE_WEBRTC}" != "true" ]; then
    echo "[kde6] BDWIND_ENABLE_WEBRTC=false; skipping WebRTC runtime"
    exec sleep infinity
fi

if [ ! -x /opt/gstreamer/gst-env ]; then
    echo "[kde6] /opt/gstreamer/gst-env not found. Rebuild the image with bdwind-gstreamer ${BDWIND_GSTREAMER_REQUIRED_VERSION}." >&2
    exit 66
fi

. /opt/gstreamer/gst-env

gst_version="$(gst-launch-1.0 --version 2>/dev/null || true)"
if ! printf '%s\n' "${gst_version}" | grep -Eq "(GStreamer|version) ${BDWIND_GSTREAMER_REQUIRED_VERSION}"; then
    echo "[kde6] GStreamer ${BDWIND_GSTREAMER_REQUIRED_VERSION} is required, but current runtime is:" >&2
    printf '%s\n' "${gst_version:-<missing gst-launch-1.0>}" >&2
    exit 67
fi

if [ -f /tmp/kde6-portal-virtual.env ]; then
    . /tmp/kde6-portal-virtual.env
fi

export BDWIND_RENDER_ENGINE="wayland"
export BDWIND_CAPTURE_SOURCE="pipewiresrc"
export BDWIND_ENABLE_RESIZE="${BDWIND_ENABLE_RESIZE:-false}"
export BDWIND_PORT_GSTREAMER="${BDWIND_PORT_GSTREAMER:-${BDWIND_PORT_NGINX:-8080}}"
export BDWIND_STUN_UDP_MIN="${BDWIND_STUN_UDP_MIN:-${BDWIND_UDP_PORT_MIN:-0}}"
export BDWIND_STUN_UDP_MAX="${BDWIND_STUN_UDP_MAX:-${BDWIND_UDP_PORT_MAX:-0}}"

until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] || ls "${XDG_RUNTIME_DIR}"/wayland-* >/dev/null 2>&1; do
    sleep 0.5
done

if python3 -c "import bdwind_gstreamer" >/dev/null 2>&1; then
    exec python3 -c 'import asyncio; asyncio.set_event_loop(asyncio.new_event_loop()); from bdwind_gstreamer.__main__ import main; main()'
fi

if command -v bdwind-gstreamer >/dev/null 2>&1; then
    exec bdwind-gstreamer
fi

echo "[kde6] bdwind_gstreamer entrypoint not found in /opt/gstreamer" >&2
exit 66
