#!/bin/bash
# =============================================================================
# Hyprland Wrapper — P8 独立觉醒协议
# Hyprland 作为容器的根 Wayland 合成器（无 Gamescope）
# =============================================================================

# GBM 三重拦截（NVIDIA CDI 容器下 GBM LINEAR flag 修复）
if [ -f /opt/gstreamer/patches/aquamarine_cdi_fix.so ]; then
    echo "[hyprland-wrapper] Loading aquamarine_cdi_fix.so"
    export LD_PRELOAD="/opt/gstreamer/patches/aquamarine_cdi_fix.so${LD_PRELOAD:+:${LD_PRELOAD}}"
elif [ -f /opt/gstreamer/patches/gbm_linear_fix.so ]; then
    echo "[hyprland-wrapper] Loading gbm_linear_fix.so"
    export LD_PRELOAD="/opt/gstreamer/patches/gbm_linear_fix.so${LD_PRELOAD:+:${LD_PRELOAD}}"
fi

# §30.1 源码编译版 Aquamarine（headless DRM render node 支持）
if [ -f /opt/aquamarine/lib/libaquamarine.so ]; then
    echo "[hyprland-wrapper] Using compiled Aquamarine"
    export LD_LIBRARY_PATH="/opt/aquamarine/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi

# Hyprland Direct — 独立模式（headless 后端）
unset WAYLAND_DISPLAY
unset DISPLAY
# 不设置 AQ_DRM_DEVICES，让 Aquamarine 自动回退到 headless 后端
# （CDI 容器中 libseat 无法接管 DRM 设备）

# 视觉净空指令（Visual Clearance Protocol） 
# 1. 强制内核态无指针环境，切断一切硬件鼠标游标平面渲染
export WLR_NO_HARDWARE_CURSORS=1

# [BEAGLE-WIND] Start seatd so libinput can access /dev/input devices
# Without a seat manager, Hyprland's libinput backend won't initialize
sudo seatd -g input -u beagle &
sleep 0.3
export LIBSEAT_BACKEND=seatd

# Ensure PipeWire virtual routing exists BEFORE Hyprland executes applications (like Chromium)
pactl list short sinks | grep -q VirtualSink || pactl load-module module-null-sink sink_name=VirtualSink sink_properties="device.description=Virtual_Sink" || true
pactl set-default-sink VirtualSink || true
pactl set-default-source VirtualSink.monitor || true

# 后台启动 Hyprland
/usr/bin/Hyprland "$@" 2>/tmp/hyprland-stderr.log &
HYPR_PID=$!

# 等待 Hyprland socket 就绪
echo "[hyprland-wrapper] Waiting for Hyprland socket..."
for i in $(seq 1 30); do
    if ls ${XDG_RUNTIME_DIR}/wayland-* 1>/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

# 等待 hyprctl 可用
sleep 2
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t ${XDG_RUNTIME_DIR}/hypr/ 2>/dev/null | head -1)

if [ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    echo "[hyprland-wrapper] Creating headless output 1920x1080@60..."
    hyprctl output create headless 2>/dev/null
    sleep 1
    # 获取创建的输出名称并配置分辨率
    OUTPUT_NAME=$(hyprctl -j monitors 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['name'] if d else '')" 2>/dev/null)
    if [ -n "$OUTPUT_NAME" ]; then
        hyprctl keyword monitor "${OUTPUT_NAME},1920x1080@60,0x0,1" 2>/dev/null
        echo "[hyprland-wrapper] Output ${OUTPUT_NAME} configured: 1920x1080@60"
    else
        hyprctl keyword monitor ",1920x1080@60,0x0,1" 2>/dev/null
        echo "[hyprland-wrapper] Output configured with wildcard"
    fi
fi

wait $HYPR_PID
