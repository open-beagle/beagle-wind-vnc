#!/bin/bash

# =============================================================================
# Beagle-Wind Desktop Wayland Entrypoint
# =============================================================================

set -e
trap "echo TRAPed signal" HUP INT QUIT TERM

# 1. 确保环境变量
# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done
# Clean up sockets from previous runs and set sticky bits for ICE and X11 to prevent DBus IPC failures
sudo rm -rf /tmp/.ICE-unix /tmp/.X* ~/.cache || true
sudo mkdir -pm 1777 /tmp/.ICE-unix /tmp/.X11-unix || true

chown -f "$(id -nu):$(id -ng)" ~ || true
sudo rm -rf /tmp/.X* ~/.cache || true
sudo rm -f ${XDG_RUNTIME_DIR}/wayland-* ${XDG_RUNTIME_DIR}/kwin* || true
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone >/dev/null || true

export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
export WLR_NO_HARDWARE_CURSORS=1
export WAYLAND_DISPLAY="wayland-0"
export DISPLAY="${DISPLAY:-:20}"

mkdir -p ~/.config ~/.local/share ~/.cache
chmod 700 ~/.config ~/.local ~/.cache

# Fix uinput permissions for Phase 4 WebRTC / Auto-Accept script
sudo chmod 0666 /dev/uinput || true
sudo mkdir -p /var/run/dbus || true

# Boot udev daemon to ensure libinput detects newly created uinput event devices
sudo /lib/systemd/systemd-udevd -d || true

# 2. 启动原生 Wayland / X11 引擎

# =============================================================================
# NVIDIA Allocator 原生硬件加速配置 (P4 Wayland 零拷贝核心)
# =============================================================================

# 1. GBM 链接对齐：引导 Mesa Loader 找到 nvidia-allocator.so
sudo mkdir -p /usr/lib/x86_64-linux-gnu/gbm || true
sudo ln -sf /usr/lib/x86_64-linux-gnu/libnvidia-allocator.so.1 \
       /usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so || true

# 2. 强制 KWin 驱动后端向 EGL 与 NVIDIA 生态靠拢
export KWIN_OPENGL_INTERFACE=egl
export GBM_BACKEND=nvidia-drm
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export KWIN_DRM_NO_DIRECT_SCANOUT=1

# 3. 剥离 KWin 的特权 capabilities 保证 LD_PRELOAD 生效
sudo setcap -r /usr/bin/kwin_wayland 2>/dev/null || true

# Export DBus session bus address so KWin joins the global container session
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus"
export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
export PIPEWIRE_REMOTE="pipewire-0"

sudo mkdir -p /tmp/.X11-unix
sudo chmod 1777 /tmp/.X11-unix
for i in {0..19}; do
    sudo touch "/tmp/.X11-unix/X$i"
    sudo chown ubuntu:ubuntu "/tmp/.X11-unix/X$i" || true
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
    fi
fi

