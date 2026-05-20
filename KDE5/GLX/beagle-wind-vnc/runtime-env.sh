#!/bin/bash

# GLX runs with --network host so X11/KDE local namespaces are not isolated by
# Docker networking. Keep every instance on a unique DISPLAY/runtime tuple.

_bdwind_display_from_port() {
	local port="$1"

	case "$port" in
		''|*[!0-9]*)
			return 1
			;;
	esac

	# Use the full instance port as the display number so host-network GLX
	# instances have a stable one-to-one identity: 48082 -> :48082.
	printf ':%s' "$((10#$port))"
}

if [ -n "${BDWIND_DISPLAY:-}" ]; then
	export DISPLAY="${BDWIND_DISPLAY}"
elif [ -n "${BDWIND_PORT_NGINX:-}" ]; then
	export DISPLAY="$(_bdwind_display_from_port "${BDWIND_PORT_NGINX}")"
else
	export DISPLAY="${DISPLAY:-:20}"
fi

export BDWIND_DISPLAY="${DISPLAY}"

_bdwind_display_token="${DISPLAY#*:}"
_bdwind_display_token="${_bdwind_display_token%%.*}"
if [ -z "$_bdwind_display_token" ]; then
	_bdwind_display_token="20"
fi

export XDG_RUNTIME_DIR="${BDWIND_XDG_RUNTIME_DIR:-/tmp/runtime-beagle-${_bdwind_display_token}}"
export DBUS_SESSION_BUS_ADDRESS="${BDWIND_DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus}"
export DBUS_SYSTEM_BUS_ADDRESS="${BDWIND_DBUS_SYSTEM_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/dbus-system-bus}"
export PIPEWIRE_RUNTIME_DIR="${BDWIND_PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export PULSE_RUNTIME_PATH="${BDWIND_PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR}/pulse}"
export PULSE_SERVER="${BDWIND_PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"

unset _bdwind_display_token
