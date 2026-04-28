#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

# Support unified BDWIND_PASSWORD with legacy PASSWD fallback
export PASSWD="${BDWIND_PASSWORD:-${PASSWD}}"

# Force SDL to use X11, preventing Wayland detection issues which cause swapchain errors
export SDL_VIDEODRIVER=x11

trap "echo TRAPed signal" HUP INT QUIT TERM

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done
# Make user directory owned by the default user
chown -f "$(id -nu):$(id -ng)" ~ || sudo chown -f "$(id -nu):$(id -ng)" ~ || chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || sudo chown -R -f -h --no-preserve-root "$(id -nu):$(id -ng)" ~ || echo 'Failed to change user directory permissions, there may be permission issues'
# Change operating system password to environment variable
(
  echo "${PASSWD}"
  echo "${PASSWD}"
) | sudo passwd "$(id -nu)" || (
  echo "mypasswd"
  echo "${PASSWD}"
  echo "${PASSWD}"
) | passwd "$(id -nu)" || echo 'Password change failed, using default password'

# Inject Polkit rule to allow passwordless pkexec for Steam dependencies
sudo mkdir -pm 755 /etc/polkit-1/rules.d/ || true
sudo bash -c "cat <<'EOF' > /etc/polkit-1/rules.d/99-nopasswd.rules
polkit.addRule(function(action, subject) {
    if (action.id == \"org.freedesktop.policykit.exec\" &&
        subject.user == \"$(id -nu)\") {
        return polkit.Result.YES;
    }
});
EOF"
sudo chmod 644 /etc/polkit-1/rules.d/99-nopasswd.rules || true
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

# Set default display
export DISPLAY="${DISPLAY:-:20}"
# PipeWire-Pulse server socket path
export PIPEWIRE_LATENCY="128/48000"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# The NVIDIA-Linux driver installer has been removed.
# Host drivers must be mapped correctly via NVIDIA Container Toolkit.
if ! command -v nvidia-xconfig >/dev/null 2>&1; then
    echo "WARNING: nvidia-xconfig not found! The NVIDIA container runtime is likely not passing correct utilities."
fi
# Remove existing Xorg configuration
if [ -f "/etc/X11/xorg.conf" ]; then
  sudo rm -f "/etc/X11/xorg.conf"
fi

# When using --gpus all, we need to select the specific GPU to bind Xorg and Vulkan to.
# Default to GPU 0 if GPU_INDEX is not passed by the run command.
export GPU_INDEX="${GPU_INDEX:-0}"
export GPU_SELECT="$(nvidia-smi --query-gpu=uuid --id="${GPU_INDEX}" --format=csv,noheader | head -n1)"

if [ -z "${GPU_SELECT}" ]; then
  echo "No NVIDIA GPUs detected or NVIDIA Container Toolkit not configured. Exiting."
  exit 1
fi

# Limit CUDA to THIS specific GPU so nvenc (selkies-gstreamer) and applications
# only see this specific GPU as their CUDA device 0.
export CUDA_VISIBLE_DEVICES="${GPU_SELECT}"


# Force Vulkan to use the NVIDIA driver instead of falling back to Mesa lavapipe (CPU software rendering).
# MESA_VK_DEVICE_SELECT is only for Mesa open-source drivers (like AMD/Intel) and causes Nvidia setups
# to fallback to 10 FPS CPU rendering (lavapipe). We enforce the Nvidia ICD directly.
export VK_ICD_FILENAMES="/etc/vulkan/icd.d/nvidia_icd.json:/usr/share/vulkan/icd.d/nvidia_icd.json"
export VK_DRIVER_FILES="/etc/vulkan/icd.d/nvidia_icd.json:/usr/share/vulkan/icd.d/nvidia_icd.json"

# Force OpenGL to use NVIDIA driver
export __GLX_VENDOR_LIBRARY_NAME="nvidia"



# Setting `VIDEO_PORT` to none disables RANDR/XRANDR, causing potential compatibility issues, set to DFP if using datacenter GPUs
if [ "$(echo ${VIDEO_PORT} | tr '[:upper:]' '[:lower:]')" = "none" ]; then
  export CONNECTED_MONITOR="None"
  export USE_DISPLAY_DEVICE="None"
# The X server is otherwise deliberately set to a specific video port despite not being plugged to enable RANDR/XRANDR, monitor will display the screen if plugged to the specific port
else
  export CONNECTED_MONITOR="${VIDEO_PORT:-DFP}"
  export USE_DISPLAY_DEVICE="${VIDEO_PORT:-DFP}"
fi

# Bus ID from nvidia-smi is in hexadecimal format and should be converted to decimal format (including the domain) which Xorg understands, required because nvidia-xconfig doesn't work as intended in a container
HEX_ID="$(nvidia-smi --query-gpu=pci.bus_id --id=${GPU_SELECT} --format=csv,noheader | head -n1)"
IFS=":." ARR_ID=(${HEX_ID})
unset IFS
BUS_ID="PCI:$(printf '%u' 0x${ARR_ID[1]}):$(printf '%u' 0x${ARR_ID[2]}):$(printf '%u' 0x${ARR_ID[3]})"
# A custom modeline should be generated because there is no monitor to fetch this information normally
export MODELINE="$(cvt ${DISPLAY_SIZEW} ${DISPLAY_SIZEH} ${DISPLAY_REFRESH} | sed -n 2p)"

