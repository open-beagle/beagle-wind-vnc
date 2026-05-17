#!/bin/bash

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.

set -e

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done

# Configure joystick interposer
# export BDWIND_INTERPOSER='/usr/$LIB/selkies_joystick_interposer.so'
# export LD_PRELOAD="${BDWIND_INTERPOSER}${LD_PRELOAD:+:${LD_PRELOAD}}"
# export SDL_JOYSTICK_DEVICE=/dev/input/js0

# Set default display
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
export DISPLAY="${DISPLAY:-:20}"
# PipeWire-Pulse server socket path
export PIPEWIRE_LATENCY="128/48000"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# Export environment variables required for BDWIND-GStreamer
export GST_DEBUG="${GST_DEBUG:-*:2}"
export GSTREAMER_PATH=/opt/gstreamer

# Force exact display variable since Wayland allocates X0
# export DISPLAY=":0"

# Source environment for GStreamer
. /opt/gstreamer/gst-env

# Apply dynamic encoder config if it exists
# Apply dynamic encoder config if it exists
if [ -f "${HOME}/.config/bdwind_encoder.conf" ]; then
    . "${HOME}/.config/bdwind_encoder.conf"
fi

# GLX is an NVFBC profile. A stale legacy encoder config must not silently
# downgrade it to ximagesrc; EGL owns that capture path.
case "${BDWIND_CAPTURE_SOURCE:-}" in
    ximage|ximagesrc)
        if [ "${BDWIND_GLX_ALLOW_XIMAGESRC:-false}" != "true" ]; then
            echo "Ignoring BDWIND_CAPTURE_SOURCE=${BDWIND_CAPTURE_SOURCE} for GLX; using nvfbcsrc."
            unset BDWIND_CAPTURE_SOURCE
        fi
        ;;
esac

# bdwind.json is the UI source of truth.
if [ -f "${HOME}/.config/bdwind.json" ]; then
    eval "$(python3 - <<'PY'
import json
import os
import shlex

conf = os.path.expanduser("~/.config/bdwind.json")
try:
    with open(conf) as f:
        data = json.load(f)
except Exception:
    data = {}

res = data.get("BDWIND_RESOLUTION")
phys = data.get("BDWIND_PHYSICAL_RESOLUTION")
if res:
    print("export BDWIND_RESOLUTION={}".format(shlex.quote(str(res))))
if phys:
    print("export BDWIND_PHYSICAL_RESOLUTION={}".format(shlex.quote(str(phys))))
    print("export RESOLUTION={}".format(shlex.quote(str(phys))))
PY
)"
fi

# Dependencies are pre-extracted natively in dist-packages/ in the GStreamer 1.28.2 tarball.
# We no longer need to unzip .whl files at runtime.

# Render engine identity — drives pipeline builder selection in Python
export BDWIND_RENDER_ENGINE="glx"

# NvFBC talks to the NVIDIA X/GLX driver interface. In this CDI/container
# layout GLVND can otherwise fall back to Mesa llvmpipe, which makes
# NvFBCCreateHandle fail with an X driver interface version mismatch.
export __GLX_VENDOR_LIBRARY_NAME="${__GLX_VENDOR_LIBRARY_NAME:-nvidia}"
export __NV_PRIME_RENDER_OFFLOAD="${__NV_PRIME_RENDER_OFFLOAD:-1}"

