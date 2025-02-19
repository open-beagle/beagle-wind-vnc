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
  cd /tmp && \
  # Install Lutris
  LUTRIS_VERSION="$(curl -fsSL "https://api.github.com/repos/lutris/lutris/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
  curl -o lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v${LUTRIS_VERSION}/lutris_${LUTRIS_VERSION}_all.deb" && \
  sudo apt-get install --no-install-recommends -y ./lutris.deb && \
  rm -f lutris.deb && \
  rm -f vscode.deb && \
  # Install BaiduDisk
  curl -o baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  sudo apt-get install --no-install-recommends -y ./baidunetdisk_4.17.7_amd64.deb && \
  rm -f baidunetdisk_4.17.7_amd64.deb &&  \
  # Install Winetricks
  sudo curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  sudo chmod -f 755 /usr/bin/winetricks && \
  sudo curl -o /usr/share/bash-completion/completions/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks.bash-completion"  && \
  # Install Joystick
  sudo apt-get install --no-install-recommends -y xboxdrv joystick jstest-gtk mangohud gamemode && \
  # Clean up
  sudo apt-get clean && \
  sudo rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*