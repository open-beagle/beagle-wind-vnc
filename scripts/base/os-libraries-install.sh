#!/bin/bash
set -e

# =============================================================================
# 操作系统库安装脚本
# 安装操作系统库或包
# =============================================================================

# 安装基础操作系统包
# 分类说明：
# - 系统管理工具：software-properties-common, build-essential, ca-certificates, file, gnupg, curl, wget, git, dnsutils, coturn, jq, htop, net-tools, packagekit-tools, pkg-config
# - CUPS打印系统：cups-browsed, cups-bsd, cups-common, cups-filters, printer-driver-cups-pdf, python3-cups
# - 音频系统：alsa-base, alsa-utils, libpulse0
# - 基础工具：supervisor, netcat-openbsd
# - 压缩工具：bzip2, gzip, xz-utils, unar, rar, unrar, zip, unzip, zstd
# - 开发工具：gcc, libc6-dev, libelf-dev, libglvnd-dev
# - Python环境：python3, python3-numpy
# - 文本编辑器：nano, vim, less
# - 字体包：fonts-dejavu, fonts-freefont-ttf, fonts-hack, fonts-liberation, fonts-noto系列, fonts-opensymbol, fonts-symbola, fonts-ubuntu
# - 多媒体工具：lame, libavcodec-extra
# - 系统服务：supervisor
# - 图形和显示：mesa-utils, mesa-va-drivers, libva2, vainfo, vdpau-driver-all, libvdpau-va-gl1, vdpauinfo, mesa-vulkan-drivers, vulkan-tools, radeontop, libvulkan-dev
# - OpenCL支持：ocl-icd-libopencl1, clinfo
# - X11相关：xkb-data, xauth, xbitmaps, xdg-user-dirs, xdg-utils, xfonts-base, xfonts-scalable, xinit, xsettingsd, libxrandr-dev, x11-xkb-utils, x11-xserver-utils, x11-utils, x11-apps, xserver-xorg-input-all, xserver-xorg-input-wacom, xserver-xorg-video-all, xserver-xorg-video-intel, xserver-xorg-video-qxl
# - NVIDIA驱动依赖：libpci3
# - OpenGL库：libxau6, libxdmcp6, libxcb1, libxext6, libx11-6, libxv1, libxtst6, libdrm2, libegl1, libgl1, libopengl0, libgles1, libgles2, libglvnd0, libglx0, libglu1, libsm6
# - NGINX Web服务器：nginx, apache2-utils
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
# 清理NGINX路径配置
sed -i -e 's/\/var\/log\/nginx\/access\.log/\/dev\/stdout/g' -e 's/\/var\/log\/nginx\/error\.log/\/dev\/stderr/g' -e 's/\/run\/nginx\.pid/\/tmp\/nginx\.pid/g' /etc/nginx/nginx.conf
echo "error_log /dev/stderr;" >>/etc/nginx/nginx.conf

# =============================================================================
# PipeWire和WirePlumber音频系统安装
# =============================================================================
# 添加PipeWire PPA密钥
mkdir -pm755 /etc/apt/trusted.gpg.d
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0xFC43B7352BCC0EC8AF2EEB8B25088A0359807596" | gpg --dearmor -o /etc/apt/trusted.gpg.d/pipewire-debian-ubuntu-pipewire-upstream.gpg
# 添加PipeWire PPA源
mkdir -pm755 /etc/apt/sources.list.d
echo "deb https://ppa.launchpadcontent.net/pipewire-debian/pipewire-upstream/ubuntu $(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"') main" >"/etc/apt/sources.list.d/pipewire-debian-ubuntu-pipewire-upstream-$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"').list"
# 添加WirePlumber PPA源
mkdir -pm755 /etc/apt/sources.list.d
echo "deb https://ppa.launchpadcontent.net/pipewire-debian/wireplumber-upstream/ubuntu $(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"') main" >"/etc/apt/sources.list.d/pipewire-debian-ubuntu-wireplumber-upstream-$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"').list"
# 安装PipeWire和WirePlumber
# 分类说明：
# - PipeWire核心：pipewire（音频和视频处理框架核心）
# - ALSA兼容：pipewire-alsa（ALSA兼容层，让PipeWire作为ALSA后端）
# - 音频客户端库：pipewire-audio-client-libraries（音频客户端开发库）
# - JACK支持：pipewire-jack（JACK音频服务器兼容层）
# - 本地化：pipewire-locales（多语言支持）
# - 视频支持：pipewire-v4l2（Video4Linux2视频设备支持）
# - Vulkan支持：pipewire-vulkan（Vulkan图形API支持）
# - 摄像头支持：pipewire-libcamera（摄像头设备支持）
# - GStreamer集成：gstreamer1.0-libcamera（GStreamer摄像头插件）, gstreamer1.0-pipewire（GStreamer PipeWire插件）
# - PipeWire模块：libpipewire-0.3-modules（PipeWire模块库）, libpipewire-module-x11-bell（X11铃声模块）
# - SPA插件：libspa-0.2-bluetooth（蓝牙SPA插件）, libspa-0.2-jack（JACK SPA插件）, libspa-0.2-modules（SPA模块库）
# - WirePlumber：wireplumber（会话管理器）, wireplumber-locales（WirePlumber多语言支持）
# - GObject绑定：gir1.2-wp-0.5（WirePlumber GObject内省绑定）
apt-get update
apt-get install --no-install-recommends -y \
  pipewire \
  pipewire-alsa \
  pipewire-audio-client-libraries \
  pipewire-jack \
  pipewire-locales \
  pipewire-v4l2 \
  pipewire-vulkan \
  pipewire-libcamera \
  gstreamer1.0-libcamera \
  gstreamer1.0-pipewire \
  libpipewire-0.3-modules \
  libpipewire-module-x11-bell \
  libspa-0.2-bluetooth \
  libspa-0.2-jack \
  libspa-0.2-modules \
  wireplumber \
  wireplumber-locales \
  gir1.2-wp-0.5

