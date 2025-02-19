FROM ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-latest

LABEL maintainer="https://github.com/open-beagle"

COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
COPY --chown=1000:1000 ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh

ARG DEBIAN_FRONTEND=noninteractive
# Install Steam and other packages
RUN sudo apt update && \
  # Install Joystick
  sudo apt install -y \
  xboxdrv \
  joystick \
  jstest-gtk \
  mangohud \
  gamemode && \
  # Install Winetricks
  sudo curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  sudo chmod -f 755 /usr/bin/winetricks && \
  sudo curl -o /usr/share/bash-completion/completions/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion"  && \
  # Install Protontricks
  sudo apt install -y pipx && \
  sudo pipx ensurepath && \
  sudo pipx install protontricks && \    
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
  # Install BaiduDisk
  curl -o /tmp/baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  sudo apt install -y /tmp/baidunetdisk_4.17.7_amd64.deb && \
  rm -f /tmp/baidunetdisk_4.17.7_amd64.deb &&  \
  # Clean up
  sudo apt clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

ENV PATH="/usr/local/games:/usr/games:$PATH"
