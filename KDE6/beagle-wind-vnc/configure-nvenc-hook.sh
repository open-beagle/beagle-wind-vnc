#!/bin/bash

# Keep the CDI/NVENC compatibility shim scoped to the persistent encoder.
# Monitoring tools and the rest of the desktop must retain the native GPU view.
bdwind_configure_nvenc_hook() {
    local mode="${BDWIND_NVENC_HOOK:-auto}"
    local hook="${BDWIND_NVENC_HOOK_PATH:-/opt/gstreamer/hooks/nvenc_ioctl_hook.so}"

    if [ "${BDWIND_ENCODER:-nvh264enc}" != "nvh264enc" ]; then
        return 0
    fi

    case "${mode,,}" in
        0|false|no|off|disabled)
            return 0
            ;;
        auto)
            if [ ! -r "${hook}" ]; then
                return 0
            fi
            ;;
        1|true|yes|on|required)
            if [ ! -r "${hook}" ]; then
                echo "[kde6] required NVENC hook is missing: ${hook}" >&2
                return 69
            fi
            ;;
        *)
            echo "[kde6] invalid BDWIND_NVENC_HOOK value: ${mode}" >&2
            return 64
            ;;
    esac

    case ":${LD_PRELOAD:-}:" in
        *":${hook}:"*) ;;
        *) export LD_PRELOAD="${hook}${LD_PRELOAD:+:${LD_PRELOAD}}" ;;
    esac

    export NVENC_HOOK_PROFILE="${NVENC_HOOK_PROFILE:-wayland-nvenc}"
    export NVENC_HOOK_REWRITE_OPEN="${NVENC_HOOK_REWRITE_OPEN:-1}"
    export NVENC_HOOK_REWRITE_RM="${NVENC_HOOK_REWRITE_RM:-1}"
    export NVENC_HOOK_SPOOF_CUDA="${NVENC_HOOK_SPOOF_CUDA:-1}"
}

