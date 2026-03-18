# Business application layer - frontend (HTML/JS) and backend (Python) code
# This layer changes frequently and builds fast (just COPY operations)
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-egl-desktop-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

# Copy frontend files
USER 1000
SHELL ["/bin/sh", "-c"]

COPY ./addons/gstreamer-web/src/. /opt/gst-web/

# Copy selkies_gstreamer Python backend
COPY ./src/selkies_gstreamer/. /usr/local/lib/python3.12/dist-packages/selkies_gstreamer/

USER 1000

ENV PIPEWIRE_LATENCY="128/48000"
ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
ENV PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
ENV PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# dbus-daemon to the below address is required during startup
ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR:-/tmp}/dbus-system-bus"

ENV SHELL=/bin/bash
ENV USER=ubuntu
ENV HOME=/home/ubuntu
WORKDIR /home/ubuntu

EXPOSE 8080

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]
