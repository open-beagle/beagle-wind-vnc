#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

# Support unified BDWIND_PASSWORD with legacy PASSWD fallback
export PASSWD="${BDWIND_PASSWORD:-${PASSWD}}"

trap "echo TRAPed signal" HUP INT QUIT TERM

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done
# Make user directory owned by the default user
chown -f "$(id -nu):$(id -ng)" ~ || sudo-root chown -f "$(id -nu):$(id -ng)" ~ || chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || sudo-root chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || echo 'Failed to change user directory permissions, there may be permission issues'
# Change operating system password to environment variable
(
  echo "${PASSWD}"
  echo "${PASSWD}"
) | sudo passwd "$(id -nu)" || (
  echo "mypasswd"
  echo "${PASSWD}"
  echo "${PASSWD}"
) | passwd "$(id -nu)" || echo 'Password change failed, using default password'
# Remove directories to make sure the desktop environment starts
rm -rf /tmp/.X* ~/.cache || echo 'Failed to clean X11 paths'

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

# Auto-detect Compute-only GPUs (like A100/H100) or missing GPUs and fallback to Software Encoding
if [ -n "$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | grep -i 'A100\|H100')" ] || [ -z "$(ls -A /dev/dri 2>/dev/null)" ] && [ -z "$(nvidia-smi 2>/dev/null)" ]; then
    echo "export BDWIND_ENCODER=sw_x264" > ~/.config/bdwind_encoder.conf
    echo "Detected compute-only GPU or No GPU. Falling back to software encoding (sw_x264)."
fi

# Use VirtualGL to run the KDE desktop environment with OpenGL if the GPU is available, otherwise use OpenGL with llvmpipe
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
if [ -n "$(nvidia-smi --query-gpu=uuid --format=csv,noheader | head -n1)" ] || [ -n "$(ls -A /dev/dri 2>/dev/null)" ]; then
  export VGL_FPS="${DISPLAY_REFRESH}"
  /usr/bin/vglrun -d "${VGL_DISPLAY:-egl}" +wm /usr/bin/startplasma-x11 &
else
  /usr/bin/startplasma-x11 &
fi

# Start Fcitx5 input method framework (will be auto-started by KDE autostart)
# /usr/bin/fcitx5 &

# Add custom processes right below this line, or within `supervisord.conf` to perform service management similar to systemd

echo "Session Running. Press [Return] to exit."
read
