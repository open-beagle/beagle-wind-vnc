# Node/Angular Builder
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-lutris-latest
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}
COPY --chown=1000:1000 ./nvidia/egl/selkies-gstreamer-entrypoint.sh /etc/beagle-wind-vnc/selkies-gstreamer-entrypoint.sh


ARG DEBIAN_FRONTEND=noninteractive
RUN sudo sed -i 's/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/g' /etc/apt/sources.list.d/*.list && \
  sudo sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu/https:\/\/mirrors.tuna.tsinghua.edu.cn\/ubuntu/g' /etc/apt/sources.list.d/ubuntu.sources
