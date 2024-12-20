# Use ubuntu:24.04 as the base image
ARG BASE=ubuntu:24.04
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

# Copy the ubuntu.sources file
COPY nvidia/weston/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

ENV DEBIAN_FRONTEND noninteractive
RUN apt update && \
    apt install -y --no-install-recommends ubuntu-desktop gnome-core gnome-terminal xrdp \
    && apt autoremove -y && \
    apt clean

# 配置 xrdp
COPY nvidia/weston/xrdp.ini /etc/xrdp/

# 暴露端口
EXPOSE 3389

# 启动命令
CMD ["/usr/bin/startwm.sh"]