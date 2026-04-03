#!/bin/bash
set -ex

# =============================================================================
# KDE Plasma 6 & Native Wayland Environment
# =============================================================================

apt-get update
# Install KDE Plasma 6, KWin Wayland, and Portals
apt-get install -y --no-install-recommends \
    plasma-desktop \
    plasma-workspace \
    kwin-wayland \
    kwayland-integration \
    xdg-desktop-portal-kde \
    xdg-desktop-portal-wlr \
    dolphin \
    konsole \
    fcitx5 \
    fcitx5-chinese-addons

# Default Wayland behavior for KWin
cat >/etc/xdg/kwinrc <<EOF
[Compositing]
Enabled=true
OpenGLIsUnsafe=false
EOF

# Fcitx5 Wayland configuration
cat >/etc/environment.d/fcitx5-wayland.conf <<EOF
GTK_IM_MODULE=fcitx5
QT_IM_MODULE=fcitx5
XMODIFIERS=@im=fcitx5
SDL_IM_MODULE=fcitx
GLFW_IM_MODULE=ibus
EOF

apt-get clean && rm -rf /var/lib/apt/lists/*
