#!/bin/bash
set -e

# =============================================================================
# BDWIND 操作系统库安装脚本 (Arch Linux版)
#
# 基于 os-libraries-install.sh，完全移植到 Arch Linux
# 不安装 NVIDIA VAAPI Driver（及其依赖的系统 GStreamer 包）。
# NVIDIA VAAPI Driver 改由 bdwind-nvidia-vaapi-driver-install.sh 单独安装，
# 使用自编译 GStreamer 1.28.2 编译，避免系统包版本冲突。
# =============================================================================

# 启用 multilib 仓库，以支持 32 位运行库 (给 Steam/Wine 使用)
echo "[multilib]" >> /etc/pacman.conf
echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
sed -i '/\[options\]/a DisableDownloadTimeout' /etc/pacman.conf || true

# 安装基础操作系统包
pacman -Syu --noconfirm \
  cups \
  cups-filters \
  cups-pdf \
  alsa-utils \
  file \
  gnupg \
  curl \
  wget \
  bzip2 \
  gzip \
  xz \
  unrar \
  zip \
  unzip \
  zstd \
  gcc \
  git \
  bind \
  coturn \
  jq \
  python \
  python-numpy \
  nano \
  vim \
  htop \
  ttf-dejavu \
  gnu-free-fonts \
  ttf-hack \
  ttf-liberation \
  noto-fonts \
  noto-fonts-cjk \
  noto-fonts-emoji \
  ttf-ubuntu-font-family \
  lame \
  less \
  ffmpeg \
  libpulse \
  supervisor \
  net-tools \
  pkgconf \
  mesa-utils \
  libva-mesa-driver \
  libva-utils \
  vdpauinfo \
  libvdpau \
  vulkan-radeon \
  vulkan-intel \
  vulkan-tools \
  vulkan-headers \
  ocl-icd \
  clinfo \
  xorg-xkbcomp \
  xorg-xauth \
  xdg-user-dirs \
  xdg-utils \
  xorg-fonts-misc \
  xorg-xinit \
  xsettingsd \
  xorg-xrandr \
  nginx \
  openbsd-netcat \
  pipewire \
  pipewire-pulse \
  pipewire-alsa \
  pipewire-jack \
  pipewire-v4l2 \
  libcamera \
  wireplumber

# =============================================================================
# NGINX配置优化
# =============================================================================
sed -i -e 's/\/var\/log\/nginx\/access\.log/\/dev\/stdout/g' -e 's/\/var\/log\/nginx\/error\.log/\/dev\/stderr/g' -e 's/\/run\/nginx\.pid/\/tmp\/nginx\.pid/g' /etc/nginx/nginx.conf
echo "error_log /dev/stderr;" >>/etc/nginx/nginx.conf

# =============================================================================
# 32 位架构库支持 (仅针对 x86_64)
# =============================================================================
if [ "$(uname -m)" = "x86_64" ]; then
  pacman -S --noconfirm \
    intel-gpu-tools \
    nvtop \
    lib32-mesa \
    lib32-vulkan-radeon \
    lib32-vulkan-intel \
    lib32-libva-mesa-driver \
    lib32-vulkan-icd-loader \
    lib32-glibc \
    lib32-libxcb \
    lib32-libxext \
    lib32-libx11 \
    lib32-libdrm \
    lib32-libglvnd \
    lib32-zlib
fi

# =============================================================================
# 系统清理和配置
# =============================================================================
rm -rf /var/cache/pacman/pkg/* /var/log/* /tmp/* /var/tmp/*

echo "/usr/local/nvidia/lib" >>/etc/ld.so.conf.d/nvidia.conf
echo "/usr/local/nvidia/lib64" >>/etc/ld.so.conf.d/nvidia.conf
ldconfig || true

# OpenCL配置
mkdir -pm755 /etc/OpenCL/vendors
echo "libnvidia-opencl.so.1" >/etc/OpenCL/vendors/nvidia.icd

# Vulkan配置 (Arch 路径)
mkdir -pm755 /etc/vulkan/icd.d/
cat >/etc/vulkan/icd.d/nvidia_icd.json <<EOF
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "libGLX_nvidia.so.0",
        "api_version" : "1.3.268"
    }
}
EOF

# EGL配置
mkdir -pm755 /usr/share/glvnd/egl_vendor.d/
cat >/usr/share/glvnd/egl_vendor.d/10_nvidia.json <<EOF
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "libEGL_nvidia.so.0"
    }
}
EOF
