#!/bin/bash
set -e

# =============================================================================
# Selkies-GStreamer安装脚本
# 安装最新版本的Selkies-GStreamer构建、Python应用程序和Web应用程序
# 应与Selkies-GStreamer文档保持一致
# =============================================================================

# 安装GStreamer依赖包
# 分类说明：
# - Python开发环境：python3-pip（Python包管理器）, python3-dev（Python开发头文件）, python3-gi（Python GObject内省绑定）, python3-setuptools（Python包安装工具）, python3-wheel（Python轮子格式支持）
# - 系统库：libgcrypt20（GNU加密库）, libgirepository-1.0-1（GObject内省库）, glib-networking（GLib网络库）, libglib2.0-0（GLib核心库）, libgudev-1.0-0（GObject udev绑定）
# - 音频系统：alsa-utils（ALSA音频工具）, jackd2（JACK音频服务器）, libjack-jackd2-0（JACK音频库）, libpulse0（PulseAudio库）, libopus0（Opus音频编解码器）
# - 视频编解码器：libvpx-dev（VP8/VP9视频编解码器开发库）, x264（H.264视频编码器）, x265（H.265视频编码器）
# - 图形和显示：libdrm2（DRM库）, libegl1（EGL库）, libgl1（OpenGL库）, libopengl0（OpenGL运行时）, libgles1（OpenGL ES 1.x库）, libgles2（OpenGL ES 2.x库）, libglvnd0（OpenGL供应商中立分发库）, libglx0（GLX库）
# - Wayland支持：wayland-protocols（Wayland协议）, libwayland-dev（Wayland开发库）, libwayland-egl1（Wayland EGL库）
# - X11窗口管理：wmctrl（窗口管理器控制工具）, xsel（X11选择工具）, xdotool（X11自动化工具）
# - X11工具和实用程序：x11-utils（X11实用工具）, x11-xkb-utils（X11键盘工具）, x11-xserver-utils（X11服务器工具）, xserver-xorg-core（X11服务器核心）
# - X11扩展库：libx11-xcb1（X11 XCB库）, libxcb-dri3-0（XCB DRI3库）, libxdamage1（X11损坏扩展库）, libxfixes3（X11修复扩展库）, libxv1（X11视频扩展库）, libxtst6（X11测试扩展库）, libxext6（X11扩展库）
apt-get update && apt-get install --no-install-recommends -y \
  python3-pip \
  python3-dev \
  python3-gi \
  python3-setuptools \
  python3-wheel \
  libgcrypt20 \
  libgirepository-1.0-1 \
  glib-networking \
  libglib2.0-0 \
  libgudev-1.0-0 \
  alsa-utils \
  jackd2 \
  libjack-jackd2-0 \
  libpulse0 \
  libopus0 \
  libvpx-dev \
  x264 \
  x265 \
  libdrm2 \
  libegl1 \
  libgl1 \
  libopengl0 \
  libgles1 \
  libgles2 \
  libglvnd0 \
  libglx0 \
  wayland-protocols \
  libwayland-dev \
  libwayland-egl1 \
  wmctrl \
  xsel \
  xdotool \
  x11-utils \
  x11-xkb-utils \
  x11-xserver-utils \
  xserver-xorg-core \
  libx11-xcb1 \
  libxcb-dri3-0 \
  libxdamage1 \
  libxfixes3 \
  libxv1 \
  libxtst6 \
  libxext6

# 根据Ubuntu版本安装不同的依赖包
# 分类说明：
# - Ubuntu 20.04+专用：xcvt（X11坐标转换工具）, libopenh264-dev（OpenH264编解码器开发库）, svt-av1（SVT-AV1编码器）, aom-tools（AV1编码工具）
# - Ubuntu 20.04及以下：mesa-utils-extra（Mesa图形工具扩展包）
if [ "$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '\"')" \> "20.04" ]; then
  apt-get install --no-install-recommends -y xcvt libopenh264-dev svt-av1 aom-tools
else
  apt-get install --no-install-recommends -y mesa-utils-extra
fi

# =============================================================================
# 自动获取并安装最新版本的Selkies-GStreamer组件
# =============================================================================

# 获取最新版本号
SELKIES_VERSION="$(curl -fsSL "https://api.github.com/repos/selkies-project/selkies-gstreamer/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
# 下载并安装GStreamer核心组件
cd /opt
curl -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/gstreamer-selkies_gpl_v${SELKIES_VERSION}_ubuntu$(grep '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '\"')_$(dpkg --print-architecture).tar.gz" | tar -xzf -
# 下载并安装Python包
cd /tmp
curl -O -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl"
pip3 install --no-cache-dir --force-reinstall "selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl" "websockets<14.0"
rm -f "selkies_gstreamer-${SELKIES_VERSION}-py3-none-any.whl"
# 下载并安装Web应用程序
cd /opt
curl -fsSL "https://github.com/selkies-project/selkies-gstreamer/releases/download/v${SELKIES_VERSION}/selkies-gstreamer-web_v${SELKIES_VERSION}.tar.gz" | tar -xzf -
# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
