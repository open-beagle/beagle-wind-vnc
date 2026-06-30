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

portal_kde_bin="$(command -v xdg-desktop-portal-kde || true)"
if [ -z "${portal_kde_bin}" ] && [ -x /usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde ]; then
    portal_kde_bin=/usr/lib/x86_64-linux-gnu/libexec/xdg-desktop-portal-kde
fi
if [ -z "${portal_kde_bin}" ] && [ -x /usr/libexec/xdg-desktop-portal-kde ]; then
    portal_kde_bin=/usr/libexec/xdg-desktop-portal-kde
fi

portal_bin="$(command -v xdg-desktop-portal || true)"
if [ -z "${portal_bin}" ] && [ -x /usr/libexec/xdg-desktop-portal ]; then
    portal_bin=/usr/libexec/xdg-desktop-portal
fi

if [ -z "${portal_kde_bin}" ] || [ -z "${portal_bin}" ]; then
    echo "xdg-desktop-portal binaries are missing" >&2
    exit 66
fi

echo "[kde6] starting xdg-desktop-portal-kde (${portal_kde_bin}) on WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"

"${portal_kde_bin}" &
kde_pid=$!

"${portal_bin}" &
portal_pid=$!

wait -n "${kde_pid}" "${portal_pid}"
