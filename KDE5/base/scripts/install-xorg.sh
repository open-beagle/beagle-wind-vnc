#!/bin/bash
set -e

# =============================================================================
# X.Org安装脚本 (GLX模式)
# 安装真实的X.Org硬件图形服务器，替代EGL模式中的Xvfb虚拟帧缓冲
# =============================================================================

# 安装X.Org及核心组件
apt-get update
apt-get install --no-install-recommends -y \
    xorg \
    xterm \
    xserver-xorg-core

# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
