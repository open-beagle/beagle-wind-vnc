#!/bin/bash
set -e

# =============================================================================
# BDWIND 操作系统库安装脚本
#
# 基于 os-libraries-install.sh，唯一区别：
# 不安装 NVIDIA VAAPI Driver（及其依赖的系统 GStreamer 包）。
# NVIDIA VAAPI Driver 改由 bdwind-nvidia-vaapi-driver-install.sh 单独安装，
# 使用自编译 GStreamer 1.24.6 编译，避免系统 GStreamer 1.24.2 版本冲突。
# =============================================================================

# 安装基础操作系统包
apt-get update
apt-get install --no-install-recommends -y \
  software-properties-common \
  build-essential \
  ca-certificates \
  cups-browsed \
  cups-bsd \
  cups-common \
  cups-filters \
  printer-driver-cups-pdf \
  alsa-base \
  alsa-utils \
  file \
  gnupg \
  curl \
  wget \
  bzip2 \
  gzip \
  xz-utils \
  unar \
  rar \
  unrar \
  zip \
  unzip \
  zstd \
  gcc \
  git \
  dnsutils \
  coturn \
  jq \
  python3 \
  python3-cups \
  python3-numpy \
  nano \
  vim \
  htop \
  fonts-dejavu \
  fonts-freefont-ttf \
  fonts-hack \
  fonts-liberation \
  fonts-noto \
  fonts-noto-cjk \
  fonts-noto-cjk-extra \
  fonts-noto-color-emoji \
  fonts-noto-extra \
  fonts-noto-ui-extra \
  fonts-noto-hinted \
  fonts-noto-mono \
  fonts-noto-unhinted \
  fonts-opensymbol \
  fonts-symbola \
  fonts-ubuntu \
  lame \
  less \
  libavcodec-extra \
  libpulse0 \
  supervisor \
  net-tools \
  packagekit-tools \
  pkg-config \
  mesa-utils \
  mesa-va-drivers \
  libva2 \
  vainfo \
  vdpau-driver-all \
  libvdpau-va-gl1 \
  vdpauinfo \
  mesa-vulkan-drivers \
  vulkan-tools \
  radeontop \
  libvulkan-dev \
  ocl-icd-libopencl1 \
  clinfo \
  xkb-data \
  xauth \
  xbitmaps \
  xdg-user-dirs \
  xdg-utils \
  xfonts-base \
  xfonts-scalable \
  xinit \
  xsettingsd \
  libxrandr-dev \
  x11-xkb-utils \
  x11-xserver-utils \
  x11-utils \
  x11-apps \
  xserver-xorg-input-all \
  xserver-xorg-input-wacom \
  xserver-xorg-video-all \
  xserver-xorg-video-intel \
  xserver-xorg-video-qxl \
  libc6-dev \
  libpci3 \
  libelf-dev \
  libglvnd-dev \
  libxau6 \
  libxdmcp6 \
  libxcb1 \
  libxext6 \
  libx11-6 \
  libxv1 \
  libxtst6 \
  libdrm2 \
  libegl1 \
  libgl1 \
  libopengl0 \
  libgles1 \
  libgles2 \
  libglvnd0 \
  libglx0 \
  libglu1 \
  libsm6 \
  nginx \
  apache2-utils \
  netcat-openbsd

# =============================================================================
# NGINX配置优化
# =============================================================================
sed -i -e 's/\/var\/log\/nginx\/access\.log/\/dev\/stdout/g' -e 's/\/var\/log\/nginx\/error\.log/\/dev\/stderr/g' -e 's/\/run\/nginx\.pid/\/tmp\/nginx\.pid/g' /etc/nginx/nginx.conf
echo "error_log /dev/stderr;" >>/etc/nginx/nginx.conf

# =============================================================================
# PipeWire和WirePlumber音频系统安装
# =============================================================================
apt-get update
apt-get install --no-install-recommends -y \
  pipewire \
  pipewire-alsa \
  pipewire-audio-client-libraries \
  pipewire-jack \
  pipewire-v4l2 \
  pipewire-libcamera \
  libpipewire-0.3-modules \
  libspa-0.2-bluetooth \
  libspa-0.2-jack \
  libspa-0.2-modules \
  wireplumber \
  gir1.2-wp-0.5

# =============================================================================
# 仅适用于x86_64架构的包
# =============================================================================
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  dpkg --add-architecture i386
  apt-get update
  apt-get install --no-install-recommends -y \
    intel-gpu-tools \
    nvtop \
    va-driver-all \
    i965-va-driver-shaders \
    intel-media-va-driver-non-free \
    va-driver-all:i386 \
    i965-va-driver-shaders:i386 \
    intel-media-va-driver-non-free:i386 \
    libva2:i386 \
    vdpau-driver-all:i386 \
    mesa-vulkan-drivers:i386 \
    libvulkan-dev:i386 \
    libc6:i386 \
    libxau6:i386 \
    libxdmcp6:i386 \
    libxcb1:i386 \
    libxext6:i386 \
    libx11-6:i386 \
    libxv1:i386 \
    libxtst6:i386 \
    libdrm2:i386 \
    libegl1:i386 \
    libgl1:i386 \
    libopengl0:i386 \
    libgles1:i386 \
    libgles2:i386 \
    libglvnd0:i386 \
    libglx0:i386 \
    libglu1:i386 \
    libsm6:i386
fi

# =============================================================================
# NVIDIA VAAPI驱动安装
# [BDWIND] 此段已移至 bdwind-nvidia-vaapi-driver-install.sh
# 使用自编译 GStreamer 1.24.6 编译，不安装系统 GStreamer 包
# =============================================================================

# =============================================================================
# 系统清理和配置
# =============================================================================
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
echo "/usr/local/nvidia/lib" >>/etc/ld.so.conf.d/nvidia.conf
echo "/usr/local/nvidia/lib64" >>/etc/ld.so.conf.d/nvidia.conf

# OpenCL配置
mkdir -pm755 /etc/OpenCL/vendors
echo "libnvidia-opencl.so.1" >/etc/OpenCL/vendors/nvidia.icd

# Vulkan配置
VULKAN_API_VERSION=$(dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+' | grep -oP '[0-9]+(\.[0-9]+)(\.[0-9]+)')
mkdir -pm755 /etc/vulkan/icd.d/
cat >/etc/vulkan/icd.d/nvidia_icd.json <<EOF
{
    "file_format_version" : "1.0.0",
    "ICD": {
        "library_path": "libGLX_nvidia.so.0",
        "api_version" : "${VULKAN_API_VERSION}"
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
