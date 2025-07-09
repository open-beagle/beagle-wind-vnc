ARG BASE_IMAGE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-latest
FROM ${BASE_IMAGE}
ARG BASE_IMAGE

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive

# Wine, Winetricks, and launchers, this process must be consistent with https://wiki.winehq.org/Ubuntu
RUN echo "Install Desktop Environment" && \
  # Install Wine
  sudo mkdir -pm755 /etc/apt/keyrings && \
  sudo curl -o /etc/apt/keyrings/winehq-archive.key -fsSL "https://dl.winehq.org/wine-builds/winehq.key" && \
  sudo curl -o /etc/apt/sources.list.d/winehq-noble.sources -fsSL "https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources" && \
  sudo apt update && \
  sudo apt install --install-recommends -y winehq-staging && \
  sudo apt install --no-install-recommends -y q4wine playonlinux && \
  # Install Winetricks
  sudo curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  sudo chmod -f 755 /usr/bin/winetricks && \
  sudo curl -o /usr/share/bash-completion/completions/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion"  && \
  # Install Joystick
  sudo apt install -y xboxdrv joystick jstest-gtk mangohud gamemode && \
  # Install Lutris
  curl -o /tmp/lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v0.5.18/lutris_0.5.18_all.deb" && \
  sudo apt install -y /tmp/lutris.deb && \
  rm -f /tmp/lutris.deb && \  
  # Install Google Chrome
  curl -o /tmp/google-chrome-stable.deb -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb" && \
  sudo apt install -y /tmp/google-chrome-stable.deb && \
  rm -f /tmp/google-chrome-stable.deb && \
  sudo sed -i '/^Exec=/ s/$/ --password-store=basic --in-process-gpu/' /usr/share/applications/google-chrome.desktop && \
  # Install VSCode
  curl -o /tmp/vscode.deb -fsSL "https://code.visualstudio.com/sha/download?build=stable&os=linux-deb-x64" && \
  sudo apt install -y /tmp/vscode.deb && \
  rm -f /tmp/vscode.deb && \
  # Install BaiduDisk
  curl -o /tmp/baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  sudo apt install -y /tmp/baidunetdisk_4.17.7_amd64.deb && \
  rm -f /tmp/baidunetdisk_4.17.7_amd64.deb &&  \
  # Install Steam
  curl -o /tmp/steam_latest.deb \
  -fL https://repo.steampowered.com/steam/archive/precise/steam_latest.deb && \
  sudo apt install -y /tmp/steam_latest.deb && \
  rm -f /tmp/steam_latest.deb && \
  # Install Steam Launcher
  sudo apt update && \
  sudo apt install -y \
  steam steam-launcher \
  libc6:amd64 libc6:i386 \
  libegl1:amd64 libegl1:i386 \
  libgbm1:amd64 libgbm1:i386 \
  libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
  libgl1:amd64 libgl1:i386 \
  steam-libs-amd64:amd64 steam-libs-i386:i386 \
  xdg-desktop-portal xdg-desktop-portal-kde xterm && \
  # Clean up
  sudo apt clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/* && \
  # 添加 deadsnakes PPA 源（包含最新 Python 版本）
  sudo add-apt-repository -y ppa:deadsnakes/ppa && \
  sudo apt-get update && \
  sudo apt-get install python3.12-venv

# 更换背景
COPY src/img/ /usr/share/wallpapers/Next/contents/images/

ENV PATH="/usr/local/games:/usr/games:$PATH"
