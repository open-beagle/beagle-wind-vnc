#!/bin/bash
set -e

# =============================================================================
# KasmVNC和RustDesk安装脚本
# 安装KasmVNC Web界面和RustDesk作为备用方案
# =============================================================================

# 获取并安装最新版本的KasmVNC
KASMVNC_VERSION="$(curl -fsSL "https://api.github.com/repos/kasmtech/KasmVNC/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
cd /tmp
curl -o kasmvncserver.deb -fsSL "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"')_${KASMVNC_VERSION}_$(dpkg --print-architecture).deb"
apt-get update
apt-get install --no-install-recommends -y ./kasmvncserver.deb libdatetime-perl
rm -f kasmvncserver.deb
# 获取并安装最新版本的RustDesk
RUSTDESK_VERSION="$(curl -fsSL "https://api.github.com/repos/rustdesk/rustdesk/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
cd /tmp
curl -o rustdesk.deb -fsSL "https://github.com/rustdesk/rustdesk/releases/download/${RUSTDESK_VERSION}/rustdesk-${RUSTDESK_VERSION}-$(uname -m).deb"
apt-get update
apt-get install --no-install-recommends -y ./rustdesk.deb
rm -f rustdesk.deb
# 获取并安装最新版本的yq工具
YQ_VERSION="$(curl -fsSL "https://api.github.com/repos/mikefarah/yq/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')"
cd /tmp
curl -o yq -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)"
install ./yq /usr/bin/
rm -f yq
# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
