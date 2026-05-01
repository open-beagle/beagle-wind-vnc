#!/bin/bash
set -e

# =============================================================================
# Xvfb安装脚本
# 安装X虚拟帧缓冲服务器
# =============================================================================

# 安装Xvfb
apt-get update
apt-get install --no-install-recommends -y xvfb

# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
