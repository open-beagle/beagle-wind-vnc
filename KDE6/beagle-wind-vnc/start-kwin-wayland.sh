#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}" || true

mode="${BDWIND_KDE6_MODE:-kwin-virtual}"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-kwin_wayland_drm=true;kwin_core=true;kpipewire=true}"

case "${mode}" in
    plasma-wayland)
        echo "[kde6] starting full Plasma Wayland session"
        exec startplasma-wayland
        ;;
    kwin-virtual)
        echo "[kde6] starting kwin_wayland virtual backend ${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"
        exec kwin_wayland \
            --virtual \
            --width "${DISPLAY_SIZEW}" \
            --height "${DISPLAY_SIZEH}" \
            --xwayland
        ;;
    *)
        echo "Unsupported BDWIND_KDE6_MODE=${mode}. Use kwin-virtual or plasma-wayland." >&2
        exit 64
        ;;
esac