# Check for spoofed EDID (Fixes Headless 30FPS lock for games like Dota 2)
export EDID_OPTIONS=""
if [ -f "/etc/X11/edid.bin" ]; then
    export EDID_OPTIONS="    Option         \"CustomEDID\" \"${CONNECTED_MONITOR}:/etc/X11/edid.bin\"
    Option         \"IgnoreEDID\" \"False\"
    Option         \"UseEDID\" \"True\""
fi


# Generate /etc/X11/xorg.conf manually instead of relying on nvidia-xconfig
cat <<EOF | sudo tee /etc/X11/xorg.conf >/dev/null
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0"
    InputDevice    "Keyboard0" "CoreKeyboard"
    InputDevice    "Mouse0" "CorePointer"
EndSection

Section "Files"
EndSection

Section "InputDevice"
    # generated from default
    Identifier     "Mouse0"
    Driver         "mouse"
    Option         "Protocol" "auto"
    Option         "Device" "/dev/input/mice"
    Option         "Emulate3Buttons" "no"
    Option         "ZAxisMapping" "4 5"
EndSection

Section "InputDevice"
    # generated from default
    Identifier     "Keyboard0"
    Driver         "kbd"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    VendorName     "Unknown"
    ModelName      "Unknown"
    Option         "DPMS" "False"
    ${MODELINE}
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "${BUS_ID}"
    Option         "AllowEmptyInitialConfiguration" "True"
    Option         "ProbeAllGpus" "False"
    Option         "IncludeImplicitMetaModes" "True"
    Option         "ModeDebug" "True"
    Option         "ModeValidation" "NoMaxPClkCheck,NoEdidMaxPClkCheck,NoMaxSizeCheck,NoHorizSyncCheck,NoVertRefreshCheck,NoVirtualSizeCheck,NoExtendedGpuCapabilitiesCheck,NoTotalSizeCheck,NoDualLinkDVICheck,NoDisplayPortBandwidthCheck,AllowNon3DVisionModes,AllowNonHDMI3DModes,AllowNonEdidModes,NoEdidHDMI2Check,AllowDpInterlaced"
    Option         "AllowExternalGpus" "True"
    Option         "ConnectedMonitor" "${CONNECTED_MONITOR}"
    Option         "UseDisplayDevice" "${USE_DISPLAY_DEVICE}"
    Option         "AllowFlipping" "False"
${EDID_OPTIONS}
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    ${DISPLAY_CDEPTH}
    SubSection     "Display"
        Depth       ${DISPLAY_CDEPTH}
        Virtual     ${DISPLAY_SIZEW} ${DISPLAY_SIZEH}
        Modes      "$(echo ${MODELINE} | awk '{print $2}' | tr -d '\"')"
    EndSubSection
EndSection

Section "ServerFlags"
    Option         "DontVTSwitch" "True"
    Option         "DontZap" "True"
    Option         "AllowMouseOpenFail" "True"
    Option         "AutoAddGPU" "False"
EndSection
EOF


# Real sudo (sudo) is required in Ubuntu 20.04 but not in newer Ubuntu, this symbolic link enables running Xorg inside a container with `-sharevts`
ln -snf /dev/ptmx /dev/tty7 || sudo ln -snf /dev/ptmx /dev/tty7 || echo 'Failed to create /dev/tty7 device'

# Run Xorg server with required extensions
sudo /usr/lib/xorg/Xorg "${DISPLAY}" vt7 -noreset -novtswitch -sharevts -nolisten "tcp" -nolisten "local" -ac -dpi "${DISPLAY_DPI}" +extension "COMPOSITE" +extension "DAMAGE" +extension "GLX" +extension "RANDR" +extension "RENDER" +extension "MIT-SHM" +extension "XFIXES" +extension "XTEST" +extension "DRI3" &

# Wait for X server to start
echo 'Waiting for X Socket' && until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done && echo 'X Server is ready'

# Ensure user config directories exist with correct permissions
mkdir -p ~/.config ~/.local/share ~/.cache
chmod 700 ~/.config ~/.local ~/.cache

# Start KDE desktop environment
export XDG_SESSION_ID="${DISPLAY#*:}"
export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
export __GL_THREADED_OPTIMIZATIONS=0

# Disable OpenGL/Vulkan VSync globally to prevent headless Xorg from capping games at 20-30fps
# and causing 1000%+ CPU spin-lock overhead in Vulkan presentation queues.
export __GL_SYNC_TO_VBLANK=0
export vblank_mode=0

# 彻底禁用 KDE Plasma 的 X11 桌面特效合成器 (Compositor)
# 在无头的 NVIDIA 云推流环境内，KWin Compositing 会导致严重的画面延迟、与 ximagesrc/NVENC 争抢显存，
# 更会导致浏览器引擎（如 Steam CEF）在软件回落时发生严重的 XWindow 销毁冲突和彻底黑屏！
# 必须使用硬切断方式保证所有层在原生 Xorg 驱动直接被画出来，再配合 AllowFlipping=False 根治所有撕裂。
sudo -u ubuntu bash -c "mkdir -p ~/.config && kwriteconfig5 --file kwinrc --group Compositing --key Enabled false || true"
sudo -u ubuntu bash -c "mkdir -p ~/.config && kwriteconfig6 --file kwinrc --group Compositing --key Enabled false || true"

/usr/bin/startplasma-x11 &

# Start Fcitx input method framework (will be auto-started by KDE autostart)
# /usr/bin/fcitx &

# Add custom processes right below this line, or within `supervisord.conf` to perform service management similar to systemd

echo "Session Running. Press [Return] to exit."
read
