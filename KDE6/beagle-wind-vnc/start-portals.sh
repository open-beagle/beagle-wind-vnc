#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ] || ls "${XDG_RUNTIME_DIR}"/wayland-* >/dev/null 2>&1; do
    sleep 0.5
done

if [ ! -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; then
    WAYLAND_DISPLAY="$(ls "${XDG_RUNTIME_DIR}"/wayland-* 2>/dev/null | grep -v lock | head -n 1 | xargs basename)"
    export WAYLAND_DISPLAY
fi

echo "[kde6] starting xdg-desktop-portal-kde on WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"

/usr/libexec/xdg-desktop-portal-kde &
kde_pid=$!

/usr/libexec/xdg-desktop-portal &
portal_pid=$!

wait -n "${kde_pid}" "${portal_pid}"
