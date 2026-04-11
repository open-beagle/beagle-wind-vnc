#!/bin/bash

# =============================================================================
# Beagle-Wind Desktop Wayland Entrypoint (P8: Supervisord Managed Architecture)
# =============================================================================

set -e
trap "echo TRAPed signal" HUP INT QUIT TERM

# 1. 确保环境变量与基础目录
mkdir -p "${XDG_RUNTIME_DIR}"

sudo chown -f "$(id -nu):$(id -ng)" ~ || true
sudo rm -rf /tmp/.ICE-unix /tmp/.X* ~/.cache || true
sudo rm -f ${XDG_RUNTIME_DIR}/wayland-* ${XDG_RUNTIME_DIR}/gamescope-* ${XDG_RUNTIME_DIR}/kwin* ${XDG_RUNTIME_DIR}/pipewire-* ${XDG_RUNTIME_DIR}/bus || true
sudo mkdir -pm 1777 /tmp/.ICE-unix /tmp/.X11-unix || true

# 1.5 从 /etc/beagle-wind-vnc/user/ 分发默认用户配置到 ~/.config/
# 仅在目标文件不存在时拷贝，保留用户已有的自定义配置
mkdir -p ~/.config/hypr ~/.config/waybar
cp -n /etc/beagle-wind-vnc/user/hypr/* ~/.config/hypr/ 2>/dev/null || true
cp -n /etc/beagle-wind-vnc/user/waybar/* ~/.config/waybar/ 2>/dev/null || true

ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone >/dev/null || true

export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
export DISPLAY="${DISPLAY:-:20}"

# =============================================================================
# 2. Arch Linux DRI/Input 设备权限修复
# =============================================================================
# Arch 容器内的 video/input 组可能与 Ubuntu 宿主机 UID 不一致，强行修复权限
sudo chmod 666 /dev/dri/card* /dev/dri/renderD* || true
sudo chmod 0666 /dev/uinput || true

# Boot udev daemon to ensure libinput detects newly created uinput event devices
sudo /lib/systemd/systemd-udevd -d || true
sudo mkdir -p /var/run/dbus || true

# =============================================================================
# 3. 提供给 Supervisord 子进程的全局变量
# =============================================================================
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"

# ⚠️ 注意事项：不能预设 WAYLAND_DISPLAY，让 Gamescope 自由掌控并创建 socket。
unset WAYLAND_DISPLAY

# 强制 NVIDIA Allocator 与 DRM Backend (P8 headless 下取消此项，否则 Aquamarine 无法分配 buffer)
# export GBM_BACKEND=nvidia-drm
# export __GLX_VENDOR_LIBRARY_NAME=nvidia

export AQ_DRM_FORMAT=AR30
export AQ_NO_MODIFIERS=1
export AQ_NO_ATOMIC=1

# =============================================================================
# 4. 放行给 Supervisord 去接管所有后台链路 
# =============================================================================
echo "[Entrypoint] Environment initialized. Handing over control to Supervisord..."
exec "$@"
