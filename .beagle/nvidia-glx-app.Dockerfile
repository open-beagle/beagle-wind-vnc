# Business application layer - frontend (HTML/JS) and backend (Python) code
# This layer changes frequently and builds fast (just COPY operations)
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-glx-desktop-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

# Run business layer installation (GStreamer engine, custom Python environment & Web UI assets)
USER 0
ARG PIP_BREAK_SYSTEM_PACKAGES=1
RUN --mount=type=bind,source=scripts/base/bdwind-gstreamer-install.sh,target=/tmp/bdwind-gstreamer-install.sh \
    bash /tmp/bdwind-gstreamer-install.sh

# Copy files that need root permissions before switching to non-root user
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
# ========== GLX-specific: Use GLX entrypoint and supervisord ==========
COPY ./nvidia/glx/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./nvidia/glx/bdwind-gstreamer-entrypoint.sh /etc/beagle-wind-vnc/bdwind-gstreamer-entrypoint.sh
COPY ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
COPY ./nvidia/egl/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh
COPY ./nvidia/glx/supervisord.conf /etc/supervisord.conf
RUN chmod 755 /usr/bin/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/bdwind-gstreamer-entrypoint.sh \
    /etc/beagle-wind-vnc/steam-game.sh \
    /etc/beagle-wind-vnc/bgctl.sh \
    /etc/supervisord.conf



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

ENV SHELL=/bin/bash
ENV USER=ubuntu
ENV HOME=/home/ubuntu
WORKDIR /home/ubuntu

EXPOSE 8080

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]
