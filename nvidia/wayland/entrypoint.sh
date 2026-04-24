#!/bin/bash

# =============================================================================
# Beagle-Wind Desktop Wayland Entrypoint (P8: Supervisord Managed Architecture)
# =============================================================================

set -e
trap "echo TRAPed signal" HUP INT QUIT TERM

# 1. 确保环境变量与基础目录
mkdir -p "${XDG_RUNTIME_DIR}"
chmod 0700 "${XDG_RUNTIME_DIR}"

sudo chown -f "$(id -nu):$(id -ng)" ~ || true
sudo rm -rf /tmp/.ICE-unix /tmp/.X* ~/.cache || true
sudo rm -f ${XDG_RUNTIME_DIR}/wayland-* ${XDG_RUNTIME_DIR}/gamescope-* ${XDG_RUNTIME_DIR}/kwin* ${XDG_RUNTIME_DIR}/pipewire-* ${XDG_RUNTIME_DIR}/bus || true
sudo mkdir -pm 1777 /tmp/.ICE-unix /tmp/.X11-unix || true

# 1.5 从 /etc/beagle-wind-vnc/user/ 分发默认用户配置到 ~/.config/
# 强制覆盖，确保热更新的配置生效
mkdir -p ~/.config/hypr ~/.config/waybar ~/.config/wofi
cp -a /etc/beagle-wind-vnc/user/hypr/* ~/.config/hypr/ 2>/dev/null || true
cp -a /etc/beagle-wind-vnc/user/waybar/* ~/.config/waybar/ 2>/dev/null || true
cp -a /etc/beagle-wind-vnc/user/wofi/* ~/.config/wofi/ 2>/dev/null || true

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

# [BEAGLE-WIND] Pre-create uinput virtual input device BEFORE Hyprland starts.
# In containers without devtmpfs, /dev/input/ is not auto-populated by udevd.
# We create the UInput device in a background process that keeps the fd open,
# then manually mknod /dev/input/eventX and write udev database entries
# so libinput discovers it at Hyprland init.
python3 -c "
import evdev, os, time, subprocess, signal
caps = {
    evdev.ecodes.EV_KEY: list(range(1, 249)) + [evdev.ecodes.BTN_LEFT, evdev.ecodes.BTN_RIGHT, evdev.ecodes.BTN_MIDDLE, evdev.ecodes.BTN_SIDE, evdev.ecodes.BTN_EXTRA],
    evdev.ecodes.EV_REL: [evdev.ecodes.REL_X, evdev.ecodes.REL_Y, evdev.ecodes.REL_WHEEL, evdev.ecodes.REL_HWHEEL],
}
ui = evdev.UInput(events=caps, name='bdwind-virtual-input-seed', version=0x3)
time.sleep(0.5)
for d in sorted(os.listdir('/sys/class/input')):
    if not d.startswith('event'): continue
    np = f'/sys/class/input/{d}/device/name'
    if os.path.exists(np) and open(np).read().strip() == 'bdwind-virtual-input-seed':
        mm = open(f'/sys/class/input/{d}/dev').read().strip()
        major, minor = mm.split(':')
        devnode = f'/dev/input/{d}'
        subprocess.run(['sudo', 'mknod', devnode, 'c', major, minor], check=False)
        subprocess.run(['sudo', 'chmod', '666', devnode], check=False)
        # Write udev database entry so libinput recognizes the device
        subprocess.run(['sudo', 'mkdir', '-p', '/run/udev/data'], check=False)
        udev_data = f'/run/udev/data/c{major}:{minor}'
        udev_content = 'E:ID_INPUT=1\nE:ID_INPUT_KEY=1\nE:ID_INPUT_KEYBOARD=1\nE:ID_INPUT_MOUSE=1\nE:ID_INPUT_POINTINGSTICK=1\n'
        subprocess.run(['sudo', 'sh', '-c', f'echo \"{udev_content}\" > {udev_data}'], check=False)
        print(f'[entrypoint] Created {devnode} + udev data for libinput', flush=True)
        break
signal.pause()
" &
UINPUT_SEED_PID=$!
echo "[entrypoint] uinput seed process PID=$UINPUT_SEED_PID"
sleep 1
sudo mkdir -p /var/run/dbus || true
sudo systemd-machine-id-setup || true
sudo dbus-uuidgen --ensure || true

# =============================================================================
# 3. 提供给 Supervisord 子进程的全局变量
# =============================================================================
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export NO_PROXY="localhost,127.0.0.1,127.0.0.0/8,::1,/tmp/"

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

# =============================================================================
# [VISUAL CLEARANCE PROTOCOL] Pre-compile Transparent XCursor BEFORE Hyprland Boot
# =============================================================================
mkdir -p /home/beagle/.icons/transparent/cursors
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==" | base64 -d > /tmp/empty.png
echo "24 0 0 /tmp/empty.png" > /tmp/cursor.in
xcursorgen /tmp/cursor.in /home/beagle/.icons/transparent/cursors/left_ptr 2>/dev/null || true
cp -a /home/beagle/.icons/transparent/cursors/left_ptr /home/beagle/.icons/transparent/cursors/arrow 2>/dev/null || true
cp -a /home/beagle/.icons/transparent/cursors/left_ptr /home/beagle/.icons/transparent/cursors/pointer 2>/dev/null || true
cp -a /home/beagle/.icons/transparent/cursors/left_ptr /home/beagle/.icons/transparent/cursors/default 2>/dev/null || true
echo -e "[Icon Theme]\nName=transparent\nInherits=" > /home/beagle/.icons/transparent/index.theme
sudo chown -R beagle:beagle /home/beagle/.icons || true

exec "$@"
