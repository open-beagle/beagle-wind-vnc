# Supported base images: Ubuntu 25.04 (Plucky Puffin) for native KDE Plasma 6 & Wayland support
ARG BASE=ubuntu:25.04
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Asia/Shanghai
ENV PASSWD=mypasswd

SHELL ["/bin/sh", "-c"]

RUN --mount=type=bind,source=Wayland/Hyprland/scripts/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/setup-base.sh

ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"
ENV LC_ALL="zh_CN.UTF-8"

RUN --mount=type=bind,source=Wayland/Hyprland/scripts/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/install-os-deps.sh && \
  chmod -R 777 /etc/nginx/sites-available /etc/nginx/sites-enabled && \
  mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi && \
  chown -R 1000:1000 /var/lib/nginx && \
  chmod -R 755 /var/lib/nginx

ENV PATH="/usr/local/nvidia/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# XDG & Session Core Environments
# XDG_SESSION_TYPE 决定 entrypoint.sh 走 Wayland (labwc) 还是 X11 (KDE) 路线
ENV XDG_SESSION_TYPE=wayland
# WAYLAND_DISPLAY 和 DISPLAY 供 entrypoint.sh 和子进程继承
ENV WAYLAND_DISPLAY=wayland-0
ENV DISPLAY=":20"
# QT_QPA_PLATFORM / EGL_PLATFORM 不在此硬编码：
#   - Wayland 路线: entrypoint.sh 不设置 (QT 自动检测), XWayland 应用走 X11
#   - X11 路线: entrypoint.sh 主动 unset WAYLAND_DISPLAY, QT 回退 xcb

ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
ENV DISPLAY_DPI=96
ENV DISPLAY_CDEPTH=24

# Install Wayland and PipeWire essentials (Replacing X.Org, Xvfb, VirtualGL)
RUN --mount=type=bind,source=Wayland/Hyprland/scripts/,target=/etc/beagle-wind-vnc/scripts/wayland/ \
    bash /etc/beagle-wind-vnc/scripts/wayland/install-wayland.sh

# Install Essential Utilities (Input Method, File Manager, Terminal) for Labwc
RUN apt-get update && apt-get install -y --no-install-recommends \
    fcitx5 \
    fcitx5-chinese-addons \
    dolphin \
    konsole && \
    mkdir -p /etc/environment.d && \
    echo "GTK_IM_MODULE=fcitx5\nQT_IM_MODULE=fcitx5\nXMODIFIERS=@im=fcitx5\nSDL_IM_MODULE=fcitx\nGLFW_IM_MODULE=ibus" > /etc/environment.d/fcitx5-wayland.conf && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Set input to fcitx5 (Wayland Native)
ENV GTK_IM_MODULE=fcitx
ENV QT_IM_MODULE=fcitx
ENV XIM=fcitx
ENV XMODIFIERS="@im=fcitx"

USER 0
RUN --mount=type=bind,source=Wayland/Hyprland/scripts/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/setup-sudo.sh

USER 1000
