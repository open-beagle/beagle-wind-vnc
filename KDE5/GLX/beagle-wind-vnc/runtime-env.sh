#!/bin/bash

# GLX runs with --network host, but X11/KDE runtime sockets live in the
# container filesystem namespace. Keep the desktop DISPLAY stable and use
# BDWIND_PORT_NGINX only for the public web entrypoint.

export DISPLAY="${BDWIND_DISPLAY:-${DISPLAY:-:21}}"

export BDWIND_DISPLAY="${DISPLAY}"

# GLX/NVFBC must talk directly to the NVIDIA Xorg/GLX driver. These variables
# belong to the EGL/VirtualGL or overlay path and can push clients toward Mesa
# llvmpipe or perturb the NVIDIA GLX/FBC interface.
unset VGL_DISPLAY
unset VGL_CLIENT
unset VGL_COMPRESS
unset VGL_READBACK
unset MANGOHUD
unset MANGOHUD_CONFIG
unset MANGOHUD_DLSYM
unset OBS_VKCAPTURE
unset ENABLE_VKBASALT
unset __NV_PRIME_RENDER_OFFLOAD
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"

export XDG_RUNTIME_DIR="${BDWIND_XDG_RUNTIME_DIR:-/tmp/runtime-beagle}"
export DBUS_SESSION_BUS_ADDRESS="${BDWIND_DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus}"
export DBUS_SYSTEM_BUS_ADDRESS="${BDWIND_DBUS_SYSTEM_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-system-bus}"
export PIPEWIRE_RUNTIME_DIR="${BDWIND_PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export PULSE_RUNTIME_PATH="${BDWIND_PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR}/pulse}"
export PULSE_SERVER="${BDWIND_PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"
