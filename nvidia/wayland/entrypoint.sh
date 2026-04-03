#!/bin/bash

# =============================================================================
# Beagle-Wind Desktop Wayland Entrypoint
# =============================================================================

set -e
trap "echo TRAPed signal" HUP INT QUIT TERM

# 1. 确保环境变量
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done

chown -f "$(id -nu):$(id -ng)" ~ || true
rm -rf /tmp/.X* ~/.cache || true
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" | tee /etc/timezone >/dev/null || true

export PATH="${PATH:+${PATH}:}/usr/local/games:/usr/games"
export WAYLAND_DISPLAY="wayland-0"
export DISPLAY="${DISPLAY:-:20}"

mkdir -p ~/.config ~/.local/share ~/.cache
chmod 700 ~/.config ~/.local ~/.cache

# 2. 启动原生 KDE Plasma Wayland 引擎
echo "Starting Native KDE Plasma Wayland Compositor..."

# Start KDE Plasma Wayland Session natively (Without Xvfb, without VirtualGL!)
# This is true zero-copy!
/usr/bin/startplasma-wayland &

echo "Session Running. Press [Return] to exit."
read
