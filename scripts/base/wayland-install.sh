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
    dconf-cli

# Clean up
apt-get clean && rm -rf /var/lib/apt/lists/*
