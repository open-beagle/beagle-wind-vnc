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

# Set Wayland session
export XDG_SESSION_TYPE="wayland"
# PipeWire-Pulse server socket path
export PIPEWIRE_LATENCY="128/48000"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:-/tmp}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR:-/tmp}/pulse}/native}"

# Export environment variables required for BDWIND-GStreamer
export GST_DEBUG="${GST_DEBUG:-*:2,pipewiresrc:5,videorate:5}"
export GSTREAMER_PATH=/opt/gstreamer

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

# Project P8-Stark: Disabled legacy python 3.14 wheel extraction,
# using isolated Python 3.12 venv with native dependencies instead.
export BDWIND_ENCODER="${BDWIND_ENCODER:-nvh264enc}"
# Project P8-Stark: Re-map GStreamer EGL context to Surfaceless to permit WebRTC Native DMABuf imports
export GST_GL_PLATFORM=egl
export GST_GL_WINDOW=surfaceless
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

# Wait for Wayland compositor to start
echo 'Waiting for Wayland Socket'
until ls "${XDG_RUNTIME_DIR}"/wayland-* 1> /dev/null 2>&1; do 
    sleep 0.5
done
echo 'Wayland Server is ready'
# 自动检测并 export WAYLAND_DISPLAY，
# 使 wl-paste/wl-copy 剪贴板命令能连接到 Hyprland 的 Wayland socket
if [ -z "${WAYLAND_DISPLAY}" ]; then
    WAYLAND_DISPLAY=$(ls "${XDG_RUNTIME_DIR}"/wayland-* 2>/dev/null | grep -v lock | head -1 | xargs basename 2>/dev/null)
    export WAYLAND_DISPLAY
    echo "Auto-detected WAYLAND_DISPLAY=${WAYLAND_DISPLAY}"
fi
# Wait additional seconds for desktop portals to register on DBus
sleep 3

# Configure NGINX
if [ "$(echo ${BDWIND_ENABLE_BASIC_AUTH} | tr '[:upper:]' '[:lower:]')" != "false" ]; then
    if command -v htpasswd >/dev/null; then
        htpasswd -bcm "${XDG_RUNTIME_DIR}/.htpasswd" "${BDWIND_BASIC_AUTH_USER:-${USER}}" "${BDWIND_PASSWORD:-${BDWIND_BASIC_AUTH_PASSWORD:-${PASSWD}}}"
    elif command -v openssl >/dev/null; then
        echo "${BDWIND_BASIC_AUTH_USER:-${USER}}:$(openssl passwd -6 "${BDWIND_PASSWORD:-${BDWIND_BASIC_AUTH_PASSWORD:-${PASSWD}}}")" > "${XDG_RUNTIME_DIR}/.htpasswd"
    else
        echo "Warning: Neither htpasswd nor openssl is installed. Basic auth will be disabled to prevent Nginx crash."
        export BDWIND_ENABLE_BASIC_AUTH="false"
    fi
fi

if [ -z "$BDWIND_PORT_GSTREAMER" ] || [ -z "$BDWIND_PORT_METRICS" ]; then
    _PORTS=$(python3 -c 'import socket; s1=socket.socket(); s1.bind(("",0)); s2=socket.socket(); s2.bind(("",0)); print(f"{s1.getsockname()[1]} {s2.getsockname()[1]}"); s1.close(); s2.close()')
    export BDWIND_PORT_GSTREAMER="${BDWIND_PORT_GSTREAMER:-$(echo $_PORTS | awk '{print $1}')}"
    export BDWIND_PORT_METRICS="${BDWIND_PORT_METRICS:-$(echo $_PORTS | awk '{print $2}')}"
fi
echo "${BDWIND_PORT_GSTREAMER}" > /tmp/gstreamer-port

