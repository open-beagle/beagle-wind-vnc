#!/bin/bash
set -ex

# =============================================================================
# Wayland & PipeWire Installation Script (Arch Linux)
# =============================================================================

pacman -S --noconfirm \
    wayland-protocols \
    wayland \
    xorg-xwayland \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    pipewire-jack \
    pipewire-audio \
    wireplumber \
    gst-plugin-pipewire \
    systemd \
    dbus \
    dconf \
    python-pillow

# Clean up
rm -rf /var/cache/pacman/pkg/*
