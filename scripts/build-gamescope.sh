#!/bin/bash
# ==============================================================================
# Gamescope 编译脚本 (P8 普罗米修斯行动)
#
# 在 GStreamer 编译基础镜像中编译 Gamescope git 主线，
# 自动检测并修补 wl_compositor 协议版本为 v6，
# 使 Hyprland (Aquamarine 0.10) 能以 Wayland 客户端嵌套运行。
#
# 使用方法:
#   docker run --rm -it \
#     -v $(pwd)/gstreamer:/workspace \
#     -w /workspace \
#     registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:build-1.28.2-arch \
#     bash scripts/build-gamescope.sh
#
# 产物: /workspace/bdwind-gamescope-git-archlinux.tar.gz
# ==============================================================================

set -euo pipefail

GAMESCOPE_SRC="/opt/gamescope-src"
GAMESCOPE_PREFIX="/opt/gamescope"
OUTPUT_DIR="/workspace"
OUTPUT_TAR="bdwind-gamescope-git-archlinux.tar.gz"

echo "============================================="
echo "  Gamescope Build - P8 普罗米修斯行动"
echo "============================================="

# -----------------------------------------------
# Step 1: 更新源码到最新 HEAD
# -----------------------------------------------
echo ">>> Step 1: Updating Gamescope source to latest HEAD..."
cd "${GAMESCOPE_SRC}"
git pull --ff-only || true
git submodule update --init --recursive
echo "    Gamescope commit: $(git rev-parse --short HEAD)"
echo "    Date: $(git log -1 --format=%ci)"

# -----------------------------------------------
# Step 2: 检测并修补 wl_compositor 协议版本
# -----------------------------------------------
echo ">>> Step 2: Checking wl_compositor protocol version..."

# 定位 wl_compositor 注册点 (通常在 src/wlserver.cpp)
WL_COMP_FILE=$(grep -rl "wl_compositor_interface" src/ | head -1)
if [ -z "${WL_COMP_FILE}" ]; then
    echo "!!! ERROR: Cannot find wl_compositor_interface in source. Aborting."
    exit 1
fi

echo "    Found wl_compositor registration in: ${WL_COMP_FILE}"
grep -n "wl_compositor_interface" "${WL_COMP_FILE}"

# 提取当前声明的版本号
CURRENT_VER=$(grep -oP 'wl_compositor_interface,\s*\K[0-9]+' "${WL_COMP_FILE}" | head -1)
echo "    Current wl_compositor version: v${CURRENT_VER:-unknown}"

TARGET_VER=6
if [ -n "${CURRENT_VER}" ] && [ "${CURRENT_VER}" -lt "${TARGET_VER}" ]; then
    echo ">>> PATCHING: wl_compositor v${CURRENT_VER} → v${TARGET_VER}"
    sed -i "s/wl_compositor_interface, ${CURRENT_VER}/wl_compositor_interface, ${TARGET_VER}/" "${WL_COMP_FILE}"
    echo "    Patch applied. Verification:"
    grep -n "wl_compositor_interface" "${WL_COMP_FILE}"
elif [ -n "${CURRENT_VER}" ] && [ "${CURRENT_VER}" -ge "${TARGET_VER}" ]; then
    echo "    ✅ Already at v${CURRENT_VER}, no patch needed."
else
    echo "    ⚠️ Could not detect version, attempting build as-is."
fi

# -----------------------------------------------
# Step 3: 编译
# -----------------------------------------------
echo ">>> Step 3: Configuring Gamescope build..."
meson setup build \
    --prefix="${GAMESCOPE_PREFIX}" \
    --buildtype=release \
    -Dpipewire=enabled \
    || { echo "!!! Meson configure failed"; exit 1; }

echo ">>> Step 3b: Compiling..."
ninja -C build -j$(nproc) \
    || { echo "!!! Ninja build failed"; exit 1; }

echo ">>> Step 3c: Installing to ${GAMESCOPE_PREFIX}..."
ninja -C build install

# -----------------------------------------------
# Step 4: 验证
# -----------------------------------------------
echo ">>> Step 4: Verifying build..."
if [ -x "${GAMESCOPE_PREFIX}/bin/gamescope" ]; then
    echo "    ✅ gamescope binary found at ${GAMESCOPE_PREFIX}/bin/gamescope"
    "${GAMESCOPE_PREFIX}/bin/gamescope" --version || true
else
    echo "!!! ERROR: gamescope binary not found!"
    ls -la "${GAMESCOPE_PREFIX}/bin/" || true
    exit 1
fi

# -----------------------------------------------
# Step 5: 打包产物
# -----------------------------------------------
echo ">>> Step 5: Packaging..."
cd /opt
tar -czf "${OUTPUT_DIR}/${OUTPUT_TAR}" gamescope/
echo "    ✅ Output: ${OUTPUT_DIR}/${OUTPUT_TAR}"
echo "    Size: $(du -h ${OUTPUT_DIR}/${OUTPUT_TAR} | cut -f1)"

echo ""
echo "============================================="
echo "  ✅ Gamescope 编译完成！"
echo "  产物: ${OUTPUT_DIR}/${OUTPUT_TAR}"
echo "  请上传至 OSS:"
echo "  https://cache.ali.wodcloud.com/vscode/bdwind/${OUTPUT_TAR}"
echo "============================================="
