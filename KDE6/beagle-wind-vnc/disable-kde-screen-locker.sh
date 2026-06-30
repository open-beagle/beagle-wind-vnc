#!/bin/bash
set -e

. /etc/beagle-wind-vnc/runtime-env.sh

config_dirs=("/etc/xdg" "${HOME}/.config")

for config_dir in "${config_dirs[@]}"; do
    if [ -w "$(dirname "${config_dir}")" ] || [ -w "${config_dir}" ]; then
        mkdir -p "${config_dir}"
    else
        sudo mkdir -p "${config_dir}"
        sudo chown "${USER}:${USER}" "${config_dir}" 2>/dev/null || true
    fi

    cat >"${config_dir}/kscreenlockerrc" <<EOF
[Daemon]
Autolock=false
LockOnResume=false
Timeout=0
EOF
done

if command -v qdbus6 >/dev/null 2>&1 && busctl --user --list >/dev/null 2>&1; then
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SetActive false >/dev/null 2>&1 || true
    qdbus6 org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.SimulateUserActivity >/dev/null 2>&1 || true
fi

pkill -u "$(id -u)" -f '(^|/)kscreenlocker_greet( |$)' 2>/dev/null || true
