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

# Copy scripts to container
COPY scripts/base/ /etc/beagle-wind-vnc/scripts/
RUN chmod +x /etc/beagle-wind-vnc/scripts/*.sh

# Run base system setup
RUN /etc/beagle-wind-vnc/scripts/base-system-setup.sh

# Set locales
ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"
ENV LC_ALL="zh_CN.UTF-8"

# Install operating system libraries or packages (must run as root before switching user)
RUN /etc/beagle-wind-vnc/scripts/os-libraries-install.sh && \
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

# Anything above this line should always be kept the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop

# Default environment variables (default password is "mypasswd")
ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
ENV DISPLAY_DPI=96
ENV DISPLAY_CDEPTH=24
ENV VIDEO_PORT=DFP
ENV KASMVNC_ENABLE=false
ENV SELKIES_ENCODER=nvh264enc
ENV SELKIES_ENABLE_RESIZE=false
ENV SELKIES_ENABLE_BASIC_AUTH=true

# ========== GLX-specific: Install X.Org (NOT Xvfb) ==========
# GLX uses a real hardware X.Org server bound to the GPU, instead of EGL's virtual framebuffer
RUN /etc/beagle-wind-vnc/scripts/xorg-install.sh

# ========== GLX-specific: NO VirtualGL needed ==========
# GLX renders natively on GPU hardware via X.Org, so VirtualGL interception is unnecessary

# Anything below this line should always be kept the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop

# Install KDE and other GUI packages
RUN /etc/beagle-wind-vnc/scripts/kde-install.sh

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

# Install latest Selkies-GStreamer
ARG PIP_BREAK_SYSTEM_PACKAGES=1
RUN /etc/beagle-wind-vnc/scripts/selkies-gstreamer-install.sh

# Add custom packages right below this comment, or use FROM in a new container and replace entrypoint.sh or supervisord.conf, and set ENTRYPOINT to /usr/bin/supervisord

# Copy files that need root permissions before switching to non-root user
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
RUN chmod 755 /usr/bin/joystick-server

# ========== GLX-specific: Use GLX entrypoint and supervisord ==========
COPY ./nvidia/glx/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./nvidia/glx/selkies-gstreamer-entrypoint.sh /etc/beagle-wind-vnc/selkies-gstreamer-entrypoint.sh
COPY ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
COPY ./nvidia/egl/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh
COPY ./nvidia/glx/supervisord.conf /etc/supervisord.conf
COPY ./scripts/base/start-turnserver.sh /etc/start-turnserver.sh
RUN chmod 755 /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/selkies-gstreamer-entrypoint.sh \
    /etc/beagle-wind-vnc/steam-game.sh \
    /etc/beagle-wind-vnc/bgctl.sh \
    /etc/supervisord.conf \
    /etc/start-turnserver.sh

USER 0
# Enable sudo through sudo-root with uid 0
RUN /etc/beagle-wind-vnc/scripts/sudo-root-setup.sh

# Clean up temporary scripts (must be done as root since scripts are owned by root)
RUN rm -rf /etc/beagle-wind-vnc/scripts/

USER 1000

ENV PIPEWIRE_LATENCY="128/48000"
ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
ENV PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
ENV PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# dbus-daemon to the below address is required during startup
ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/tmp}/dbus-system-bus"
# Shared D-Bus session bus for all services (Steam CEF/Chromium requires this)
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/tmp}/dbus-session-bus"

USER 1000
ENV SHELL=/bin/bash
ENV USER=ubuntu
ENV HOME=/home/ubuntu
WORKDIR /home/ubuntu

EXPOSE 8080

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]
