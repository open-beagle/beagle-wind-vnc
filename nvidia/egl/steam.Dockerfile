FROM ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-latest

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive

# Install Steam and other packages
RUN export DEBIAN_FRONTEND=noninteractive && \
  sudo apt update && \
  sudo apt install --no-install-recommends -y \
    xboxdrv \
    joystick \
    jstest-gtk \
    mangohud \
    gamemode && \
  curl -o /tmp/steam_latest.deb \
    -fL https://repo.steampowered.com/steam/archive/precise/steam_latest.deb && \
  sudo apt install --no-install-recommends -y \
    /tmp/steam_latest.deb && \
  sudo apt update && \
  sudo apt install -y --no-install-recommends \
    libc6:amd64 libc6:i386 \
    libegl1:amd64 libegl1:i386 \
    libgbm1:amd64 libgbm1:i386 \
    libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
    libgl1:amd64 libgl1:i386 \
    steam-libs-amd64:amd64 steam-libs-i386:i386 \
    xdg-desktop-portal xdg-desktop-portal-kde xterm && \
  sudo apt clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
