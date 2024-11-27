# Node/Angular Builder
ARG BASE=ghcr.io/selkies-project/nvidia-glx-desktop:24.04-20241103070505
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

COPY ./gstreamer-web/src/. /opt/gst-web/

RUN sudo chown -R root:root /opt/gst-web
