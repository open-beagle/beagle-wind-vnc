#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

mkdir -p "${XDG_RUNTIME_DIR}"
chmod 700 "${XDG_RUNTIME_DIR}" || true

mode="${BDWIND_KDE6_MODE:-nested-smithay}"

export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-wayland}"
# Keep the KWin baseline diagnostics and append the reviewed runtime rules.
# Previously this assignment shadowed BDWIND_KDE_QT_LOGGING_RULES entirely,
# making the screencast lease unobservable even when the runtime enabled it.
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-kwin_wayland_drm=true;kwin_core=true;kpipewire=true}${BDWIND_KDE_QT_LOGGING_RULES:+;${BDWIND_KDE_QT_LOGGING_RULES}}"

/etc/beagle-wind-vnc/disable-kde-screen-locker.sh
/etc/beagle-wind-vnc/ensure-kde-portal-desktop.sh

case "${mode}" in
    nested-smithay)
        if [ ! -r "${BDWIND_SMITHAY_READY_FILE}" ]; then
            echo "[kde6] Smithay display readiness file is missing" >&2
            exit 68
        fi
        . "${BDWIND_SMITHAY_READY_FILE}"
        outer_display="${BDWIND_SMITHAY_WAYLAND_DISPLAY:?missing outer display}"
        if [ ! -S "${XDG_RUNTIME_DIR}/${outer_display}" ]; then
            echo "[kde6] Smithay outer socket is missing: ${outer_display}" >&2
            exit 68
        fi
        rm -f \
            "${XDG_RUNTIME_DIR}/${BDWIND_KDE6_INNER_DISPLAY}" \
            "${XDG_RUNTIME_DIR}/${BDWIND_KDE6_INNER_DISPLAY}.lock"
        echo "[kde6] starting nested KWin outer=${outer_display} inner=${BDWIND_KDE6_INNER_DISPLAY} ${DISPLAY_SIZEW}x${DISPLAY_SIZEH}@${DISPLAY_REFRESH}"
        export WAYLAND_DISPLAY="${outer_display}"
        exec kwin_wayland \
            --wayland-display "${outer_display}" \
            --socket "${BDWIND_KDE6_INNER_DISPLAY}" \
            --xwayland \
            --fullscreen true \
            --width "${DISPLAY_SIZEW}" \
            --height "${DISPLAY_SIZEH}" \
            --output-count 1 \
            --no-lockscreen
        ;;
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
        echo "Unsupported BDWIND_KDE6_MODE=${mode}. Use nested-smithay, kwin-virtual, or plasma-wayland." >&2
        exit 64
        ;;
esac
