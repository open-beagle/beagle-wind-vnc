#!/bin/bash
# =============================================================================
# Beagle Wind - Wayland MVP Monitor Daemon (AI Checkpoint 5.2.4)
# =============================================================================
OUTPUT_DIR="/tmp/mvp_report_524"
METRICS_LOG="$OUTPUT_DIR/metrics.csv"
CRASH_LOG="$OUTPUT_DIR/crashes.log"
WEBRTC_LOG="$OUTPUT_DIR/webrtc_drops.log"

mkdir -p "$OUTPUT_DIR"
echo "Timestamp,CPU_Usage(%),Memory_Usage(%),NVENC_Util(%),Frames_Dropped" > "$METRICS_LOG"
> "$CRASH_LOG"
> "$WEBRTC_LOG"

echo "=========================================================="
echo " [AI 侦察探针] MVP 5.2.4 联调监控已启动"
echo " 目标：记录 10 分钟内 Wayland + Pipewire + NVENC 性能抖动"
echo " 日志管线输出至: $OUTPUT_DIR"
echo "=========================================================="

# 持续采样 600 秒 (10分钟)
for i in {1..600}; do
    TIME=$(date +%H:%M:%S)
    
    # 捕获 CPU 与 内存 (聚焦 kwin_wayland 与 GStreamer)
    SYS_CPU=$(top -b -n 1 | grep "Cpu(s)" | awk '{print $2}')
    SYS_MEM=$(free -m | awk '/Mem:/ { printf("%.1f", $3/$2 * 100) }')
    
    # 捕获显卡 NVENC 视频编码硬件单元负载
    # (有些非特权容器内无法调用 dmon，这里提供兼容性探测)
    if command -v nvidia-smi &> /dev/null; then
        NVENC=$(nvidia-smi -q -d UTILIZATION | grep "Encoder" | head -n 1 | awk '{print $3}')
        if [ -z "$NVENC" ]; then NVENC="0"; fi
    else
        NVENC="N/A"
    fi

    # WebRTC 丢包状态与 Gstreamer 异常下推拦截
    # (提取系统日志中可能的流毁坏与断流信息)
    journalctl -n 20 --no-pager | grep -iE "gstreamer|webrtc|format|error|pipeline" >> "$WEBRTC_LOG" 2>/dev/null || true
    
    echo "$TIME, $SYS_CPU, $SYS_MEM, $NVENC, N/A" >> "$METRICS_LOG"
    
    echo -ne "采样中... [$i/600] 秒  (当前 NVENC: $NVENC% | CPU: $SYS_CPU%)\r"
    sleep 1
done

echo -e "\n\n[*] 采样结束！正在收集段错误(Segfault)与高危 Dump..."
dmesg -T | grep -iE "segfault|trap|wayland|pipewire" > "$CRASH_LOG" 2>/dev/null || true

echo "=========================================================="
echo " [AI 侦察汇报] 数据收集完毕！"
echo " 请大主程核查后将 $OUTPUT_DIR 的异样日志交给我分析！"
echo "=========================================================="
