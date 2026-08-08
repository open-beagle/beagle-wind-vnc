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

# KWin creates XWayland on the first free display (currently :1), so do not
# pass runtime-env.sh's placeholder DISPLAY to Plasma-launched X11 clients.
for _ in $(seq 1 100); do
    x_socket="$(find /tmp/.X11-unix -maxdepth 1 -type s -name 'X*' -printf '%f\n' 2>/dev/null \
        | sort -V | head -n 1)"
    if [ -n "${x_socket}" ]; then
        export DISPLAY=":${x_socket#X}"
        break
    fi
    sleep 0.2
done
if [ -z "${x_socket:-}" ]; then
    echo "[kde6] KWin XWayland display did not become ready" >&2
    exit 69
fi
dbus-update-activation-environment DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR \
    XDG_CURRENT_DESKTOP XDG_SESSION_TYPE 2>/dev/null || true
echo "[kde6] Plasma application environment uses DISPLAY=${DISPLAY}"

for _ in $(seq 1 100); do
    if busctl --user --address="${DBUS_SESSION_BUS_ADDRESS}" --no-pager list 2>/dev/null \
        | awk '$1 == "org.kde.ActivityManager" && $2 != "-" { found = 1 } END { exit !found }'; then
        break
    fi
    sleep 0.2
done
if ! busctl --user --address="${DBUS_SESSION_BUS_ADDRESS}" --no-pager list 2>/dev/null \
    | awk '$1 == "org.kde.ActivityManager" && $2 != "-" { found = 1 } END { exit !found }'; then
    echo "[kde6] kactivitymanagerd did not acquire org.kde.ActivityManager" >&2
    exit 69
fi

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
    sleep 2
    python3 /etc/beagle-wind-vnc/kwin-screenshot-probe.py \
        >"${XDG_RUNTIME_DIR}/bdwind-kwin-pixels.json" 2>&1 || true
) &

wait "${plasmashell_pid}"
