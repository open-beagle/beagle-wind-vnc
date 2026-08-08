#!/bin/bash
set -e

if [ -f /etc/beagle-wind-vnc/runtime-env.sh ]; then
    . /etc/beagle-wind-vnc/runtime-env.sh
fi

export PASSWD="${BDWIND_PASSWORD:-${PASSWD:-mypasswd}}"

mkdir -p "${XDG_RUNTIME_DIR}" "${HOME}/.config" "${HOME}/.local/share" "${HOME}/.cache"
chmod 700 "${XDG_RUNTIME_DIR}" "${HOME}/.config" "${HOME}/.local" "${HOME}/.cache" 2>/dev/null || true

if [ ! -f "${HOME}/.config/fcitx5/profile" ]; then
    install -Dm600 /etc/beagle-wind-vnc/fcitx5-profile "${HOME}/.config/fcitx5/profile"
fi

if [ "$(stat -c '%u:%g' "${HOME}")" != "$(id -u):$(id -g)" ]; then
    sudo chown -R "$(id -u):$(id -g)" "${HOME}" || true
fi

# Keep the Steam launcher as a real file in the persistent home volume.  The
# executable bit also marks the desktop entry as launchable in Plasma's folder
# view.  Existing user customizations are never overwritten.
if [ -f /usr/share/applications/steam.desktop ] \
    && [ ! -e "${HOME}/Desktop/steam.desktop" ]; then
    install -Dm755 /usr/share/applications/steam.desktop "${HOME}/Desktop/steam.desktop"
fi
if [ -f "${HOME}/Desktop/steam.desktop" ]; then
    sed -i \
        's#Exec=/usr/bin/steam#Exec=/etc/beagle-wind-vnc/launch-steam.sh#g' \
        "${HOME}/Desktop/steam.desktop"
fi

(
    echo "${PASSWD}"
    echo "${PASSWD}"
) | sudo passwd "$(id -nu)" || true

sudo mkdir -p /run/dbus /tmp/.X11-unix /tmp/.ICE-unix "${PULSE_RUNTIME_PATH}" || true
sudo chmod 1777 /tmp/.X11-unix /tmp/.ICE-unix || true
sudo chown -R "$(id -u):$(id -g)" "${XDG_RUNTIME_DIR}" "${PULSE_RUNTIME_PATH}" || true

if [ ! -e /etc/xdg/menus/applications.menu ] \
    && [ -n "${XDG_MENU_PREFIX:-}" ] \
    && [ -f "/etc/xdg/menus/${XDG_MENU_PREFIX}applications.menu" ]; then
    sudo ln -snf "${XDG_MENU_PREFIX}applications.menu" /etc/xdg/menus/applications.menu || true
fi

sudo rm -f "${XDG_RUNTIME_DIR}"/wayland-* "${XDG_RUNTIME_DIR}"/kwin* "${XDG_RUNTIME_DIR}"/pipewire-* "${XDG_RUNTIME_DIR}"/bus 2>/dev/null || true

if [ ! -e /dev/dri/renderD128 ]; then
    real_render="$(ls /dev/dri/renderD* 2>/dev/null | head -n 1 || true)"
    if [ -n "${real_render}" ]; then
        sudo ln -snf "${real_render}" /dev/dri/renderD128 || true
    fi
fi

if [ ! -e /dev/dri/card0 ]; then
    real_card="$(ls /dev/dri/card* 2>/dev/null | head -n 1 || true)"
    if [ -n "${real_card}" ]; then
        sudo ln -snf "${real_card}" /dev/dri/card0 || true
    fi
fi

sudo chgrp render /dev/dri/renderD* /dev/dri/card* 2>/dev/null || true
sudo chmod g+rw /dev/dri/renderD* /dev/dri/card* 2>/dev/null || true

if [ -e /usr/lib/x86_64-linux-gnu/libnvidia-allocator.so.1 ]; then
    sudo mkdir -p /usr/lib/x86_64-linux-gnu/gbm
    sudo ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-allocator.so.1 /usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so || true
fi

sudo setcap -r /usr/bin/kwin_wayland 2>/dev/null || true
sudo setcap -r /usr/lib/*/libexec/kwin_wayland 2>/dev/null || true

sudo systemd-machine-id-setup 2>/dev/null || true
sudo dbus-uuidgen --ensure 2>/dev/null || true

if [ -x /opt/gstreamer/gst-env ]; then
    . /opt/gstreamer/gst-env
fi

exec "$@"
