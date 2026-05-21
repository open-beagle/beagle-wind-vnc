#!/bin/bash

# Host-network instances share TCP/UDP ports, but X11/KDE runtime sockets live
# in the container filesystem namespace. Keep the desktop DISPLAY stable and
# use BDWIND_PORT_NGINX only for the public web entrypoint.

export DISPLAY="${BDWIND_DISPLAY:-${DISPLAY:-:20}}"

export BDWIND_DISPLAY="${DISPLAY}"

export XDG_RUNTIME_DIR="${BDWIND_XDG_RUNTIME_DIR:-/tmp/runtime-beagle}"
export DBUS_SESSION_BUS_ADDRESS="${BDWIND_DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus}"
export DBUS_SYSTEM_BUS_ADDRESS="${BDWIND_DBUS_SYSTEM_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-system-bus}"
export PIPEWIRE_RUNTIME_DIR="${BDWIND_PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export PULSE_RUNTIME_PATH="${BDWIND_PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR}/pulse}"
export PULSE_SERVER="${BDWIND_PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"
