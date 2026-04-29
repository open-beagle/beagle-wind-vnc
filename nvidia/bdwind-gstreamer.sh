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

# Apply dynamic display config if it exists
if [ -f "${HOME}/.config/bdwind_display.conf" ]; then
    . "${HOME}/.config/bdwind_display.conf"
fi

# Unzip provided python wheels if they haven't been extracted yet
mkdir -p /tmp/pydeps
if [ ! -d "/tmp/pydeps/prometheus_client" ]; then
    echo "Extracting Python .whl dependencies..."
    cd /tmp/pydeps && for f in /opt/gstreamer/lib/python3/dist-packages/*.whl; do unzip -qo $f; done
    # Delete bdwind_gstreamer to avoid shadowing the live host mount in /opt/gstreamer
    rm -rf /tmp/pydeps/bdwind_gstreamer
    cd - >/dev/null
fi
export PYTHONPATH="/tmp/pydeps:${PYTHONPATH}"



export BDWIND_ENCODER="${BDWIND_ENCODER:-nvh264enc}"
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

# 端口持久化复用：容器内重启时保持端口不变
if [ -z "$BDWIND_PORT_GSTREAMER" ] || [ -z "$BDWIND_PORT_METRICS" ]; then
    # 优先从缓存文件读取上次分配的端口
    CACHED_GSTREAMER_PORT=$(cat /tmp/gstreamer-port 2>/dev/null || true)
    CACHED_METRICS_PORT=$(cat /tmp/metrics-port 2>/dev/null || true)

    if [ -n "$CACHED_GSTREAMER_PORT" ] && [ -n "$CACHED_METRICS_PORT" ]; then
        # 容器内重启：复用上次端口
        export BDWIND_PORT_GSTREAMER="$CACHED_GSTREAMER_PORT"
        export BDWIND_PORT_METRICS="$CACHED_METRICS_PORT"
    else
        # 容器首次启动：动态分配
        _PORTS=$(python3 -c 'import socket; s1=socket.socket(); s1.bind(("",0)); s2=socket.socket(); s2.bind(("",0)); print(f"{s1.getsockname()[1]} {s2.getsockname()[1]}"); s1.close(); s2.close()')
        export BDWIND_PORT_GSTREAMER="$(echo $_PORTS | awk '{print $1}')"
        export BDWIND_PORT_METRICS="$(echo $_PORTS | awk '{print $2}')"
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

# Clear the cache registry
rm -rf "${HOME}/.cache/gstreamer-1.0"



# Prepare BDWIND NVENC Multi-GPU Workaround Hook
if [ -f "/opt/gstreamer/patches/nvenc_ioctl_hook.so" ]; then
    # In X11/GLX explicitly disable the nvenc DRM hook which causes NvFBC GLX context creation to fail with BadValue
    # export LD_PRELOAD="/opt/gstreamer/patches/nvenc_ioctl_hook.so${LD_PRELOAD:+:${LD_PRELOAD}}"
    
    # 预热 GSP 固件，避免 Hook 拦截到未初始化的上下文
    nvidia-smi -L >/dev/null 2>&1 || true

    # export NVENC_HOOK_DEBUG=1
    # Dynamically find the available nvidia GPU index so the wrapper can redirect /dev/nvidia0
    DETECTED_GPU=$(ls /dev/nvidia[0-9]* 2>/dev/null | grep -Eo '[0-9]+$' | head -n 1)
    export NVENC_GPU_INDEX="${NVENC_GPU_INDEX:-${DETECTED_GPU:-0}}"
fi

# Apply NVFBC GeForce unlock patch (requires root for binary patching)
# libnvidia-fbc.so is injected by nvidia-container-toolkit at runtime,
# so the patch must be applied at startup, not during image build.
if [ -f "/opt/gstreamer/patches/patch-nvfbc.sh" ]; then
    echo "Applying NVFBC GeForce unlock patch..."
    sudo bash /opt/gstreamer/patches/patch-nvfbc.sh || echo "WARNING: NVFBC patch failed, falling back to ximagesrc"
fi

# Hot-load custom compiled GStreamer C plugins (e.g. nvfbcsrc) if provided via volume mount
if [ -f "/opt/gstreamer/patches/libgstnvfbcsrc.so" ]; then
    echo "Hot-loading custom libgstnvfbcsrc.so plugin..."
    sudo cp /opt/gstreamer/patches/libgstnvfbcsrc.so /opt/gstreamer/lib/x86_64-linux-gnu/gstreamer-1.0/
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
    --encoder="${BDWIND_ENCODER:-nvh264enc}" \
    --addr="127.0.0.1" \
    --port="${BDWIND_PORT_GSTREAMER:-8081}" \
    --enable_basic_auth="false" \
    --enable_metrics_http="true" \
    --metrics_http_port="${BDWIND_PORT_METRICS:-9081}" \
    $@
