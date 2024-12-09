# Node/Angular Builder
ARG BASE=ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241103070509
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

COPY ./addons/gstreamer-web/src/. /opt/gst-web/

COPY --chown=1000:1000 ./nvidia/egl/entrypoint.sh /etc/entrypoint.sh
COPY --chown=1000:1000 ./nvidia/egl/selkies-gstreamer-entrypoint.sh /etc/selkies-gstreamer-entrypoint.sh

# COPY --chown=1000:1000 ./src/selkies_gstreamer/webrtc_input.py /usr/local/lib/python3.12/dist-packages/selkies_gstreamer/webrtc_input.py

RUN sudo chown -R root:root /opt/gst-web && \
  sudo sed -i 's/ppa.launchpadcontent.net/launchpad.proxy.ustclug.org/g' /etc/apt/sources.list.d/*.list && \
  sudo sed -i 's/http:\/\/archive.ubuntu.com\/ubuntu/https:\/\/mirrors.tuna.tsinghua.edu.cn\/ubuntu/g' /etc/apt/sources.list.d/ubuntu.sources && \
  sudo chmod +x /etc/entrypoint.sh && \
  sudo chmod +x /etc/selkies-gstreamer-entrypoint.sh
