#!/bin/bash
set -euo pipefail

. /etc/beagle-wind-vnc/runtime-env.sh

if [ ! -x /opt/gstreamer/gst-env ]; then
    echo "[kde6] /opt/gstreamer/gst-env is missing" >&2
    exit 66
fi
. /opt/gstreamer/gst-env

if ! gst-inspect-1.0 waylanddisplaysrc >/dev/null 2>&1; then
    echo "[kde6] waylanddisplaysrc is unavailable; KDE6 has no capture fallback" >&2
    exit 68
fi

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}"
rm -f \
    "${BDWIND_SMITHAY_READY_FILE}" \
    "${BDWIND_SMITHAY_STATUS_FILE}" \
    "${BDWIND_SMITHAY_CONTROL_SOCKET}"

exec python3 /etc/beagle-wind-vnc/smithay-display.py
