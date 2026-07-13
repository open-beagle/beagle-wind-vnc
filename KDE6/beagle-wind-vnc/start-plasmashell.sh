#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

if [ "${BDWIND_KDE6_PLASMASHELL:-true}" != "true" ]; then
    echo "[kde6] plasmashell disabled"
    exec sleep infinity
fi

if [ "${BDWIND_KDE6_MODE:-kwin-virtual}" = "plasma-wayland" ]; then
    echo "[kde6] plasmashell is managed by startplasma-wayland"
    exec sleep infinity
fi

until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] || ls "${XDG_RUNTIME_DIR}"/wayland-* >/dev/null 2>&1; do
    sleep 0.5
done

pkill -TERM -u "$(id -u)" -x plasmashell 2>/dev/null || true
for _ in $(seq 1 20); do
    if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
        break
    fi
    sleep 0.25
done
if pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1; then
    pkill -KILL -u "$(id -u)" -x plasmashell 2>/dev/null || true
    sleep 0.5
fi

/etc/beagle-wind-vnc/ensure-plasma-captured-panel.sh --config-only

if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/tmp/kbuildsycoca6-plasmashell.log 2>&1 || {
        echo "[kde6] kbuildsycoca6 failed before plasmashell start" >&2
        tail -n 80 /tmp/kbuildsycoca6-plasmashell.log >&2 || true
    }
fi

plasmashell --replace &
plasmashell_pid=$!

(
    sleep "${BDWIND_KDE6_CAPTURED_PANEL_DELAY:-3}"
    /etc/beagle-wind-vnc/ensure-plasma-captured-panel.sh
) &

wait "${plasmashell_pid}"
