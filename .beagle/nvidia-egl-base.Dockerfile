# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

# Supported base images: Ubuntu 24.04, 22.04, 20.04
ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}
ARG BASE_IMAGE

LABEL maintainer="https://github.com/open-beagle"

ARG DEBIAN_FRONTEND=noninteractive
# Configure rootless user environment for constrained conditions without escalated root privileges inside containers
ARG TZ=Asia/Shanghai
ENV PASSWD=mypasswd

# Copy scripts to container
COPY scripts/base/ /tmp/scripts/
RUN chmod +x /tmp/scripts/*.sh

# Run base system setup
RUN /tmp/scripts/base-system-setup.sh

# Set locales
ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"
ENV LC_ALL="zh_CN.UTF-8"

USER 1000
# Use BUILDAH_FORMAT=docker in buildah
SHELL ["/usr/bin/fakeroot", "--", "/bin/sh", "-c"]

# Install operating system libraries or packages
RUN /tmp/scripts/os-libraries-install.sh

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
ENV VGL_DISPLAY=egl
ENV KASMVNC_ENABLE=false
ENV SELKIES_ENCODER=nvh264enc
ENV SELKIES_ENABLE_RESIZE=false
ENV SELKIES_ENABLE_BASIC_AUTH=true

# Install Xvfb
RUN /tmp/scripts/xvfb-install.sh

# Install VirtualGL and make libraries available for preload
RUN /tmp/scripts/virtualgl-install.sh

# Anything below this line should always be kept the same between docker-nvidia-glx-desktop and docker-nvidia-egl-desktop

# Install KDE and other GUI packages
RUN /tmp/scripts/kde-install.sh

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
RUN /tmp/scripts/selkies-gstreamer-install.sh

# # Install KasmVNC and RustDesk
# RUN /tmp/scripts/kasmvnc-rustdesk-install.sh

# ENV PATH="${PATH:+${PATH}:}/usr/lib/rustdesk"
# ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH:+${LD_LIBRARY_PATH}:}/usr/lib/rustdesk/lib"

# Add custom packages right below this comment, or use FROM in a new container and replace entrypoint.sh or supervisord.conf, and set ENTRYPOINT to /usr/bin/supervisord

COPY ./addons/gstreamer-web/src/. /opt/gst-web/

# Copy joystick-server
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
RUN chmod -f 755 /usr/bin/joystick-server

# Copy selkies_gstreamer
COPY ./src/selkies_gstreamer/. /usr/local/lib/python3.12/dist-packages/selkies_gstreamer/

# Copy scripts and configurations used to start the container with `--chown=1000:1000`
COPY --chown=1000:1000 ./nvidia/egl/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
RUN chmod -f 755 /etc/beagle-wind-vnc/entrypoint.sh
COPY --chown=1000:1000 ./nvidia/egl/selkies-gstreamer-entrypoint.sh /etc/beagle-wind-vnc/selkies-gstreamer-entrypoint.sh
RUN chmod -f 755 /etc/beagle-wind-vnc/selkies-gstreamer-entrypoint.sh
# COPY --chown=1000:1000 ./nvidia/egl/kasmvnc-entrypoint.sh /etc/beagle-wind-vnc/kasmvnc-entrypoint.sh
# RUN chmod -f 755 /etc/beagle-wind-vnc/kasmvnc-entrypoint.sh
COPY --chown=1000:1000 ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
RUN chmod -f 755 /etc/beagle-wind-vnc/steam-game.sh
COPY --chown=1000:1000 ./nvidia/egl/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh
RUN chmod -f 755 /etc/beagle-wind-vnc/bgctl.sh
COPY --chown=1000:1000 ./nvidia/egl/supervisord.conf /etc/supervisord.conf
RUN chmod -f 755 /etc/supervisord.conf

# Configure coTURN script
RUN echo "#!/bin/bash\n\
set -e\n\
turnserver \
    --verbose \
    --listening-ip=\"0.0.0.0\" \
    --listening-ip=\"::\" \
    --listening-port=\"\${SELKIES_TURN_PORT:-3478}\" \
    --realm=\"\${TURN_REALM:-example.com}\" \
    --external-ip=\"\${TURN_EXTERNAL_IP:-\$(dig -4 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z \"\$output\" ] || echo \"\$output\" | grep -q '^;;'; then exit 1; else echo \"\$(echo \$output | sed 's,\\\",,g')\"; fi } || dig -6 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z \"\$output\" ] || echo \"\$output\" | grep -q '^;;'; then exit 1; else echo \"[\$(echo \$output | sed 's,\\\",,g')]\"; fi } || hostname -I 2>/dev/null | awk '{print \$1; exit}' || echo '127.0.0.1')}\" \
    --min-port=\"\${TURN_MIN_PORT:-49152}\" \
    --max-port=\"\${TURN_MAX_PORT:-65535}\" \
    --channel-lifetime=\"\${TURN_CHANNEL_LIFETIME:--1}\" \
    --lt-cred-mech \
    --user=\"selkies:\${TURN_RANDOM_PASSWORD:-\$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)}\" \
    --no-cli \
    --cli-password=\"\${TURN_RANDOM_PASSWORD:-\$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)}\" \
    --userdb=\"\${XDG_RUNTIME_DIR:-/tmp}/turnserver-turndb\" \
    --pidfile=\"\${XDG_RUNTIME_DIR:-/tmp}/turnserver.pid\" \
    --log-file=\"stdout\" \
    --allow-loopback-peers \
    \${TURN_EXTRA_ARGS} \$@\
" > /etc/start-turnserver.sh && chmod -f 755 /etc/start-turnserver.sh

SHELL ["/bin/sh", "-c"]

USER 0
# Enable sudo through sudo-root with uid 0
RUN /tmp/scripts/sudo-root-setup.sh
USER 1000

# Clean up temporary scripts
RUN rm -rf /tmp/scripts/

ENV PIPEWIRE_LATENCY="128/48000"
ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
ENV PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
ENV PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# dbus-daemon to the below address is required during startup
ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/tmp}/dbus-system-bus"

USER 1000
ENV SHELL=/bin/bash
ENV USER=ubuntu
ENV HOME=/home/ubuntu
WORKDIR /home/ubuntu

EXPOSE 8080

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]