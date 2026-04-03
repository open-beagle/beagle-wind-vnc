# Start from the unified base image.
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-base-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

# Switch to root and standard shell for package installation
USER 0
SHELL ["/bin/sh", "-c"]

# Copy custom scripts needed for steam and install joystick
RUN curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.0.0.tar.gz" | tar -xzf - -C /usr/bin/
COPY --chown=1000:1000 ./nvidia/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
COPY ./nvidia/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh

# Copy required services for supervisord conf.d
COPY ./nvidia/desktop-services.conf /etc/supervisor/conf.d/desktop-services.conf
RUN chmod 755 /usr/bin/joystick-server /etc/beagle-wind-vnc/steam-game.sh /etc/beagle-wind-vnc/bgctl.sh

ARG DEBIAN_FRONTEND=noninteractive
# Install Steam and extra packages missing from base
RUN apt update && \
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
  # Install Joystick and Game tools
  apt install -y xboxdrv joystick jstest-gtk mangohud gamemode jq && \
  apt install -y pipx && pipx ensurepath && pipx install protontricks && \
  # Install Lutris (auto-fetch latest version)
  LUTRIS_VERSION="$(curl -fsSL "https://api.github.com/repos/lutris/lutris/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
  curl -o /tmp/lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v${LUTRIS_VERSION}/lutris_${LUTRIS_VERSION}_all.deb" && \
  apt install -y /tmp/lutris.deb && \
  rm -f /tmp/lutris.deb && \
  # Install Google Chrome
  curl -o /tmp/google-chrome-stable.deb -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb" && \
  apt install -y /tmp/google-chrome-stable.deb && \
  rm -f /tmp/google-chrome-stable.deb && \
  sed -i '/^Exec=/ s/$/ --password-store=basic --in-process-gpu/' /usr/share/applications/google-chrome.desktop && \
  # Install Steam
  curl -o /tmp/steam_latest.deb -fL https://repo.steampowered.com/steam/archive/precise/steam_latest.deb && \
  apt install -y /tmp/steam_latest.deb && rm -f /tmp/steam_latest.deb && \
  apt update && apt install -y steam steam-launcher \
  libc6:amd64 libc6:i386 \
  libegl1:amd64 libegl1:i386 \
  libgbm1:amd64 libgbm1:i386 \
  libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
  libgl1:amd64 libgl1:i386 \
  libvulkan1:amd64 libvulkan1:i386 \
  mesa-vulkan-drivers:amd64 mesa-vulkan-drivers:i386 \
  vulkan-tools \
  steam-libs-amd64:amd64 steam-libs-i386:i386 \
  xdg-desktop-portal xdg-desktop-portal-kde xterm && \
  # Install VSCode (auto-fetch latest version)
  curl -o /tmp/vscode.deb -fsSL "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" && \
  apt install -y /tmp/vscode.deb && rm -f /tmp/vscode.deb && \
  # Install BaiduDisk
  curl -o /tmp/baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  apt install -y /tmp/baidunetdisk_4.17.7_amd64.deb && rm -f /tmp/baidunetdisk_4.17.7_amd64.deb && \
  # Clean up and add deadsnakes PPA for pipx/tools
  add-apt-repository -y ppa:deadsnakes/ppa && apt-get update && apt-get install -y python3.12-venv && \
  apt clean && \
  rm -rf /usr/share/vulkan/icd.d/*.json && \
  rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

COPY src/img/ /usr/share/wallpapers/Next/contents/images/

USER 1000
SHELL ["/bin/sh", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"
