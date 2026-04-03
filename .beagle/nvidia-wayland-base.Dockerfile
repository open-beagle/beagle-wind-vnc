# Supported base images: Ubuntu 25.04 (Plucky Puffin) for native KDE Plasma 6 & Wayland support
ARG BASE=ubuntu:25.04
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Asia/Shanghai
ENV PASSWD=mypasswd

SHELL ["/bin/sh", "-c"]

RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/base-system-setup.sh

ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"
ENV LC_ALL="zh_CN.UTF-8"

RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/bdwind-os-libraries-install.sh && \
  chmod -R 777 /etc/nginx/sites-available /etc/nginx/sites-enabled && \
  mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi && \
  chown -R 1000:1000 /var/lib/nginx && \
  chmod -R 755 /var/lib/nginx

ENV PATH="/usr/local/nvidia/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# XDG & Wayland Core Environments
ENV XDG_SESSION_TYPE=wayland
ENV QT_QPA_PLATFORM=wayland
ENV EGL_PLATFORM=wayland
ENV WAYLAND_DISPLAY=wayland-0
# Keep DISPLAY for XWayland fallback apps (like old Steam games)
ENV DISPLAY=":20"

ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
# No VGL_DISPLAY anymore due to Zero-copy Wayland

# Install Wayland and PipeWire essentials (Replacing X.Org, Xvfb, VirtualGL)
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/wayland-install.sh

# Install KDE 6 and Plasma Wayland Shell
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/kde6-wayland-install.sh

# KDE 6 Environment variables
ENV DESKTOP_SESSION=plasma
ENV XDG_SESSION_DESKTOP=KDE
ENV XDG_CURRENT_DESKTOP=KDE
ENV KDE_FULL_SESSION=true
ENV KDE_SESSION_VERSION=6

# Set input to fcitx5 (Wayland Native)
ENV GTK_IM_MODULE=fcitx
ENV QT_IM_MODULE=fcitx
ENV XIM=fcitx
ENV XMODIFIERS="@im=fcitx"

USER 0
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/sudo-root-setup.sh

USER 1000
