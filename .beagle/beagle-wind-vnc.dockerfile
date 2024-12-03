# Node/Angular Builder
ARG BASE=ghcr.io/selkies-project/nvidia-glx-desktop:24.04-20241103070505
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

COPY ./gstreamer-web/src/. /opt/gst-web/

COPY --chown=1000:1000 ./entrypoint.sh /etc/entrypoint.sh

RUN sudo chown -R root:root /opt/gst-web && \
  sudo sed -i 's/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/g' /etc/apt/sources.list.d/*.list && \
  sudo sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu/https:\/\/mirrors.tuna.tsinghua.edu.cn\/ubuntu/g' /etc/apt/sources.list.d/ubuntu.sources && \
  sudo chmod +x /etc/entrypoint.sh
