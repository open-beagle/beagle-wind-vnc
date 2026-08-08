#!/bin/bash
set -e

# KWin chooses the XWayland display at runtime.  A fixed DISPLAY value can
# point Steam at a socket that does not exist after a container restart.
display_number="${DISPLAY#*:}"
display_number="${display_number%%.*}"
if [ -z "${DISPLAY:-}" ] \
    || [ ! -S "/tmp/.X11-unix/X${display_number}" ]; then
    x_socket="$(find /tmp/.X11-unix -maxdepth 1 -type s -name 'X*' -printf '%f\n' 2>/dev/null \
        | sort -V | head -n 1)"
    if [ -z "${x_socket}" ]; then
        echo "Steam cannot start: the KWin XWayland display is unavailable" >&2
        exit 69
    fi
    export DISPLAY=":${x_socket#X}"
fi

# The custom GStreamer runtime is required by the streaming worker, but its
# libraries must not override the GTK/GStreamer ABI used by Steam and Zenity.
unset LD_LIBRARY_PATH
unset GST_PLUGIN_PATH
unset GST_PLUGIN_SYSTEM_PATH
unset GI_TYPELIB_PATH
unset PYTHONPATH

exec /usr/bin/steam "$@"