export BDWIND_ENCODER="${BDWIND_ENCODER:-x264enc}"
export BDWIND_ENABLE_RESIZE="${BDWIND_ENABLE_RESIZE:-false}"
if [ "${BDWIND_TURN_DISABLE}" != "true" ] && [ -z "${BDWIND_TURN_REST_URI}" ] && { { [ -z "${BDWIND_TURN_USERNAME}" ] || [ -z "${BDWIND_TURN_PASSWORD}" ]; } && [ -z "${BDWIND_TURN_SHARED_SECRET}" ] || [ -z "${BDWIND_TURN_HOST}" ] || [ -z "${BDWIND_TURN_PORT}" ]; }; then
  export TURN_RANDOM_PASSWORD="$(tr -dc 'A-Za-z0-9' < /dev/urandom 2>/dev/null | head -c 24)"
  export BDWIND_TURN_HOST="${BDWIND_TURN_HOST:-$(dig -4 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z "$output" ] || echo "$output" | grep -q '^;;'; then exit 1; else echo "$(echo $output | sed 's,\",,g')"; fi } || dig -6 TXT +short @ns1.google.com o-o.myaddr.l.google.com 2>/dev/null | { read output; if [ -z "$output" ] || echo "$output" | grep -q '^;;'; then exit 1; else echo "[$(echo $output | sed 's,\",,g')]"; fi } || hostname -I 2>/dev/null | awk '{print $1; exit}' || echo '127.0.0.1')}"
  export TURN_EXTERNAL_IP="${TURN_EXTERNAL_IP:-$(getent ahostsv4 $(echo ${BDWIND_TURN_HOST} | tr -d '[]') 2>/dev/null | awk '{print $1; exit}' || getent ahostsv6 $(echo ${BDWIND_TURN_HOST} | tr -d '[]') 2>/dev/null | awk '{print "[" $1 "]"; exit}')}"
  export BDWIND_TURN_PORT="${BDWIND_TURN_PORT:-3478}"
  export BDWIND_TURN_USERNAME="selkies"
  export BDWIND_TURN_PASSWORD="${TURN_RANDOM_PASSWORD}"
  export BDWIND_TURN_PROTOCOL="${BDWIND_TURN_PROTOCOL:-tcp}"
  export BDWIND_STUN_HOST="${BDWIND_STUN_HOST:-stun.l.google.com}"
  export BDWIND_STUN_PORT="${BDWIND_STUN_PORT:-19302}"
fi

# Wait for Display server to start
export DISPLAY="${DISPLAY:-:20}"
export XDG_SESSION_TYPE="${XDG_SESSION_TYPE:-x11}"
if [ "${XDG_SESSION_TYPE}" = "wayland" ]; then
    export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
    echo 'Waiting for Wayland Socket' && until [ -S "${XDG_RUNTIME_DIR}/${WAYLAND_DISPLAY}" ]; do sleep 0.5; done && echo 'Wayland Server is ready'
else
    echo "Waiting for X11 Socket on ${DISPLAY}..." && until [ -S "/tmp/.X11-unix/X${DISPLAY#*:}" ]; do sleep 0.5; done && echo 'X11 Server is ready'
fi

# Configure NGINX
if [ "$(echo ${BDWIND_ENABLE_BASIC_AUTH} | tr '[:upper:]' '[:lower:]')" != "false" ]; then htpasswd -bcm "${XDG_RUNTIME_DIR}/.htpasswd" "${BDWIND_BASIC_AUTH_USER:-${USER}}" "${BDWIND_BASIC_AUTH_PASSWORD:-${BDWIND_PASSWORD:-${PASSWD}}}"; fi

_bdwind_port_available() {
    python3 - "$1" <<'PY'
import socket
import sys

try:
    port = int(sys.argv[1])
    if port <= 0 or port > 65535:
        raise ValueError(port)
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", port))
    sock.close()
except Exception:
    sys.exit(1)
PY
}

_bdwind_allocate_ports() {
    python3 - <<'PY'
import socket

sockets = []
for _ in range(2):
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.bind(("127.0.0.1", 0))
    sockets.append(sock)

print(f"{sockets[0].getsockname()[1]} {sockets[1].getsockname()[1]}")

for sock in sockets:
    sock.close()
PY
}

