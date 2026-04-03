#!/bin/bash
set -ex

# =============================================================================
# Wayland & PipeWire Installation Script
# =============================================================================

apt-get update
apt-get install -y --no-install-recommends \
    wayland-protocols \
    libwayland-client0 \
    libwayland-server0 \
    libwayland-egl1 \
    xwayland \
    pipewire \
    pipewire-bin \
    pipewire-pulse \
    pipewire-audio \
    wireplumber \
    libpipewire-0.3-dev \
    libspa-0.2-dev \
    libudev-dev \
    libdrm-dev \
    dbus \
    dbus-user-session \
    dconf-cli \
    python3-pil

# Clean up
apt-get clean && rm -rf /var/lib/apt/lists/*

# 手动物理提取 pipewiresrc 插件，绕过 apt 强制依赖安装 (防止 Ubuntu 在系统中安装 1.24 版本的原生 GStreamer 库污染我们的 1.28.1 隔离环境)
mkdir -p /tmp/gst-pipewire
cd /tmp/gst-pipewire
apt-get update
apt-get download gstreamer1.0-pipewire
dpkg-deb -x gstreamer1.0-pipewire*.deb .
mkdir -p /usr/lib/x86_64-linux-gnu/gstreamer-1.0
cp -a usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstpipewire.so* /usr/lib/x86_64-linux-gnu/gstreamer-1.0/ || true
cd /
rm -rf /tmp/gst-pipewire
apt-get clean && rm -rf /var/lib/apt/lists/*
