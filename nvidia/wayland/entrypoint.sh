#!/bin/bash

# =============================================================================
# Beagle-Wind Desktop Wayland Entrypoint
# =============================================================================

set -e
trap "echo TRAPed signal" HUP INT QUIT TERM

# 1. 确保环境变量
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done

chown -f "$(id -nu):$(id -ng)" ~ || true
rm -rf /tmp/.X* ~/.cache || true
rm -f ${XDG_RUNTIME_DIR}/wayland-* ${XDG_RUNTIME_DIR}/kwin* || true
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone >/dev/null || true

export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
export WAYLAND_DISPLAY="wayland-0"
export DISPLAY="${DISPLAY:-:20}"

mkdir -p ~/.config ~/.local/share ~/.cache
chmod 700 ~/.config ~/.local ~/.cache

# Fix uinput permissions for Phase 4 WebRTC / Auto-Accept script
sudo chmod 0666 /dev/uinput || true
sudo mkdir -p /var/run/dbus || true

# 2. 启动原生 KDE Plasma Wayland 引擎
echo "Waiting for PipeWire socket before starting KWin..."
until [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]; do sleep 0.5; done

echo "Waiting extra 3 seconds for PipeWire & Wireplumber internals to stabilize..."
sleep 3

echo "Starting Native KDE Plasma Wayland Compositor..."

# Export DBus session bus address so KWin joins the global container session
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PIPEWIRE_REMOTE="pipewire-0"

mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix
for i in {0..19}; do
    touch "/tmp/.X11-unix/X$i"
done

# 还原 GLX 的设备精确挂载隔离与链接逻辑
if [ ! -e /dev/nvidia0 ] && ls /dev/nvidia[0-9]* 1> /dev/null 2>&1; then
    REAL_NVD=$(ls /dev/nvidia[0-9]* 2>/dev/null | head -n 1)
    [ -n "$REAL_NVD" ] && sudo ln -snf "$REAL_NVD" /dev/nvidia0 || true
fi
if [ ! -e /dev/dri/renderD128 ] && ls /dev/dri/renderD* 1> /dev/null 2>&1; then
    REAL_REND=$(ls /dev/dri/renderD* 2>/dev/null | grep -v 128 | head -n 1)
    [ -n "$REAL_REND" ] && sudo ln -snf "$REAL_REND" /dev/dri/renderD128 || true
fi
if [ ! -e /dev/dri/card0 ] && ls /dev/dri/card* 1> /dev/null 2>&1; then
    REAL_CARD=$(ls /dev/dri/card* 2>/dev/null | grep -E '/dev/dri/card[0-9]+' | grep -v card0 | head -n 1)
    [ -n "$REAL_CARD" ] && sudo ln -snf "$REAL_CARD" /dev/dri/card0 || true
fi

# 锁定 CUDA 和 Vulkan 的唯一设备 (跟随挂载逻辑)
export GPU_INDEX="${GPU_INDEX:-0}"
if command -v nvidia-smi >/dev/null; then
    export GPU_SELECT="$(nvidia-smi --query-gpu=uuid --id="${GPU_INDEX}" --format=csv,noheader | head -n1 2>/dev/null)"
    if [ -n "${GPU_SELECT}" ]; then
        export CUDA_VISIBLE_DEVICES="${GPU_SELECT}"
        export MESA_VK_DEVICE_SELECT="$(nvidia-smi --query-gpu=pci.bus_id --id=${GPU_INDEX} --format=csv,noheader | head -n1 2>/dev/null | sed 's/00000000://' | tr '[:upper:]' '[:lower:]')"
        export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1
    fi
fi

# Start KWin Wayland Standalone on the unified dbus session with root privileges (DRM Master)
sudo -E kwin_wayland --virtual --xwayland &
KWIN_PID=$!

echo "Session Running. Wait for KWin to spin up..."
read
