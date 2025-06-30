#!/bin/bash
set -e

# =============================================================================
# VirtualGL安装脚本
# 安装VirtualGL并使库可用于预加载
# =============================================================================

# 获取最新版本的VirtualGL
cd /tmp
VIRTUALGL_VERSION="$(curl -fsSL "https://api.github.com/repos/VirtualGL/virtualgl/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
# 根据架构安装不同版本的VirtualGL
if [ "$(dpkg --print-architecture)" = "amd64" ]; then
  # 为AMD64架构添加32位支持并安装VirtualGL
  dpkg --add-architecture i386
  curl -fsSL -O "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION}/virtualgl_${VIRTUALGL_VERSION}_amd64.deb"
  curl -fsSL -O "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION}/virtualgl32_${VIRTUALGL_VERSION}_amd64.deb"
  apt-get update
  apt-get install -y --no-install-recommends "./virtualgl_${VIRTUALGL_VERSION}_amd64.deb" "./virtualgl32_${VIRTUALGL_VERSION}_amd64.deb"
  rm -f "virtualgl_${VIRTUALGL_VERSION}_amd64.deb" "virtualgl32_${VIRTUALGL_VERSION}_amd64.deb"
  # 为64位库设置setuid权限
  chmod -f u+s /usr/lib/libvglfaker.so /usr/lib/libvglfaker-nodl.so /usr/lib/libvglfaker-opencl.so /usr/lib/libdlfaker.so /usr/lib/libgefaker.so
  # 为32位库设置setuid权限
  chmod -f u+s /usr/lib32/libvglfaker.so /usr/lib32/libvglfaker-nodl.so /usr/lib32/libvglfaker-opencl.so /usr/lib32/libdlfaker.so /usr/lib32/libgefaker.so
  chmod -f u+s /usr/lib/i386-linux-gnu/libvglfaker.so /usr/lib/i386-linux-gnu/libvglfaker-nodl.so /usr/lib/i386-linux-gnu/libvglfaker-opencl.so /usr/lib/i386-linux-gnu/libdlfaker.so /usr/lib/i386-linux-gnu/libgefaker.so
elif [ "$(dpkg --print-architecture)" = "arm64" ]; then
  # 为ARM64架构安装VirtualGL
  curl -fsSL -O "https://github.com/VirtualGL/virtualgl/releases/download/${VIRTUALGL_VERSION}/virtualgl_${VIRTUALGL_VERSION}_arm64.deb"
  apt-get update
  apt-get install -y --no-install-recommends ./virtualgl_${VIRTUALGL_VERSION}_arm64.deb
  rm -f "virtualgl_${VIRTUALGL_VERSION}_arm64.deb"
  # 为ARM64库设置setuid权限
  chmod -f u+s /usr/lib/libvglfaker.so /usr/lib/libvglfaker-nodl.so /usr/lib/libdlfaker.so /usr/lib/libgefaker.so
fi
# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
