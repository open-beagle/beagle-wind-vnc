# Node/Angular Builder
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-lutris-latest
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

ARG DEBIAN_FRONTEND=noninteractive
RUN sudo sed -i 's/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/g' /etc/apt/sources.list.d/*.list && \
  sudo sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu/https:\/\/mirrors.tuna.tsinghua.edu.cn\/ubuntu/g' /etc/apt/sources.list.d/ubuntu.sources

# Copy joystick-server
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
RUN sudo chmod +x /usr/bin/joystick-server

# Copy selkies_gstreamer
COPY ./src/selkies_gstreamer/. /usr/local/lib/python3.12/dist-packages/selkies_gstreamer/
