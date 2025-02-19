FROM ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-latest

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive

# Wine, Winetricks, and launchers, this process must be consistent with https://wiki.winehq.org/Ubuntu
ARG WINE_BRANCH=staging
RUN sudo mkdir -pm755 /etc/apt/keyrings && \
  sudo curl -fsSL -o /etc/apt/keyrings/winehq-archive.key "https://dl.winehq.org/wine-builds/winehq.key" && \
  sudo curl -fsSL -o "/etc/apt/sources.list.d/winehq-$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"').sources" "https://dl.winehq.org/wine-builds/ubuntu/dists/$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"')/winehq-$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"').sources" && \
  sudo apt-get update && \
  sudo apt-get install --install-recommends -y winehq-${WINE_BRANCH} && \
  sudo apt-get install --no-install-recommends -y q4wine playonlinux && \
  LUTRIS_VERSION="$(curl -fsSL "https://api.github.com/repos/lutris/lutris/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
  cd /tmp && \
  curl -o lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v${LUTRIS_VERSION}/lutris_${LUTRIS_VERSION}_all.deb" && \
  sudo apt-get install --no-install-recommends -y ./lutris.deb && \
  rm -f lutris.deb && \
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/* && \
  sudo curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  sudo chmod -f 755 /usr/bin/winetricks && \
  sudo curl -o /usr/share/bash-completion/completions/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion"; 

# 安装手柄驱动
RUN sudo apt update && \
  sudo apt install --no-install-recommends -y \
    xboxdrv \
    joystick \
    jstest-gtk \
    mangohud \
    gamemode && \
  sudo apt clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
