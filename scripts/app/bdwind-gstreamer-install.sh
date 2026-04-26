#!/bin/bash
set -e

# =============================================================================
# Selkies-GStreamer安装脚本
# 安装最新版本的Selkies-GStreamer构建、Python应用程序和Web应用程序
# 应与Selkies-GStreamer文档保持一致
# =============================================================================

# 安装GStreamer 1.28.2 运行时依赖包
# 彻底清理了 1.22 时代的遗留依赖，移除了庞大的 -dev 开发包和 x264/x265 CLI 工具。
# 这些包是通过 ldd 直接比对 bdwind-gstreamer 1.28.2 tarball 内所有的 .so 精准备齐的运行库。
# 注意：许多基础显示库 (libdrm2, libegl1 等) 已经在 bdwind-os-libraries-install.sh 预先安装，此处理仅补充 GStreamer 独有库。

apt-get update && apt-get install --no-install-recommends -y \
  xclip \
  libnvrtc12 \
  libnvrtc-builtins12.0 \
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
  libasound2t64 \
  jackd2 \
  libjack-jackd2-0 \
  libpulse0 \
  libopus0 \
  libvpx9 \
  libx264-164 \
  libx265-199 \
  libaom3 \
  libsvtav1enc1d1 \
  libopenh264-7 \
  libnice10 \
  libsoup-3.0-0 \
  libwebrtc-audio-processing1 \
  liborc-0.4-0t64 \
  libsrtp2-1 \
  libgraphene-1.0-0 \
  libgssdp-1.6-0 \
  libgupnp-1.6-0 \
  libgupnp-igd-1.6-0 \
  libbrotli1 \
  xcvt \
  wayland-protocols \
  libwayland-client0 \
  libwayland-server0 \
  libwayland-cursor0 \
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

# 为 NVENC 和 cudanvrtc 构建默认的 libnvrtc.so 动态软链接
# 由于通过 APT 安装的 libnvrtc12 只提供 libnvrtc.so.12，GStreamer cudanvrtc 加载模块底层强制需要去 dlopen(libnvrtc.so)
ln -sf /usr/lib/x86_64-linux-gnu/libnvrtc.so.12 /usr/lib/x86_64-linux-gnu/libnvrtc.so || true

# =============================================================================
# 自动获取并安装私有化定制 Beagle-Wind (GLX) 组件
# =============================================================================

# 私有化定制：使用刚编译好的 1.28.2 专用底座与 Python 包合集
cd /tmp
echo "Downloading custom bdwind-gstreamer 1.28.2 tarball..."
curl -O -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gstreamer-1.28.2-ubuntu24.04.tar.gz"
echo "Extracting GStreamer Custom Engines into /opt..."
tar -xzf bdwind-gstreamer-1.28.2-ubuntu24.04.tar.gz -C /opt
rm -f bdwind-gstreamer-1.28.2-ubuntu24.04.tar.gz

# 安装 Python 控制端（四大魔改补丁已预打包在 tarball 的 dist-packages 中）
echo "Installing custom bdwind_gstreamer Python environment..."
# 1. 暂时移出预置的含有 GitHub URL 强制要求的主引擎包（改为移至隔离目录以保持其合法的 .whl 格式命名）
mkdir -p /tmp/bdwind_gstreamer_tmp
mv /opt/gstreamer/lib/python3/dist-packages/bdwind_gstreamer*.whl /tmp/bdwind_gstreamer_tmp/

# 2. 从本地依赖预置目录全集安装（引入 --ignore-installed 防止 Debian 系统级别包缺失 RECORD 导致卸载失败）
pip3 install --root-user-action=ignore --ignore-installed --no-cache-dir /opt/gstreamer/lib/python3/dist-packages/*.whl

# 3. 此时所有依赖环境实际上都已完全满足，我们使用 --no-deps 跳过严格的流式底层校验包，单独安装主引擎
pip3 install --root-user-action=ignore --ignore-installed --no-cache-dir --no-deps /tmp/bdwind_gstreamer_tmp/*.whl

# 4. 清扫刚刚的临时安装主包提取出物
rm -rf /tmp/bdwind_gstreamer_tmp

# 获取自研风洞前端 (webrtc 子模块打包的静态资源)
BDWIND_WEBRTC_VERSION="1.28.2"
mkdir -p /opt/bdwind/webrtc
echo "Downloading custom bdwind-webrtc ${BDWIND_WEBRTC_VERSION} Web Frontend..."
curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-webrtc-${BDWIND_WEBRTC_VERSION}.tar.gz" | tar -xzf - -C /opt/bdwind/webrtc || true

# 清理解压包、系统缓存和临时文件
rm -f /tmp/bdwind-gstreamer-1.28.2-ubuntu24.04.tar.gz
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/*
# 由于脚本本身是以 --mount=bind 挂载在 /tmp 下的，清理其余垃圾时允许遇到挂载占用而忽略报错
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true
