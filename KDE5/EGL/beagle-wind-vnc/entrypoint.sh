#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

if [ -f /etc/beagle-wind-vnc/runtime-env.sh ]; then
    . /etc/beagle-wind-vnc/runtime-env.sh
fi

# Support unified BDWIND_PASSWORD with legacy PASSWD fallback
export PASSWD="${BDWIND_PASSWORD:-${PASSWD}}"

XVFB_PID=""
PLASMA_PID=""
APP_PID=""

cleanup() {
    echo "Stopping desktop session..."
    if [ -n "${APP_PID}" ]; then
        kill "${APP_PID}" 2>/dev/null || true
    fi
    if [ -n "${PLASMA_PID}" ]; then
        kill "${PLASMA_PID}" 2>/dev/null || true
    fi
    if [ -n "${XVFB_PID}" ]; then
        kill "${XVFB_PID}" 2>/dev/null || true
    fi
}

trap "cleanup; exit 0" HUP INT QUIT TERM

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done

DBUS_SESSION_SOCKET="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
if [ "${DBUS_SESSION_SOCKET}" != "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    echo "Waiting for session D-Bus socket: ${DBUS_SESSION_SOCKET}"
    until [ -S "${DBUS_SESSION_SOCKET}" ]; do sleep 0.5; done
fi

# Supervisor restarts only stop this script process; KDE/X11 descendants can
# survive and later attach to the next Xvfb session. Clear the old desktop
# session before recreating DISPLAY so hot updates start from one clean shell.
pkill -u "$(id -u)" -f "/usr/games/lutris" 2>/dev/null || true
pkill -u "$(id -u)" -x plasmashell 2>/dev/null || true
pkill -u "$(id -u)" -x kwin_x11 2>/dev/null || true
pkill -u "$(id -u)" -x ksmserver 2>/dev/null || true
pkill -u "$(id -u)" -f "kactivitymanagerd" 2>/dev/null || true
pkill -u "$(id -u)" -x kded5 2>/dev/null || true
pkill -u "$(id -u)" -x kdeinit5 2>/dev/null || true
pkill -u "$(id -u)" -x klauncher 2>/dev/null || true
pkill -u "$(id -u)" -x xsettingsd 2>/dev/null || true

# Make user directory owned by the default user
if [ "$(stat -c '%u:%g' ~)" != "$(id -u):$(id -g)" ]; then
    echo "Detected incorrect permissions on $HOME, fixing with sudo..."
    sudo chown -R "$(id -u):$(id -g)" ~ || echo 'Failed to fix home directory permissions'
fi
# Change operating system password to environment variable
(
  echo "${PASSWD}"
  echo "${PASSWD}"
) | sudo passwd "$(id -nu)" || (
  echo "mypasswd"
  echo "${PASSWD}"
  echo "${PASSWD}"
) | passwd "$(id -nu)" || echo 'Password change failed, using default password'
# Remove stale X11 files without deleting /tmp/.X11-unix itself. Xvfb runs as
# the unprivileged desktop user here; if the directory is deleted it cannot
# recreate it and ximagesrc will later fail to open DISPLAY.
sudo mkdir -p /tmp/.X11-unix || mkdir -p /tmp/.X11-unix || echo 'Failed to create X11 socket directory'
sudo chown root:root /tmp/.X11-unix || echo 'Failed to chown X11 socket directory'
sudo chmod 1777 /tmp/.X11-unix || chmod 1777 /tmp/.X11-unix || echo 'Failed to chmod X11 socket directory'
rm -f "/tmp/.X${DISPLAY#*:}-lock" "/tmp/.X11-unix/X${DISPLAY#*:}" || echo 'Failed to clean stale X11 lock/socket'
rm -rf ~/.cache || echo 'Failed to clean desktop cache'

# Fix NVENC Error Code 2 (OOM) by symlinking isolated NVIDIA devices to index 0 interfaces
if [ ! -e /dev/nvidia0 ]; then
    REAL_NVD=$(ls /dev/nvidia[0-9]* 2>/dev/null | head -n 1)
    if [ -n "$REAL_NVD" ]; then
        sudo ln -snf "$REAL_NVD" /dev/nvidia0 || echo "Failed to symlink $REAL_NVD to /dev/nvidia0"
    fi
fi
if [ ! -e /dev/dri/renderD128 ]; then
    REAL_REND=$(ls /dev/dri/renderD* 2>/dev/null | grep -v 128 | head -n 1)
    if [ -n "$REAL_REND" ]; then
        sudo ln -snf "$REAL_REND" /dev/dri/renderD128 || echo "Failed to symlink $REAL_REND to /dev/dri/renderD128"
    fi
fi
if [ ! -e /dev/dri/card0 ]; then
    REAL_CARD=$(ls /dev/dri/card* 2>/dev/null | grep -E '/dev/dri/card[0-9]+' | grep -v card0 | head -n 1)
    if [ -n "$REAL_CARD" ]; then
        sudo ln -snf "$REAL_CARD" /dev/dri/card0 || echo "Failed to symlink $REAL_CARD to /dev/dri/card0"
    fi
fi

# Change time zone from environment variable
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone >/dev/null || echo 'Failed to set timezone'
# Add Lutris directories to path
export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
# Add LibreOffice to library path
export LD_LIBRARY_PATH="/usr/lib/libreoffice/program${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"

# Configure joystick interposer
# export SELKIES_INTERPOSER='/usr/$LIB/selkies_joystick_interposer.so'
# export LD_PRELOAD="${SELKIES_INTERPOSER}${LD_PRELOAD:+:${LD_PRELOAD}}"
# export SDL_JOYSTICK_DEVICE=/dev/input/js0
# mkdir -pm1777 /dev/input || sudo-root mkdir -pm1777 /dev/input || echo 'Failed to create joystick interposer directory'
# touch /dev/input/js0 /dev/input/js1 /dev/input/js2 /dev/input/js3 || sudo-root touch /dev/input/js0 /dev/input/js1 /dev/input/js2 /dev/input/js3 || echo 'Failed to create joystick interposer devices'
# chmod 777 /dev/input/js* || sudo-root chmod 777 /dev/input/js* || echo 'Failed to change permission for joystick interposer devices'

# Set default display
export DISPLAY="${DISPLAY:-:20}"
# PipeWire-Pulse server socket path
export PIPEWIRE_LATENCY="128/48000"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# The NVIDIA-Linux driver installer has been removed.
# Host drivers must be mapped correctly via NVIDIA Container Toolkit (CDI).
if [ -z "$(ldconfig -N -v $(sed 's/:/ /g' <<<$LD_LIBRARY_PATH) 2>/dev/null | grep 'libEGL_nvidia.so.0')" ]; then
    echo "WARNING: libEGL_nvidia.so.0 not found! The NVIDIA container runtime is likely not passing correct libraries."
fi

# Read persisted physical resolution from bdwind.json (Auto mode persistence).
# This ensures we restore the last client's resolution after container restart.
if [ -f "$HOME/.config/bdwind.json" ]; then
    _PHYS_RES=$(python3 -c "import json; d=json.load(open('$HOME/.config/bdwind.json')); print(d.get('BDWIND_PHYSICAL_RESOLUTION',''))" 2>/dev/null)
    if [ -n "$_PHYS_RES" ]; then
        export DISPLAY_SIZEW="${_PHYS_RES%x*}"
        export DISPLAY_SIZEH="${_PHYS_RES#*x}"
        echo "Using persisted resolution from bdwind.json: ${DISPLAY_SIZEW}x${DISPLAY_SIZEH}"
    fi
fi

# Also source bdwind_display.conf if it exists (written by display_resize.py)
if [ -f "$HOME/.config/bdwind_display.conf" ]; then
    . "$HOME/.config/bdwind_display.conf"
fi

# Set target viewport resolution
TARGET_W="${DISPLAY_SIZEW:-1920}"
TARGET_H="${DISPLAY_SIZEH:-1080}"

# Run Xvfb server with a massive 8K virtual canvas (7680x4320).
# This allocates ~126MB RAM and sets the maximum RandR bounds to 8K,
# allowing us to dynamically scale up to 4K/8K without restarting Xvfb.
/usr/bin/Xvfb "${DISPLAY}" -screen 0 7680x4320x"${DISPLAY_CDEPTH}" -dpi "${DISPLAY_DPI}" +extension "COMPOSITE" +extension "DAMAGE" +extension "GLX" +extension "RANDR" +extension "RENDER" +extension "MIT-SHM" +extension "XFIXES" +extension "XTEST" +iglx +render -nolisten "tcp" -ac -noreset -shmem &
XVFB_PID="$!"

# Wait for X server to start
echo 'Waiting for X Socket' && until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done && echo 'X Server is ready'

# Dynamically set the initial viewport using Xrandr
echo "Setting initial Xrandr viewport to ${TARGET_W}x${TARGET_H}..."
MODELINE=$(cvt "$TARGET_W" "$TARGET_H" 60 | grep Modeline | cut -d' ' -f3-)
MODENAME="${TARGET_W}x${TARGET_H}_60.00"
xrandr -d "${DISPLAY}" --newmode "$MODENAME" $MODELINE
xrandr -d "${DISPLAY}" --addmode screen "$MODENAME"
xrandr -d "${DISPLAY}" --output screen --mode "$MODENAME"
echo "Viewport scaled successfully."

# Ensure user config directories exist with correct permissions
mkdir -p ~/.config ~/.local/share ~/.cache
chmod 700 ~/.config ~/.local ~/.cache
sudo chown -R "$(id -u):$(id -g)" ~/.config ~/.local ~/.cache || echo 'Failed to fix user config permissions'

# Auto-detect Compute-only GPUs (like A100/H100) or missing GPUs and fallback to Software Encoding
if [ -n "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -i 'A100\|H100')" ] || [ -z "$(ls -A /dev/dri 2>/dev/null)" ] && [ -z "$(nvidia-smi 2>/dev/null)" ]; then
    python3 - <<'PY'
import json
import os

conf = os.path.expanduser("~/.config/bdwind.json")
os.makedirs(os.path.dirname(conf), exist_ok=True)
settings = {}
if os.path.exists(conf):
    try:
        with open(conf, encoding="utf-8") as f:
            settings = json.load(f)
    except Exception:
        settings = {}
settings["BDWIND_ENCODER"] = "x264enc"
with open(conf, "w", encoding="utf-8") as f:
    json.dump(settings, f)
PY
    echo "Detected compute-only GPU or No GPU. Falling back to software encoding (x264enc)."
fi

# Use VirtualGL to run the KDE desktop environment with OpenGL if the GPU is available, otherwise use OpenGL with llvmpipe
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
# Plasma's panel and desktop icons are Qt Quick surfaces. In the EGL/Xvfb
# capture path, the default scene graph backend can create valid X windows
# without painting them into the Xvfb framebuffer. Use software Qt Quick for
# the desktop shell; accelerated rendering remains available to launched apps.
export QT_QUICK_BACKEND="${BDWIND_PLASMA_QT_QUICK_BACKEND:-software}"
export QSG_RENDER_LOOP="${BDWIND_PLASMA_QSG_RENDER_LOOP:-basic}"

KDE_DISPLAY_TOKEN="${DISPLAY//[:.]/_}"
if ! pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 \
    && ! pgrep -u "$(id -u)" -x kwin_x11 >/dev/null 2>&1 \
    && ! pgrep -u "$(id -u)" -x ksmserver >/dev/null 2>&1; then
    rm -f "${XDG_RUNTIME_DIR}/KSMserver_${KDE_DISPLAY_TOKEN}" \
        "${XDG_RUNTIME_DIR}/kdeinit5_${KDE_DISPLAY_TOKEN}" \
        "${XDG_RUNTIME_DIR}"/iceauth_* \
        "${XDG_RUNTIME_DIR}"/klauncher*.socket \
        "${XDG_RUNTIME_DIR}"/klauncher* \
        /tmp/.ICE-unix/* 2>/dev/null || true
fi
unset KDE_DISPLAY_TOKEN

KACTIVITY_BIN="/usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd"
if [ -x "${KACTIVITY_BIN}" ] && ! pgrep -u "$(id -u)" -f "${KACTIVITY_BIN}" >/dev/null 2>&1; then
  "${KACTIVITY_BIN}" >/tmp/kactivitymanagerd.log 2>&1 &
  sleep 2
fi

if [ "${BDWIND_DESKTOP_VGL:-false}" = "true" ]; then
  export VGL_FPS="${DISPLAY_REFRESH}"
  /usr/bin/vglrun -d "${VGL_DISPLAY:-egl}" +wm /usr/bin/startplasma-x11 &
else
  /usr/bin/startplasma-x11 &
fi
PLASMA_PID="$!"

# In this EGL/Xvfb desktop path, the plasmashell instance started by
# startplasma-x11 can race early KDE services and create an empty panel window.
# Restart it once after the session settles; the restarted shell paints the
# panel and desktop icons correctly into the Xvfb framebuffer.
if [ "${BDWIND_PLASMA_RESTART_AFTER_START:-true}" = "true" ]; then
    (
        sleep "${BDWIND_PLASMA_RESTART_DELAY:-25}"
        WAIT_KWIN=0
        while ! pgrep -u "$(id -u)" -x kwin_x11 >/dev/null 2>&1 && [ "${WAIT_KWIN}" -lt 30 ]; do
            WAIT_KWIN=$((WAIT_KWIN + 1))
            sleep 1
        done
        pkill -u "$(id -u)" -x plasmashell 2>/dev/null || true
        WAIT_SHELL=0
        while pgrep -u "$(id -u)" -x plasmashell >/dev/null 2>&1 && [ "${WAIT_SHELL}" -lt 10 ]; do
            WAIT_SHELL=$((WAIT_SHELL + 1))
            sleep 1
        done
        echo "Restarting plasmashell after KDE session warmup"
        exec env -i \
            HOME="${HOME}" \
            USER="$(id -nu)" \
            LOGNAME="$(id -nu)" \
            SHELL="${SHELL:-/bin/bash}" \
            PATH="${PATH}" \
            LANG="${LANG:-C.UTF-8}" \
            DISPLAY="${DISPLAY}" \
            XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR}" \
            DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS}" \
            QT_QUICK_BACKEND="${QT_QUICK_BACKEND}" \
            QSG_RENDER_LOOP="${QSG_RENDER_LOOP}" \
            QT_LOGGING_RULES="${QT_LOGGING_RULES}" \
            /usr/bin/plasmashell
    ) >/tmp/plasmashell-restart.log 2>&1 &
fi

STARTUP_COMMAND="${BDWIND_STARTUP_COMMAND:-${BDWIND_APP_COMMAND:-}}"
if [ -z "${STARTUP_COMMAND}" ] && command -v lutris >/dev/null 2>&1; then
    STARTUP_COMMAND="$(command -v lutris)"
fi

if [ -n "${STARTUP_COMMAND}" ]; then
    (
        sleep "${BDWIND_STARTUP_DELAY:-38}"
        PANEL_WAIT=0
        while [ "${PANEL_WAIT}" -lt 30 ]; do
            if DISPLAY="${DISPLAY}" xwininfo -root -tree 2>/dev/null | grep -qE 'plasmashell.*1920x44|plasmashell.*[0-9]+x4[0-9][+][0-9]+[+][0-9]+'; then
                break
            fi
            PANEL_WAIT=$((PANEL_WAIT + 1))
            sleep 1
        done
        if ! pgrep -u "$(id -u)" -f "${STARTUP_COMMAND%% *}" >/dev/null 2>&1; then
            echo "Starting desktop application: ${STARTUP_COMMAND}"
            export APPIMAGE_EXTRACT_AND_RUN="${APPIMAGE_EXTRACT_AND_RUN:-1}"
            exec bash -lc "exec ${STARTUP_COMMAND}"
        fi
    ) >/tmp/bdwind-startup-app.log 2>&1 &
    APP_PID="$!"
fi

# Start Fcitx5 input method framework (will be auto-started by KDE autostart)
# /usr/bin/fcitx5 &

# Add custom processes right below this line, or within `supervisord.conf` to perform service management similar to systemd

echo "Session Running. Press [Return] to exit."
while true; do
    if ! kill -0 "${XVFB_PID}" 2>/dev/null; then
        echo "Xvfb exited; restarting desktop through supervisor."
        wait "${XVFB_PID}" 2>/dev/null || true
        exit 1
    fi

    if ! kill -0 "${PLASMA_PID}" 2>/dev/null; then
        echo "Plasma session exited; restarting desktop through supervisor."
        wait "${PLASMA_PID}" 2>/dev/null || true
        exit 1
    fi

    if [ ! -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; then
        echo "X11 socket disappeared; restarting desktop through supervisor."
        exit 1
    fi

    sleep 2
done
