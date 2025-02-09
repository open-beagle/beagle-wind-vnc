# Node/Angular Builder
ARG BASE=ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241103070509
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

COPY ./addons/gstreamer-web/src/. /opt/gst-web/
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server

COPY --chown=1000:1000 ./nvidia/egl/entrypoint.sh /etc/entrypoint.sh
COPY --chown=1000:1000 ./nvidia/egl/selkies-gstreamer-entrypoint.sh /etc/selkies-gstreamer-entrypoint.sh
COPY --chown=1000:1000 ./nvidia/egl/steam-game.sh /etc/steam-game.sh
COPY --chown=1000:1000 ./nvidia/egl/supervisord.conf /etc/supervisord.conf

COPY --chown=1000:1000 ./src/selkies_gstreamer/. /usr/local/lib/python3.12/dist-packages/selkies_gstreamer/

ARG SOCKS5_PROXY_LOCAL=socks5://10.3.242.28:1080
RUN export DEBIAN_FRONTEND=noninteractive && \
  sudo apt update && \
  sudo apt install --no-install-recommends -y \
    xboxdrv \
    joystick \
    jstest-gtk \
    mangohud \
    gamemode && \
  sudo apt install --no-install-recommends -y \
    fonts-noto-cjk \
    fonts-wqy-zenhei \
    fonts-wqy-microhei && \
  curl -x $SOCKS5_PROXY_LOCAL \
    -o /tmp/steam_latest.deb \
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

ENV PATH="/usr/local/games:/usr/games:$PATH"
RUN sudo chown -R root:root /opt/gst-web && \
  sudo sed -i 's/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/g' /etc/apt/sources.list.d/*.list && \
  sudo sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu/https:\/\/mirrors.tuna.tsinghua.edu.cn\/ubuntu/g' /etc/apt/sources.list.d/ubuntu.sources && \
  sudo chmod +x /etc/entrypoint.sh && \
  sudo chmod +x /etc/selkies-gstreamer-entrypoint.sh && \
  sudo chmod +x /etc/steam-game.sh && \
  sudo chmod -f 755 /etc/supervisord.conf