# 端口持久化复用：容器内重启时保持端口不变；host network 下缓存端口可能已被其它实例占用。
if [ -z "$BDWIND_PORT_GSTREAMER" ] || [ -z "$BDWIND_PORT_METRICS" ]; then
    CACHED_GSTREAMER_PORT=$(cat /tmp/gstreamer-port 2>/dev/null || true)
    CACHED_METRICS_PORT=$(cat /tmp/metrics-port 2>/dev/null || true)

    if [ -n "$CACHED_GSTREAMER_PORT" ] && [ -n "$CACHED_METRICS_PORT" ] &&
        _bdwind_port_available "$CACHED_GSTREAMER_PORT" &&
        _bdwind_port_available "$CACHED_METRICS_PORT"; then
        export BDWIND_PORT_GSTREAMER="$CACHED_GSTREAMER_PORT"
        export BDWIND_PORT_METRICS="$CACHED_METRICS_PORT"
    else
        _PORTS=$(_bdwind_allocate_ports)
        export BDWIND_PORT_GSTREAMER="$(echo $_PORTS | awk '{print $1}')"
        export BDWIND_PORT_METRICS="$(echo $_PORTS | awk '{print $2}')"
        echo "Allocated BDWIND ports: gstreamer=${BDWIND_PORT_GSTREAMER}, metrics=${BDWIND_PORT_METRICS}"
    fi
fi
echo "${BDWIND_PORT_GSTREAMER}" > /tmp/gstreamer-port
echo "${BDWIND_PORT_METRICS}" > /tmp/metrics-port

echo "# BDWIND-GStreamer NGINX Configuration
server {
    access_log /dev/stdout;
    error_log /dev/stderr;
    listen ${BDWIND_PORT_NGINX:-8080} $(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "ssl"; fi);
    listen [::]:${BDWIND_PORT_NGINX:-8080} $(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "ssl"; fi);
    ssl_certificate ${BDWIND_HTTPS_CERT-/etc/ssl/certs/ssl-cert-snakeoil.pem};
    ssl_certificate_key ${BDWIND_HTTPS_KEY-/etc/ssl/private/ssl-cert-snakeoil.key};
    $(if [ \"$(echo ${BDWIND_ENABLE_BASIC_AUTH} | tr '[:upper:]' '[:lower:]')\" != \"false\" ]; then echo "auth_basic \"Selkies\";"; echo -n "    auth_basic_user_file ${XDG_RUNTIME_DIR}/.htpasswd;"; fi)

    location / {
        root /opt/bdwind/webrtc/;
        index  index.html index.htm;
    }

    location ~* \.html$ {
        root /opt/bdwind/webrtc/;
        add_header Cache-Control \"no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0\";
        expires off;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        root /opt/bdwind/webrtc/;
        add_header Cache-Control \"public, max-age=31536000, immutable\";
        expires 1y;
    }

    location /health {
        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_GSTREAMER:-8081};
    }

    location /turn {
        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_GSTREAMER:-8081};
    }

    location /settings {
        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_GSTREAMER:-8081};
    }

    location /ws {
        proxy_set_header        Upgrade \$http_upgrade;
        proxy_set_header        Connection \"upgrade\";

        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;

        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_GSTREAMER:-8081};
    }

    location /webrtc/signalling {
        proxy_set_header        Upgrade \$http_upgrade;
        proxy_set_header        Connection \"upgrade\";

        proxy_set_header        Host \$host;
        proxy_set_header        X-Real-IP \$remote_addr;
        proxy_set_header        X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header        X-Forwarded-Proto \$scheme;

        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_GSTREAMER:-8081};
    }

    location /metrics {
        proxy_http_version      1.1;
        proxy_read_timeout      3600s;
        proxy_send_timeout      3600s;
        proxy_connect_timeout   3600s;
        proxy_buffering         off;

        client_max_body_size    10M;

        proxy_pass http$(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "s"; fi)://127.0.0.1:${BDWIND_PORT_METRICS:-9081};
    }

    error_page 500 502 503 504 /50x.html;
    location = /50x.html {
        root /opt/bdwind/webrtc/;
    }
}" | tee /etc/nginx/sites-available/default > /dev/null

