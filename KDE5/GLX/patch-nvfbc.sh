#!/bin/bash
# ==============================================================================
# NVFBC GeForce Unlock Patch
#
# NVIDIA 在消费级 GeForce 显卡上禁用了 NVFBC (Frame Buffer Capture) API。
# 此脚本在容器启动时自动检测驱动版本，并应用 nvidia-patch 项目的二进制补丁，
# 将许可检查的条件跳转 (jne) NOP 掉，从而解锁 NVFBC 零拷贝屏幕捕获。
#
# 补丁来源: https://github.com/keylase/nvidia-patch
# 原理: 将 `test eax,eax; jne <offset>` 替换为 `test eax,eax; nop*6`
#
# 策略:
#   1. 首选: 宿主机已预先打补丁 (推荐，一次操作所有容器受益)
#   2. 兜底: 容器启动时拷贝到可写路径 → 打补丁 → ldconfig 优先加载
#
# 注意: libnvidia-fbc.so 由 nvidia-container-toolkit 从宿主机注入，可能以只读挂载。
# ==============================================================================

set -euo pipefail

NVFBC_LIB_DIR="/usr/lib/x86_64-linux-gnu"
PATCH_LIB_DIR="/opt/gstreamer/hooks/lib"
MARKER_FILE="/tmp/.nvfbc-patched"

# 幂等: 如果已经打过补丁，跳过
if [ -f "$MARKER_FILE" ]; then
    echo "[patch-nvfbc] Already patched in this session, skipping."
    exit 0
fi

# 检测驱动版本
DRIVER_VERSION=""
if command -v nvidia-smi &>/dev/null; then
    DRIVER_VERSION=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d '[:space:]')
fi

if [ -z "$DRIVER_VERSION" ]; then
    echo "[patch-nvfbc] WARNING: Cannot detect NVIDIA driver version, skipping."
    exit 0
fi

echo "[patch-nvfbc] Detected NVIDIA driver: $DRIVER_VERSION"

# 查找 libnvidia-fbc.so
NVFBC_SO="${NVFBC_LIB_DIR}/libnvidia-fbc.so.${DRIVER_VERSION}"
if [ ! -f "$NVFBC_SO" ]; then
    echo "[patch-nvfbc] WARNING: $NVFBC_SO not found, skipping."
    exit 0
fi

# nvidia-patch 补丁数据库 (来源: github.com/keylase/nvidia-patch)
declare -A PATCH_DB=(
    # 570.x
    ["570.86.15"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.86.16"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.124.04"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.124.06"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.133.07"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.133.20"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.144"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.148.08"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.153.02"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.158.01"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.169"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.172.08"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.195.03"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["570.211.01"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    # 575.x
    ["575.51.02"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["575.57.08"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["575.64"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["575.64.03"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["575.64.05"]='s/\x85\xc0\x0f\x85\x14\x01\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    # 580.x
    ["580.65.06"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.76.05"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.82.07"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.82.09"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.95.05"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.105.08"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.119.02"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.126.09"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["580.142"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    # 590.x
    ["590.44.01"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["590.48.01"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    # 595.x
    ["595.45.04"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
    ["595.58.03"]='s/\x85\xc0\x0f\x85\xd4\x00\x00\x00\x48/\x85\xc0\x90\x90\x90\x90\x90\x90\x48/g'
)

PATCH="${PATCH_DB[$DRIVER_VERSION]:-}"
if [ -z "$PATCH" ]; then
    echo "[patch-nvfbc] WARNING: No patch for driver $DRIVER_VERSION"
    exit 0
fi

PATCHED_BYTES=$(echo "$PATCH" | awk -F/ '{print $3}')
ORIGINAL_BYTES=$(echo "$PATCH" | awk -F/ '{print $2}')

# 检查: 宿主机是否已预先打过补丁?
if LC_ALL=C grep -qaP "$PATCHED_BYTES" "$NVFBC_SO"; then
    echo "[patch-nvfbc] Host-patched library detected! No runtime patch needed."
    touch "$MARKER_FILE"
    exit 0
fi

if ! LC_ALL=C grep -qaP "$ORIGINAL_BYTES" "$NVFBC_SO"; then
    echo "[patch-nvfbc] WARNING: Expected bytes not found, skipping."
    exit 0
fi

# 兜底策略: 拷贝到可写路径 → 打补丁 → ldconfig 优先加载
echo "[patch-nvfbc] Runtime patching (host library not pre-patched)..."
mkdir -p "$PATCH_LIB_DIR"
cp -a "$NVFBC_SO" "${PATCH_LIB_DIR}/libnvidia-fbc.so.${DRIVER_VERSION}"
sed -i "$PATCH" "${PATCH_LIB_DIR}/libnvidia-fbc.so.${DRIVER_VERSION}"
ln -sf "libnvidia-fbc.so.${DRIVER_VERSION}" "${PATCH_LIB_DIR}/libnvidia-fbc.so.1"

# ldconfig 优先加载补丁目录
echo "$PATCH_LIB_DIR" > /etc/ld.so.conf.d/nvfbc-patch.conf
ldconfig 2>/dev/null || true

if LC_ALL=C grep -qaP "$PATCHED_BYTES" "${PATCH_LIB_DIR}/libnvidia-fbc.so.${DRIVER_VERSION}"; then
    echo "[patch-nvfbc] SUCCESS: NVFBC unlocked (runtime patch at $PATCH_LIB_DIR)"
    touch "$MARKER_FILE"
else
    echo "[patch-nvfbc] ERROR: Patch verification failed."
    exit 1
fi
