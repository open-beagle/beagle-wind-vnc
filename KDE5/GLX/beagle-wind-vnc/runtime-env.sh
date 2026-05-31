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
# Let GLVND choose the server-provided GLX vendor. On this GLX/NVFBC profile,
# forcing __GLX_VENDOR_LIBRARY_NAME=nvidia can make GLX clients abort, while
# direct GLX can fall back to Mesa llvmpipe in a fresh shell.
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-}"
export LIBGL_ALWAYS_INDIRECT="${LIBGL_ALWAYS_INDIRECT:-1}"

export XDG_RUNTIME_DIR="${BDWIND_XDG_RUNTIME_DIR:-/tmp/runtime-beagle}"
export DBUS_SESSION_BUS_ADDRESS="${BDWIND_DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus}"
export DBUS_SYSTEM_BUS_ADDRESS="${BDWIND_DBUS_SYSTEM_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-system-bus}"
export PIPEWIRE_RUNTIME_DIR="${BDWIND_PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export PULSE_RUNTIME_PATH="${BDWIND_PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR}/pulse}"
export PULSE_SERVER="${BDWIND_PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"

# NvFBC fails when LD_PRELOAD is present, while NVENC needs the preload hook.
# Keep capture and encode in separate processes for the GLX/NVFBC profile.
export BDWIND_GLX_SPLIT_CAPTURE="${BDWIND_GLX_SPLIT_CAPTURE:-true}"
# Split capture transport:
# - tcp: stable phase-1 raw NV12 baseline.
# - cudaipc: phase-2 CUDA IPC path, enabled explicitly while validation is ongoing.
# - cudaring: BDW latest-frame CUDA IPC ring transport.
export BDWIND_GLX_CAPTURE_TRANSPORT="${BDWIND_GLX_CAPTURE_TRANSPORT:-tcp}"
if [ "${BDWIND_GLX_CAPTURE_TRANSPORT}" = "cudaipc" ] || [ "${BDWIND_GLX_CAPTURE_TRANSPORT}" = "cudaring" ]; then
    export BDWIND_GLX_NVFBC_CAPTURE_MODE="${BDWIND_GLX_NVFBC_CAPTURE_MODE:-cuda}"
fi
# CUDA IPC defaults are intentionally latest-frame oriented. When cudaipc is
# enabled, copy mode exercises the BDWIND low-latency nvcodec patch that skips
# the extra READ_DONE round trip after the frame has been copied locally.
export BDWIND_GLX_CUDAIPC_BUFFER_SIZE="${BDWIND_GLX_CUDAIPC_BUFFER_SIZE:-1}"
export BDWIND_GLX_CUDAIPC_QUEUE_SIZE="${BDWIND_GLX_CUDAIPC_QUEUE_SIZE:-1}"
export BDWIND_GLX_CUDAIPC_IO_MODE="${BDWIND_GLX_CUDAIPC_IO_MODE:-copy}"

export BDWIND_GLX_CUDARING_SLOT_COUNT="${BDWIND_GLX_CUDARING_SLOT_COUNT:-4}"
export BDWIND_GLX_CUDARING_WAIT_TIMEOUT_MS="${BDWIND_GLX_CUDARING_WAIT_TIMEOUT_MS:-2000}"
export BDWIND_GLX_CUDARING_STATS_INTERVAL_MS="${BDWIND_GLX_CUDARING_STATS_INTERVAL_MS:-1000}"
export BDWIND_GLX_CUDARING_SYNC_BEFORE_PUBLISH="${BDWIND_GLX_CUDARING_SYNC_BEFORE_PUBLISH:-true}"
if [ "${BDWIND_GLX_CAPTURE_TRANSPORT}" = "cudaring" ]; then
    export GST_DEBUG="${GST_DEBUG:-*:2},bdwcudaringsink:4,bdwcudaringsrc:4"
    export BDWIND_KEYFRAME_DISTANCE="${BDWIND_KEYFRAME_DISTANCE:-30}"
    export BDWIND_RTP_MTU="${BDWIND_RTP_MTU:-1400}"
    export BDWIND_NVENC_RC_MODE="${BDWIND_NVENC_RC_MODE:-cbr}"
    export BDWIND_NVENC_STRICT_GOP="${BDWIND_NVENC_STRICT_GOP:-true}"
    export BDWIND_NVENC_VBV_MULTIPLIER="${BDWIND_NVENC_VBV_MULTIPLIER:-0.75}"
    export BDWIND_POST_ENC_QUEUE_LEAKY="${BDWIND_POST_ENC_QUEUE_LEAKY:-false}"
    export BDWIND_RTP_QUEUE_LEAKY="${BDWIND_RTP_QUEUE_LEAKY:-false}"
fi

# Match the production game profile's explicit ICE interface pinning. This
# avoids libnice advertising docker/cilium interfaces before NAT rewriting.
export NICE_NETWORK_INTERFACES="${NICE_NETWORK_INTERFACES:-bond0}"