if [ "${XDG_SESSION_TYPE}" = "wayland" ]; then
    # ==========================================
    # 次世代云游戏路线: Labwc (wlroots)
    # ==========================================
    echo "Starting Native wlroots Wayland Compositor (labwc)..."

    export XDG_CURRENT_DESKTOP=wlroots
    export XDG_SESSION_DESKTOP=wlroots
    export SLURP_COMMAND="echo HEADLESS-1"
    
    # 热更新自动补齐依赖 (兼容基础旧镜像直起)
    if ! command -v labwc >/dev/null; then
        echo "Installing labwc & portal hot-reload dependencies..."
        sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y labwc wlr-randr xdg-desktop-portal-wlr
    fi

    # ⚡ 每次启动都强制写入 Portal 配置（文件名必须是 config 而非 config.ini）
    # xdg-desktop-portal-wlr 使用 GLib g_key_file 只查找 "config"，不认 "config.ini"
    sudo mkdir -p /etc/xdg/xdg-desktop-portal-wlr
    printf '[screencast]\noutput_name=HEADLESS-1\nmax_fps=60\nchooser_type=none\nforce_mod_linear=1\n' | sudo tee /etc/xdg/xdg-desktop-portal-wlr/config >/dev/null
    # 同时写入用户级配置作为双重保障
    mkdir -p ~/.config/xdg-desktop-portal-wlr
    printf '[screencast]\noutput_name=HEADLESS-1\nmax_fps=60\nchooser_type=none\nforce_mod_linear=1\n' > ~/.config/xdg-desktop-portal-wlr/config

    # 强制 Portal 路由：ScreenCast 走 wlr 后端，阻止 KDE portal 抢占
    sudo mkdir -p /usr/share/xdg-desktop-portal
    printf '[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.ScreenCast=wlr\norg.freedesktop.impl.portal.Screenshot=wlr\n' | sudo tee /usr/share/xdg-desktop-portal/portals.conf >/dev/null
    
    # 授权所有 render 和 card node（撤回降级妥协，为硬件直通铺路）
    sudo chmod 666 /dev/dri/* || true
    
    # ⚡ 关键：屏蔽上游传染的客户端 Wayland 平台参数，防止 labwc 将自己误认为子客户端
    unset EGL_PLATFORM
    
    # 威兰德方案 A: 强制线性内存沉淀，骗过官僚审查，正面硬刚 DMABUF
    export WLR_DRM_NO_MODIFIERS=1  # 配合 force_mod_linear 的底层双保险
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export KHRONOS_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json

    export WLR_RENDERER=gles2
    export WLR_RENDER_DRM_DEVICE=/dev/dri/renderD130
    
    # BDWIND: Fix invisible mouse cursor in zero-copy Wayland pipeline by enforcing software cursors
    export WLR_NO_HARDWARE_CURSORS=1
    
    # Fix libinput event permissions mapped from kubernetes host bounds (106 is host input group)
    sudo groupadd -g 106 host_input || true
    sudo usermod -aG 106 ubuntu || true

    # Start seatd as root to provide proper input grouping, bypassing libseat's VT requirement
    sudo seatd -g video > /tmp/seatd.log 2>&1 &
    
    EGL_LOG_LEVEL=debug WAYLAND_DEBUG=1 LIBSEAT_BACKEND=seatd SEATD_SOCK=/run/seatd.sock WLR_LIBINPUT_NO_DEVICES=1 WLR_BACKENDS=headless,libinput labwc -d > /tmp/labwc_debug.log 2>&1 &
    LABWC_PID=$!
    
    # 等待 wayland-0 socket
    echo 'Waiting for Wayland Socket...'
    export WLR_NO_HARDWARE_CURSORS=1
export WAYLAND_DISPLAY=wayland-0
    until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; do sleep 0.5; done
    echo 'wayland-0 Server is ready!'
    
    # 将环境变量注入 DBus，让后续按需启动的所有服务（如 PipeWire, Portal）能感知 Wayland
    export PIPEWIRE_RUNTIME_DIR="${XDG_RUNTIME_DIR}"
    if command -v dbus-update-activation-environment >/dev/null; then
        dbus-update-activation-environment --systemd \
            WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_DESKTOP \
            XDG_SESSION_TYPE DISPLAY PIPEWIRE_RUNTIME_DIR SLURP_COMMAND \
            WLR_DRM_NO_MODIFIERS GBM_BACKEND __GLX_VENDOR_LIBRARY_NAME \
            __NV_PRIME_RENDER_OFFLOAD __VK_LAYER_NV_optimus \
            KHRONOS_ICD_FILENAMES __EGL_VENDOR_LIBRARY_FILENAMES
    fi
    
    # 设置初始分辨率
    wlr-randr --output HEADLESS-1 --custom-mode ${DISPLAY_SIZEW:-1920}x${DISPLAY_SIZEH:-1080}@60 || true
    
    # 启动 XWayland 兼容层
    Xwayland "${DISPLAY}" &
    
    # 启动轻量级面板与壁纸
    selkies-desktop &
    
    # 稍微给点时间让 Xwayland 等基础服务完成建立
    echo "Waiting for Pipewire..."
    until [ -S "${XDG_RUNTIME_DIR}/pipewire-0" ]; do sleep 0.5; done
    echo "Pipewire is ready!"

    # 杀掉任何 DBus 自动激活的旧 portal 进程（防止配置未生效的僵尸）
    killall -9 xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-kde 2>/dev/null || true
    sleep 1
    sleep 1

    # 启动 D-Bus ScreenCast Portals (完全静默、免交互)
    /usr/libexec/xdg-desktop-portal -v > /tmp/xdp_main.log 2>&1 &
    sleep 2
    # 取消硬件干扰，写入 维兰德 的 force_mod_linear 规则

    # 正面迎接 DMABUF，撤下 bwrap 泡泡！
    WAYLAND_DEBUG=1 WAYLAND_DISPLAY=wayland-0 /usr/libexec/xdg-desktop-portal-wlr -l DEBUG -r > /tmp/wlr.log 2>&1 &    
    # 阻塞挂起守护进程
    wait $LABWC_PID
else
    # ==========================================
    # 绝境突围：嵌套 Wayland 硬件合体架构 (Option D fallback for X11)
    # ==========================================
    # 获取并转换 Bus ID (Xorg 认得格式)
    HEX_ID="$(nvidia-smi --query-gpu=pci.bus_id --id=${GPU_INDEX} --format=csv,noheader | head -n1 2>/dev/null)"
    if [ -n "$HEX_ID" ]; then
        IFS=":." ARR_ID=(${HEX_ID})
        unset IFS
        BUS_ID="PCI:$(printf '%u' 0x${ARR_ID[1]})@$(printf '%u' 0x${ARR_ID[0]}):$(printf '%u' 0x${ARR_ID[2]}):$(printf '%u' 0x${ARR_ID[3]})"
    else
        BUS_ID=""
    fi

    export DISPLAY="${DISPLAY:-:20}"
    if command -v cvt >/dev/null 2>&1; then
        MODELINE="$(cvt -r ${DISPLAY_SIZEW:-1920} ${DISPLAY_SIZEH:-1080} ${DISPLAY_REFRESH:-60} | sed -n 2p)"
    else
        MODELINE="Modeline \"1920x1080\"  138.50  1920 1968 2000 2080  1080 1083 1088 1111 +hsync -vsync"
    fi

    # Generate a high-bandwidth EDID that supports up to 4K@60Hz via DisplayPort timing
    # The old Dell U2412M EDID was limited to 165MHz TMDS pixel clock, capping resolution at 1024x768
    sudo python3 << 'EDID_SCRIPT'
import struct, sys

def checksum(data):
    return (256 - sum(data) % 256) % 256

edid = bytearray(128)
edid[0:8] = b'\x00\xff\xff\xff\xff\xff\xff\x00'
edid[8] = 0x59; edid[9] = 0x54
edid[10] = 0x01; edid[11] = 0x00
edid[12:16] = b'\x01\x00\x00\x00'
edid[16] = 1; edid[17] = 34  # 2024
edid[18] = 1; edid[19] = 3
edid[20] = 0x80
edid[21] = 53; edid[22] = 30
edid[23] = 120
edid[24] = 0xEE
edid[25:35] = bytes([0xA5, 0xC4, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])
edid[35] = 0x21; edid[36] = 0x08; edid[37] = 0x00
edid[38] = 0xD1; edid[39] = 0xC0  # 1920x1080@60
edid[40] = 0xA9; edid[41] = 0xC0  # 1680x1050@60
edid[42] = 0x81; edid[43] = 0xC0  # 1280x720@60
edid[44] = 0xB3; edid[45] = 0x00  # 1792x1344@60
edid[46] = 0x01; edid[47] = 0x01
edid[48] = 0x01; edid[49] = 0x01
edid[50] = 0x01; edid[51] = 0x01
edid[52] = 0x01; edid[53] = 0x01
pclk = 14850
edid[54] = pclk & 0xFF; edid[55] = (pclk >> 8) & 0xFF
edid[56] = 0x80  # H active low
edid[57] = 0x18  # H blanking low
edid[58] = 0x71  # H active/blanking high
edid[59] = 0x38  # V active low
edid[60] = 0x2D  # V blanking low
edid[61] = 0x40  # V active/blanking high
edid[62] = 0x58  # H sync offset low
edid[63] = 0x2C  # H sync width low
edid[64] = 0x45  # V sync offset/width low
edid[65] = 0x00  # sync high bits
edid[66] = 0x56; edid[67] = 0x50  # image size
edid[68] = 0x21  # image size high
edid[69] = 0x00; edid[70] = 0x00  # border
edid[71] = 0x1E  # flags: +hsync +vsync
edid[72:90] = b'\x00\x00\x00\xFC\x00Virtual 4K DP\n'
edid[90:108] = bytes([0x00,0x00,0x00,0xFD,0x00, 24, 120, 15, 136, 60, 0x00,0x0A,0x20,0x20,0x20,0x20,0x20,0x20])
edid[108:126] = b'\x00\x00\x00\xFF\x00BDWIND-VRT-001\n'
edid[126] = 0
edid[127] = checksum(edid[:127])

with open('/etc/X11/edid.bin', 'wb') as f:
    f.write(bytes(edid))
print('EDID written: %d bytes, checksum OK' % len(edid))
EDID_SCRIPT

    # Generate /etc/X11/xorg.conf
    cat <<EOF | sudo tee /etc/X11/xorg.conf >/dev/null
Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0"
    InputDevice    "Keyboard0" "CoreKeyboard"
    InputDevice    "Mouse0" "CorePointer"
EndSection

Section "InputDevice"
    Identifier     "Mouse0"
    Driver         "mouse"
    Option         "Protocol" "auto"
    Option         "Device" "/dev/input/mice"
    Option         "Emulate3Buttons" "no"
    Option         "ZAxisMapping" "4 5"
EndSection

Section "InputDevice"
    Identifier     "Keyboard0"
    Driver         "kbd"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
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
    Option         "UseDisplayDevice" "DFP-0"
    Option         "ConnectedMonitor" "DFP-0"
    Option         "CustomEDID" "DFP-0:/etc/X11/edid.bin"
    Option         "IgnoreEDID" "False"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Depth       24
        Virtual     8192 4096
        Modes      "1920x1080"
    EndSubSection
EndSection

Section "ServerFlags"
    Option         "DontVTSwitch" "True"
    Option         "AllowMouseOpenFail" "True"
    Option         "AutoAddGPU" "False"
EndSection
EOF

    echo "deb http://mirrors.aliyun.com/ubuntu/ jammy main universe" | sudo tee /etc/apt/sources.list.d/jammy.list >/dev/null
    sudo sed -i 's/archive.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    sudo sed -i 's/security.ubuntu.com/mirrors.aliyun.com/g' /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
    sudo apt-get update >/dev/null 2>&1
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3-prometheus-client python3-msgpack xdotool xclip kwin-x11 xserver-xorg-input-evdev xserver-xorg-input-kbd xserver-xorg-input-mouse >/dev/null 2>&1 || true

    sudo /lib/systemd/systemd-udevd --daemon >/dev/null 2>&1 || true

    sudo mkdir -p /etc/X11/xorg.conf.d
    cat <<'EVDEV_EOF' | sudo tee /etc/X11/xorg.conf.d/99-evdev-override.conf >/dev/null
Section "InputClass"
    Identifier "evdev catchall"
    MatchIsPointer "on"
    MatchIsKeyboard "on"
    Driver "evdev"
EndSection

Section "InputClass"
    Identifier "evdev touchpad catchall"
    MatchIsTouchpad "on"
    Driver "evdev"
EndSection
EVDEV_EOF

    # 启动原生 X11 硬件底座
    sudo ln -snf /dev/ptmx /dev/tty7 || true
    sudo ln -snf /usr/lib/xorg/modules/extensions/libglxserver_nvidia.so /usr/lib/xorg/modules/extensions/libglx.so 2>/dev/null || true
    sudo /usr/lib/xorg/Xorg "${DISPLAY}" vt7 -noreset -novtswitch -sharevts -nolisten "tcp" -ac -dpi "${DISPLAY_DPI:-96}" +extension "COMPOSITE" +extension "DAMAGE" +extension "GLX" +extension "RANDR" +extension "RENDER" +extension "MIT-SHM" +extension "XFIXES" &
    XORG_PID=$!

    echo 'Waiting for X Socket...'
    until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done
    echo 'X Server is ready!'

    export XDG_SESSION_ID="${DISPLAY#*:}"
    export QT_LOGGING_RULES="${QT_LOGGING_RULES:-*.debug=false;qt.qpa.*=false}"
    export XDG_SESSION_TYPE=x11
    export QT_XCB_GL_INTEGRATION=xcb_glx
    export KWIN_COMPOSE=O2
    export KWIN_OPENGL_INTERFACE=glx
    export KWIN_X11_NO_SYNC_TO_VBLANK=1
    unset WAYLAND_DISPLAY
    unset QT_QPA_PLATFORM
    unset EGL_PLATFORM

    # Force proper 1080p rendering on Virtual Monitor
    XRANDR_CONFIG="$(echo ${MODELINE} | sed 's/^Modeline //')"
    xrandr --display "${DISPLAY}" --newmode ${XRANDR_CONFIG} || true
    XRANDR_MODE="$(echo ${MODELINE} | awk '{print $2}' | tr -d '"')"
    xrandr --display "${DISPLAY}" --addmode DFP-0 "${XRANDR_MODE}" || true
    xrandr --display "${DISPLAY}" --output DFP-0 --mode "${XRANDR_MODE}" || true

    dbus-update-activation-environment --all 2>/dev/null || true

    # 启动原生 KDE Activity Manager 否则 Plasma Shell 崩溃黑屏
    /usr/lib/x86_64-linux-gnu/libexec/kactivitymanagerd &
    sleep 1

    # 启动 KDE X11 桌面
    echo "Starting Native KDE Plasma X11 Compositor..."
    /usr/bin/startplasma-x11 &
    KWIN_PID=$!
    read
fi
