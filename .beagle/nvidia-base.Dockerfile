# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Supported base images: Ubuntu 24.04, 22.04, 20.04
ARG BASE=ubuntu:24.04
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive
# Configure rootless user environment for constrained conditions without escalated root privileges inside containers
ARG TZ=Asia/Shanghai
ENV PASSWD=mypasswd

# Ensure we use standard shell for root operations (not fakeroot)
SHELL ["/bin/sh", "-c"]

# Run base system setup via BuildKit ephemeral bind mount (zero image layers trace)
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/base-system-setup.sh

# Set locales
ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"
ENV LC_ALL="zh_CN.UTF-8"

# Install operating system libraries or packages (must run as root before switching user)
# [BDWIND] Use bdwind version that skips system GStreamer / NVIDIA VAAPI driver installation
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/bdwind-os-libraries-install.sh && \
  # Allow non-root user to write nginx site config at runtime
  chmod -R 777 /etc/nginx/sites-available /etc/nginx/sites-enabled && \
  # Create nginx runtime directories with proper permissions for non-root user
  mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi && \
  chown -R 1000:1000 /var/lib/nginx && \
  chmod -R 755 /var/lib/nginx

# Expose NVIDIA libraries and paths
ENV PATH="/usr/local/nvidia/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
# Make all NVIDIA GPUs visible by default
ENV NVIDIA_VISIBLE_DEVICES=all
# All NVIDIA driver capabilities should preferably be used, check `NVIDIA_DRIVER_CAPABILITIES` inside the container if things do not work
ENV NVIDIA_DRIVER_CAPABILITIES=all
# Disable VSYNC for NVIDIA GPUs
ENV __GL_SYNC_TO_VBLANK=0
# Set default DISPLAY environment
ENV DISPLAY=":20"

# Default environment variables (default password is "mypasswd")
ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
ENV DISPLAY_DPI=96
ENV DISPLAY_CDEPTH=24
ENV VIDEO_PORT=DFP
ENV VGL_DISPLAY=egl
ENV BDWIND_ENCODER=nvh264enc
ENV BDWIND_ENABLE_RESIZE=false
ENV BDWIND_ENABLE_BASIC_AUTH=true

# Install ALL display backends (X.Org natively for GLX, Xvfb and VirtualGL for EGL)
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/xorg-install.sh && \
    bash /etc/beagle-wind-vnc/scripts/xvfb-install.sh && \
    bash /etc/beagle-wind-vnc/scripts/virtualgl-install.sh

# Anything below this line should always be kept the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop

# Install KDE and other GUI packages
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/kde-install.sh

# KDE environment variables
ENV DESKTOP_SESSION=plasma
ENV XDG_SESSION_DESKTOP=KDE
ENV XDG_CURRENT_DESKTOP=KDE
ENV XDG_SESSION_TYPE=x11
ENV KDE_FULL_SESSION=true
ENV KDE_SESSION_VERSION=5
ENV KDE_APPLICATIONS_AS_SCOPE=1
ENV KWIN_COMPOSE=N
ENV KWIN_EFFECTS_FORCE_ANIMATIONS=0
ENV KWIN_EXPLICIT_SYNC=0
ENV KWIN_X11_NO_SYNC_TO_VBLANK=1
# Use sudoedit to change protected files instead of using sudo on kwrite
ENV SUDO_EDITOR=kwrite
# Enable AppImage execution in containers
ENV APPIMAGE_EXTRACT_AND_RUN=1
# Set input to fcitx
ENV GTK_IM_MODULE=fcitx
ENV QT_IM_MODULE=fcitx
ENV XIM=fcitx
ENV XMODIFIERS="@im=fcitx"

USER 0
# Enable sudo through sudo-root with uid 0
RUN --mount=type=bind,source=scripts/base/,target=/etc/beagle-wind-vnc/scripts/ \
    bash /etc/beagle-wind-vnc/scripts/sudo-root-setup.sh

USER 1000