# start-webrtc can be restarted independently while nginx keeps running under
# supervisord. Reload nginx so proxy_pass follows any regenerated dynamic ports.
if pgrep -x nginx >/dev/null 2>&1; then
    nginx -t && nginx -s reload || echo "WARNING: nginx reload failed; proxy may still use old backend ports"
fi

# Clear the cache registry
rm -rf "${HOME}/.cache/gstreamer-1.0"


# Prepare BDWIND NVENC Multi-GPU Workaround Hook
NVENC_HOOK="/opt/gstreamer/hooks/nvenc_ioctl_hook.so"
if [ -f "$NVENC_HOOK" ]; then
    export NVENC_HOOK_PROFILE="${NVENC_HOOK_PROFILE:-glx-nvenc}"

    # Keep a legacy override for old deployments, but the hook can now discover
    # the CDI target from /dev/nvidia0 by itself.
    if [ -n "${NVENC_GPU_INDEX:-}" ]; then
        export NVENC_GPU_INDEX
    fi

    # Pre-warm GSP without letting the hook affect NVML/nvidia-smi output.
    env -u LD_PRELOAD nvidia-smi -L >/dev/null 2>&1 || true

    case ":${LD_PRELOAD:-}:" in
        *:"${NVENC_HOOK}":*) ;;
        *) export LD_PRELOAD="${NVENC_HOOK}${LD_PRELOAD:+:${LD_PRELOAD}}" ;;
    esac

    # Keep the hook scoped to the WebRTC process and make the target explicit.
    # If a specific driver/GStreamer pair still rejects the hook, disable it
    # here rather than passing hook state via Docker.

fi

# Apply NVFBC GeForce unlock patch (requires root for binary patching)
# The libnvidia-fbc.so is injected via nvidia-container-toolkit at runtime,
# so the patch must be applied at startup, not during image build.
if [ -f "/etc/beagle-wind-vnc/patch-nvfbc.sh" ]; then
    echo "Applying NVFBC GeForce unlock patch..."
    sudo bash /etc/beagle-wind-vnc/patch-nvfbc.sh || echo "WARNING: NVFBC patch failed, falling back to ximagesrc"
fi

# Hot-load custom compiled GStreamer C plugins (e.g. nvfbcsrc) if provided via volume mount
if [ -f "/opt/gstreamer/hooks/libgstnvfbcsrc.so" ]; then
    echo "Hot-loading custom libgstnvfbcsrc.so plugin..."
    sudo cp /opt/gstreamer/hooks/libgstnvfbcsrc.so /opt/gstreamer/lib/x86_64-linux-gnu/gstreamer-1.0/
fi

# Inject Libnice NAT 1-to-1 Mapping if BDWIND_ICE_IP is specified
if [ -n "${BDWIND_ICE_IP}" ]; then
    LOCAL_IP=$(hostname -I | awk '{print $1}')
    export NICE_NAT_1TO1="${LOCAL_IP}:${BDWIND_ICE_IP}"
    echo "BDWIND_ICE_IP detected. Force mapping ICE Candidates to: ${NICE_NAT_1TO1}"
fi

# Start the BDWIND-GStreamer WebRTC HTML5 remote desktop application
# 使用 python3 -m 直接启动模块，等效于 pip 安装的 bdwind-gstreamer 入口脚本，
# 但不依赖 pip console_scripts，兼容 volume 热挂载调试场景。
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/dbus-session-bus"

python3 -m bdwind_gstreamer \
    --encoder="${BDWIND_ENCODER:-x264enc}" \
    --addr="127.0.0.1" \
    --port="${BDWIND_PORT_GSTREAMER:-8081}" \
    --enable_basic_auth="false" \
    --enable_metrics_http="true" \
    --metrics_http_port="${BDWIND_PORT_METRICS:-9081}" \
    --udp_port_min="${BDWIND_UDP_PORT_MIN:-0}" \
    --udp_port_max="${BDWIND_UDP_PORT_MAX:-0}" \
    $@
