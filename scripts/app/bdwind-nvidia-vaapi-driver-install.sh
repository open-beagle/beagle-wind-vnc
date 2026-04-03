#!/bin/bash
set -e

# =============================================================================
# BDWIND NVIDIA VAAPI Driver Install
#
# 使用自编译 GStreamer 1.24.6（/opt/gstreamer）的头文件和库编译 nvidia-vaapi-driver，
# 不依赖系统 GStreamer 包。
#
# 前置条件：
#   - /opt/gstreamer 已安装（由 bdwind-gstreamer-install.sh 完成）
#   - 系统 GStreamer 包已清理（由 bdwind-os-libraries-install.sh 完成）
#
# 需要设置内核参数 `nvidia_drm.modeset=1` 才能正确运行
# =============================================================================

export DEBIAN_FRONTEND=noninteractive

echo "[BDWIND] Installing NVIDIA VAAPI driver (using self-compiled GStreamer 1.24.6)..."

# 安装编译依赖（不包含系统 GStreamer 包）
# 注意：之前系统 gstreamer1.0-plugins-bad-dev 会隐式拉入一堆基础库的 -dev 包
# 现在使用自编译版本，所以我们必须显式补充 nvidia-vaapi-driver 构建所需的底层 -dev
apt-get update
apt-get install --no-install-recommends -y \
  meson \
  libffmpeg-nvenc-dev \
  libva-dev \
  libegl-dev \
  libdrm-dev \
  libgl-dev

# 设置 PKG_CONFIG_PATH 指向自编译 GStreamer
export PKG_CONFIG_PATH="/opt/gstreamer/lib/x86_64-linux-gnu/pkgconfig:${PKG_CONFIG_PATH}"
export LD_LIBRARY_PATH="/opt/gstreamer/lib/x86_64-linux-gnu:${LD_LIBRARY_PATH}"

# 获取并编译 nvidia-vaapi-driver
NVIDIA_VAAPI_DRIVER_VERSION="$(curl -fsSL "https://api.github.com/repos/elFarto/nvidia-vaapi-driver/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
echo "[BDWIND] Building nvidia-vaapi-driver v${NVIDIA_VAAPI_DRIVER_VERSION}..."
cd /tmp
curl -fsSL "https://github.com/elFarto/nvidia-vaapi-driver/archive/v${NVIDIA_VAAPI_DRIVER_VERSION}.tar.gz" | tar -xzf -
mv -f nvidia-vaapi-driver* nvidia-vaapi-driver
cd nvidia-vaapi-driver
meson setup build
meson install -C build

# 清理编译文件和临时开发头文件库，以大幅减小最终 Docker 镜像体积
# 对应的运行时环境 (libdrm2, libegl1, libva2 等) 均已经在 os-libraries 中全局安装，这里只安全移除 dev/meson。
# libffmpeg-nvenc-dev 仅是 nvidia-codec-sdk 的纯头文件包，它的运行时在 Nvidia 显卡驱动中提供，不需要替代。
apt-get purge -y --auto-remove \
  meson \
  libffmpeg-nvenc-dev \
  libva-dev \
  libegl-dev \
  libdrm-dev \
  libgl-dev

rm -rf /tmp/nvidia-vaapi-driver*
apt-get clean && rm -rf /var/lib/apt/lists/*

echo "[BDWIND] NVIDIA VAAPI driver v${NVIDIA_VAAPI_DRIVER_VERSION} installed successfully."