echo "# BDWIND-GStreamer NGINX Configuration
pid /tmp/nginx.pid;
events {
    worker_connections 1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    server {
    access_log /dev/stdout;
    error_log /dev/stderr;
    listen ${BDWIND_PORT_NGINX:-8080} $(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "ssl"; fi);
    listen [::]:${BDWIND_PORT_NGINX:-8080} $(if [ \"$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')\" = \"true\" ]; then echo -n "ssl"; fi);
    $(if [ "$(echo ${BDWIND_ENABLE_HTTPS} | tr '[:upper:]' '[:lower:]')" = "true" ]; then echo "ssl_certificate ${BDWIND_HTTPS_CERT-/etc/ssl/certs/ssl-cert-snakeoil.pem};"; echo "    ssl_certificate_key ${BDWIND_HTTPS_KEY-/etc/ssl/private/ssl-cert-snakeoil.key};"; fi)
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
}
}" | sudo tee /etc/nginx/nginx.conf > /dev/null

sudo nginx -s reload || true

# Clear the cache registry
rm -rf "${HOME}/.cache/gstreamer-1.0"

# Prepare BDWIND NVENC Multi-GPU Workaround Hook
if [ -f "/opt/gstreamer/patches/nvenc_ioctl_hook.so" ]; then
    # Unlock hardware encoders dynamically across identical GPUs
    export LD_PRELOAD="/opt/gstreamer/patches/nvenc_ioctl_hook.so"
    
    # 预热 GSP 固件，避免 Hook 拦截到未初始化的上下文
    nvidia-smi -L >/dev/null 2>&1 || true

    # export NVENC_HOOK_DEBUG=1
    # Dynamically find the available nvidia GPU index so the wrapper can redirect /dev/nvidia0
    DETECTED_GPU=$(ls /dev/nvidia[0-9]* 2>/dev/null | grep -Eo '[0-9]+$' | head -n 1)
    export NVENC_GPU_INDEX="${NVENC_GPU_INDEX:-${DETECTED_GPU:-0}}"
fi

# Inject Libnice NAT 1-to-1 Mapping if BDWIND_ICE_IP is specified
if [ -n "${BDWIND_ICE_IP}" ]; then
    # Support format: LOCAL_IP:PUBLIC_IP (e.g. 10.241.109.6:36.170.21.98)
    # or just PUBLIC_IP (e.g. 36.170.21.98) for auto-detection of local IP
    if echo "${BDWIND_ICE_IP}" | grep -q ':'; then
        # Explicit LOCAL:PUBLIC format, use directly
        export NICE_NAT_1TO1="${BDWIND_ICE_IP}"
        echo "BDWIND_ICE_IP explicit mapping. Force ICE Candidates to: ${NICE_NAT_1TO1}"
    else
        # Only public IP given, auto-detect local IP
        LOCAL_IP=$(ip -4 route get 114.114.114.114 2>/dev/null | grep -oP 'src \K\S+' || hostname -I 2>/dev/null | awk '{print $1}')
        if [ -n "$LOCAL_IP" ]; then
            export NICE_NAT_1TO1="${LOCAL_IP}:${BDWIND_ICE_IP}"
            echo "BDWIND_ICE_IP detected. Force mapping ICE Candidates to: ${NICE_NAT_1TO1}"
        else
            echo "WARNING: Could not determine LOCAL_IP for NAT mapping."
        fi
    fi
fi

# Start the BDWIND-GStreamer WebRTC HTML5 remote desktop application
# 使用 python3 -m 直接启动模块，等效于 pip 安装的 bdwind-gstreamer 入口脚本，
# 但不依赖 pip console_scripts，兼容 volume 热挂载调试场景。
export DBUS_SESSION_BUS_ADDRESS="unix:path=${XDG_RUNTIME_DIR}/bus"

# Ensure pipewire has a target sink to capture audio from in completely headless environments
until pactl info > /dev/null 2>&1; do sleep 0.5; done
pactl list short sinks | grep -q VirtualSink || pactl load-module module-null-sink sink_name=VirtualSink sink_properties=device.description=Virtual_Sink || true
pactl set-default-sink VirtualSink || true
pactl set-default-source VirtualSink.monitor || true

# Intercept broken encoders: Vulkan Video is unstable in CDI containers, fall back to NVENC CUDA
if [ "$BDWIND_ENCODER" = "vulkanh264enc" ] || [ "$BDWIND_ENCODER" = "vulkanh265enc" ]; then
    echo "WARNING: $BDWIND_ENCODER (Vulkan Video) is unstable in CDI container. Falling back to nvh264enc (NVENC CUDA)."
    export BDWIND_ENCODER="nvh264enc"
fi

/opt/stark-runtime/bin/python3 -m bdwind_gstreamer \
    --encoder="${BDWIND_ENCODER:-nvh264enc}" \
    --addr="127.0.0.1" \
    --port="${BDWIND_PORT_GSTREAMER:-8081}" \
    --enable_basic_auth="false" \
    --enable_metrics_http="true" \
    --metrics_http_port="${BDWIND_PORT_METRICS:-9081}" \
    $@
