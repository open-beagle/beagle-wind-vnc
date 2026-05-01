# Business application layer - frontend (HTML/JS) and backend (Python) code
# This layer changes frequently and builds fast (just COPY operations)
ARG RENDER_ENGINE=glx
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:kde5-desktop-latest
FROM ${BASE}

# Redeclare ARG so it's available after FROM
ARG RENDER_ENGINE

# NOTE for runtime:
# To enable NVFBC zero-copy screen capture on consumer GeForce GPUs (e.g. RTX 4090),
# you must mount the proprietary `libnvidia-fbc.so` from the host directly into the container.
# Example: -v /usr/lib/x86_64-linux-gnu/libnvidia-fbc.so.595.58.03:/usr/lib/x86_64-linux-gnu/libnvidia-fbc.so.1:ro
# The Docker Nvidia Toolkit does not mount this automatically on unprivileged containers.

LABEL maintainer="https://github.com/open-beagle"

# Run business layer installation (GStreamer engine, custom Python environment & Web UI assets)
USER 0
ARG PIP_BREAK_SYSTEM_PACKAGES=1

# Step 1: Install self-compiled GStreamer 1.28.2 + BDWIND Python environment + Web UI
COPY ./KDE5/${RENDER_ENGINE}/scripts/install-gstreamer.sh /tmp/install-gstreamer.sh
RUN bash /tmp/install-gstreamer.sh && rm -f /tmp/install-gstreamer.sh

# [P7] nvidia-vaapi-driver removed — we use direct CUDA/NVENC path, not VA-API

# Copy files that need root permissions before switching to non-root user
RUN curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.0.0.tar.gz" | tar -xzf - -C /usr/bin/

# Use dynamic backend copy based on RENDER_ENGINE
COPY ./KDE5/${RENDER_ENGINE}/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./KDE5/${RENDER_ENGINE}/xorg.conf.template* /etc/beagle-wind-vnc/
COPY ./KDE5/base/start-webrtc.sh /etc/beagle-wind-vnc/start-webrtc.sh
COPY ./KDE5/base/start-gamepad.sh /etc/beagle-wind-vnc/start-gamepad.sh
COPY ./KDE5/${RENDER_ENGINE}/supervisord.conf /etc/supervisord.conf
COPY ./KDE5/base/fallback-sink.lua /usr/share/wireplumber/scripts/fallback-sink.lua
# P7: Patches directory (NVFBC GeForce unlock, nvenc hooks, etc.)
RUN mkdir -p /opt/gstreamer/hooks
COPY ./KDE5/${RENDER_ENGINE}/patch-nvfbc.sh* /opt/gstreamer/hooks/
RUN chmod 755 /usr/bin/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/start-webrtc.sh \
    /etc/beagle-wind-vnc/start-gamepad.sh \
    /etc/supervisord.conf \
    /opt/gstreamer/hooks/patch-nvfbc.sh

USER 1000

# -----------------------------------------------------------------------------
# Expose Self-compiled GStreamer 1.28.2 Globally
# -----------------------------------------------------------------------------
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="${GSTREAMER_PATH}/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV GST_PLUGIN_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu/gstreamer-1.0${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}"
ENV GST_PLUGIN_SYSTEM_PATH="${XDG_DATA_HOME:-/home/ubuntu/.local/share}/gstreamer-1.0/plugins:/usr/lib/x86_64-linux-gnu/gstreamer-1.0${GST_PLUGIN_SYSTEM_PATH:+:${GST_PLUGIN_SYSTEM_PATH}}"
ENV GI_TYPELIB_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:${GI_TYPELIB_PATH}}"
ENV PYTHONPATH="${GSTREAMER_PATH}/lib/python3/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"

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
