FROM ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-latest

LABEL maintainer="https://github.com/open-beagle"

# Switch to root and standard shell for package installation
USER 0
SHELL ["/bin/sh", "-c"]

COPY --chown=1000:1000 ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh

ARG DEBIAN_FRONTEND=noninteractive

# Wine, Winetricks, and launchers, this process must be consistent with https://wiki.winehq.org/Ubuntu
RUN echo "Install Lutris Environment" && \
  # Install Wine
  mkdir -pm755 /etc/apt/keyrings && \
  curl -o /etc/apt/keyrings/winehq-archive.key -fsSL "https://dl.winehq.org/wine-builds/winehq.key" && \
  curl -o /etc/apt/sources.list.d/winehq-noble.sources -fsSL "https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources" && \
  apt update && \
  apt install --install-recommends -y winehq-staging && \
  apt install --no-install-recommends -y q4wine playonlinux && \
  # Install Winetricks
  curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  chmod -f 755 /usr/bin/winetricks && \
  curl -o /usr/share/bash-completion/completions/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion"  && \
  # Install Joystick
  apt install -y xboxdrv joystick jstest-gtk mangohud gamemode && \
  # Install Lutris (auto-fetch latest version)
  LUTRIS_VERSION="$(curl -fsSL "https://api.github.com/repos/lutris/lutris/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
  curl -o /tmp/lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v${LUTRIS_VERSION}/lutris_${LUTRIS_VERSION}_all.deb" && \
  apt install -y /tmp/lutris.deb && \
  rm -f /tmp/lutris.deb && \  
  # Install BaiduDisk
  curl -o /tmp/baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  apt install -y /tmp/baidunetdisk_4.17.7_amd64.deb && \
  rm -f /tmp/baidunetdisk_4.17.7_amd64.deb &&  \  
  # Clean up
  apt clean && \
  rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# Switch back to non-root user
USER 1000
SHELL ["/bin/sh", "-c"]