# =============================================================================
# 仅适用于x86_64架构的包
# =============================================================================
# 分类说明：
# - GPU监控工具：intel-gpu-tools（Intel GPU监控和调试工具）, nvtop（NVIDIA GPU监控工具）
# - 视频加速驱动：va-driver-all（所有VA-API驱动）, i965-va-driver-shaders（Intel i965着色器驱动）, intel-media-va-driver-non-free（Intel媒体VA驱动）
# - 32位视频加速驱动：va-driver-all:i386, i965-va-driver-shaders:i386, intel-media-va-driver-non-free:i386, libva2:i386, vdpau-driver-all:i386, mesa-vulkan-drivers:i386, libvulkan-dev:i386
# - 32位基础库：libc6:i386（32位C库）, libxau6:i386（32位X11认证库）, libxdmcp6:i386（32位X11显示管理器控制协议库）, libxcb1:i386（32位X11 C绑定库）, libxext6:i386（32位X11扩展库）, libx11-6:i386（32位X11客户端库）, libxv1:i386（32位X11视频扩展库）, libxtst6:i386（32位X11测试扩展库）
# - 32位图形库：libdrm2:i386（32位DRM库）, libegl1:i386（32位EGL库）, libgl1:i386（32位OpenGL库）, libopengl0:i386（32位OpenGL运行时）, libgles1:i386（32位OpenGL ES 1.x库）, libgles2:i386（32位OpenGL ES 2.x库）, libglvnd0:i386（32位OpenGL供应商中立分发库）, libglx0:i386（32位GLX库）, libglu1:i386（32位OpenGL实用工具库）, libsm6:i386（32位X11会话管理库）
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
# 需要设置内核参数 `nvidia_drm.modeset=1` 才能正确运行
# =============================================================================
# 分类说明：
# - 构建工具：meson（构建系统生成器）
# - GStreamer插件：gstreamer1.0-plugins-bad（GStreamer坏插件集合）, libgstreamer-plugins-bad1.0-dev（GStreamer坏插件开发库）
# - NVIDIA编码支持：libffmpeg-nvenc-dev（NVIDIA硬件编码开发库）
# - 视频加速开发库：libva-dev（VA-API开发库）, libegl-dev（EGL开发库）
if [ "$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '\"')" \> "20.04" ]; then
  # 安装构建依赖
  apt-get update
  apt-get install --no-install-recommends -y \
    meson \
    gstreamer1.0-plugins-bad \
    libffmpeg-nvenc-dev \
    libva-dev \
    libegl-dev \
    libgstreamer-plugins-bad1.0-dev
  # 获取并编译nvidia-vaapi-driver
  NVIDIA_VAAPI_DRIVER_VERSION="$(curl -fsSL "https://api.github.com/repos/elFarto/nvidia-vaapi-driver/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
  cd /tmp
  curl -fsSL "https://github.com/elFarto/nvidia-vaapi-driver/archive/v${NVIDIA_VAAPI_DRIVER_VERSION}.tar.gz" | tar -xzf -
  mv -f nvidia-vaapi-driver* nvidia-vaapi-driver
  cd nvidia-vaapi-driver
  meson setup build
  meson install -C build
  rm -rf /tmp/*
fi

# =============================================================================
# 系统清理和配置
# =============================================================================
# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
# 配置NVIDIA库路径
echo "/usr/local/nvidia/lib" >>/etc/ld.so.conf.d/nvidia.conf
echo "/usr/local/nvidia/lib64" >>/etc/ld.so.conf.d/nvidia.conf
# =============================================================================
# OpenCL配置
# =============================================================================
# 手动配置OpenCL
mkdir -pm755 /etc/OpenCL/vendors
echo "libnvidia-opencl.so.1" >/etc/OpenCL/vendors/nvidia.icd
# =============================================================================
# Vulkan配置
# =============================================================================
# 手动配置Vulkan
VULKAN_API_VERSION=$(dpkg -s libvulkan1 | grep -oP 'Version: [0-9|\.]+' | grep -oP '[0-9]+(\.[0-9]+)(\.[0-9]+)')
mkdir -pm755 /etc/vulkan/icd.d/
echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
        \"library_path\": \"libGLX_nvidia.so.0\",\n\
        \"api_version\" : \"${VULKAN_API_VERSION}\"\n\
    }\n\
}" >/etc/vulkan/icd.d/nvidia_icd.json
# =============================================================================
# EGL配置
# =============================================================================
# 手动配置EGL
mkdir -pm755 /usr/share/glvnd/egl_vendor.d/
echo "{\n\
    \"file_format_version\" : \"1.0.0\",\n\
    \"ICD\": {\n\
        \"library_path\": \"libEGL_nvidia.so.0\"\n\
    }\n\
}" >/usr/share/glvnd/egl_vendor.d/10_nvidia.json
