# 继承我们刚刚打好的神级 Wayland 底座
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-wayland-base-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

USER 0
SHELL ["/bin/sh", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

# =============================================================================
# 一站式灌入所有娱乐与生产力引擎 (Steam, Wine, Lutris)
# 在 Wayland 下，不管是跑 GLX 还是 EGL 的游戏，全都通过 Xwayland 或 Native Wayland 降维打击统一处理！
# =============================================================================
RUN apt update && \
  # 1. 安装 Wine 体系 (跑 Windows 游戏必备)
  apt install --install-recommends -y wine wine32:i386 wine64 && \
  apt install --no-install-recommends -y q4wine playonlinux && \
  # 2. 安装 Winetricks 与环境依赖
  curl -o /usr/bin/winetricks -fsSL "https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks" && \
  chmod -f 755 /usr/bin/winetricks && \
  # 3. 安装手柄和外设管理工具
  apt install -y xboxdrv joystick jstest-gtk mangohud gamemode jq && \
  apt install -y pipx && pipx ensurepath && pipx install protontricks && \
  # 4. 安装 Lutris (开源游戏收纳站)
  LUTRIS_VERSION="$(curl -fsSL "https://api.github.com/repos/lutris/lutris/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9\.\-]*//g')" && \
  curl -o /tmp/lutris.deb -fsSL "https://github.com/lutris/lutris/releases/download/v${LUTRIS_VERSION}/lutris_${LUTRIS_VERSION}_all.deb" && \
  apt install -y /tmp/lutris.deb && rm -f /tmp/lutris.deb && \
  # 5. 安装 Steam
  curl -o /tmp/steam_latest.deb -fL https://repo.steampowered.com/steam/archive/precise/steam_latest.deb && \
  apt install -y /tmp/steam_latest.deb && rm -f /tmp/steam_latest.deb && \
  apt update && apt install -y steam steam-launcher \
  libc6:amd64 libc6:i386 \
  steam-libs-amd64:amd64 steam-libs-i386:i386 && \
  # 6. 安装 Chrome
  curl -o /tmp/google-chrome-stable.deb -fsSL "https://dl.google.com/linux/direct/google-chrome-stable_current_$(dpkg --print-architecture).deb" && \
  apt install -y /tmp/google-chrome-stable.deb && rm -f /tmp/google-chrome-stable.deb && \
  sed -i '/^Exec=/ s/$/ --password-store=basic --in-process-gpu/' /usr/share/applications/google-chrome.desktop && \
  # 7. 清理战场
  apt clean && \
  rm -rf /usr/share/vulkan/icd.d/*.json && \
  rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# 向桌面灌入默认背景图 (这里可依据产品定制)
# 向桌面灌入默认背景图 (这里可依据产品定制)
COPY src/img/ /usr/share/wallpapers/Next/contents/images/

# =============================================================================
# Beagle-Wind WebRTC & Streaming Engine Setup
# =============================================================================
# 安装运行时核心依赖 (由于废弃了独立安装脚本，必须在此处补齐 Python 与 GStreamer 的强绑定库)
RUN apt update && apt install --no-install-recommends -y \
  libnvrtc12 \
  libnvidia-egl-wayland1 \
  libnvidia-egl-gbm1 \
  wl-clipboard \
  python3-pip \
  python3-dev \
  python3-gi \
  python3-setuptools \
  python3-wheel \
  libgcrypt20-dev \
  libgirepository1.0-dev \
  glib-networking \
  libglib2.0-dev \
  libgudev-1.0-dev \
  libasound2-dev \
  jackd2 \
  libjack-jackd2-dev \
  libpulse-dev \
  libopus-dev \
  libvpx-dev \
  libx264-dev \
  libx265-dev \
  libaom-dev \
  libsvtav1enc-dev \
  libopenh264-dev \
  libnice10 \
  libsoup-3.0-0 \
  libsrtp2-1 \
  libgraphene-1.0-0 \
  libgssdp-1.6-0 \
  libgupnp-1.6-0 \
  libgupnp-igd-1.6-0 \
  libbrotli-dev && \
  ln -sf /usr/lib/x86_64-linux-gnu/libnvrtc.so.12 /usr/lib/x86_64-linux-gnu/libnvrtc.so || true && \
  apt clean && rm -rf /var/lib/apt/lists/*

# 从 Aliyun OSS 取得编译好的 GStreamer 1.28.1 容器引擎压缩包
RUN curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gstreamer-1.28.1-ubuntu25.04.tar.gz" | tar -xzf - -C /opt || true

# 拷贝 WebRTC 前端与 Python 启动脚本至指定层
RUN curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.0.0.tar.gz" | tar -xzf - -C /usr/bin/ && \
    mkdir -p /opt/bdwind/webrtc && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-webrtc-1.28.1.tar.gz" | tar -xzf - -C /opt/bdwind/webrtc --strip-components=1 || true

# 创建 KWin GBM 劫持补丁链接 (由原生 GStreamer 包内附带提供)
RUN ln -sf /opt/gstreamer/lib/kwin_drm_hook.so /opt/kwin_drm_hook.so || true

# 拷贝 Wayland 下专属控制配置文件
COPY ./nvidia/wayland/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./nvidia/bdwind-gstreamer.sh /etc/beagle-wind-vnc/bdwind-gstreamer.sh
COPY ./nvidia/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
COPY ./nvidia/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh
COPY ./nvidia/bdwind-gamepad.sh /etc/beagle-wind-vnc/bdwind-gamepad.sh
COPY ./nvidia/wayland/supervisord.conf /etc/supervisord.conf
COPY ./nvidia/desktop-services.conf /etc/supervisor/conf.d/desktop-services.conf

RUN chmod 755 /usr/bin/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/bdwind-gstreamer.sh \
    /etc/beagle-wind-vnc/steam-game.sh \
    /etc/beagle-wind-vnc/bgctl.sh \
    /etc/beagle-wind-vnc/bdwind-gamepad.sh \
    /etc/supervisord.conf

# 安装 GStreamer Python 打包出的 Wheel (bdwind-gstreamer 引擎)
RUN pip3 install --break-system-packages --ignore-installed --no-cache-dir /opt/gstreamer/lib/python3/dist-packages/*.whl

# 切回安全用户组，准备接入 GStreamer + Wayland 信令拦截进程
USER 1000
SHELL ["/bin/sh", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"

# -----------------------------------------------------------------------------
# Expose Self-compiled GStreamer Globally
# -----------------------------------------------------------------------------
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="${GSTREAMER_PATH}/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV GST_PLUGIN_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu/gstreamer-1.0${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}"
ENV GST_PLUGIN_SYSTEM_PATH="${XDG_DATA_HOME:-/home/ubuntu/.local/share}/gstreamer-1.0/plugins:/usr/lib/x86_64-linux-gnu/gstreamer-1.0${GST_PLUGIN_SYSTEM_PATH:+:${GST_PLUGIN_SYSTEM_PATH}}"
ENV GI_TYPELIB_PATH="${GSTREAMER_PATH}/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/x86_64-linux-gnu/girepository-1.0${GI_TYPELIB_PATH:+:${GI_TYPELIB_PATH}}"
ENV PYTHONPATH="${GSTREAMER_PATH}/lib/python3/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"

ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV USER=ubuntu
ENV PIPEWIRE_RUNTIME_DIR="/tmp/runtime-ubuntu"
ENV PULSE_RUNTIME_PATH="/tmp/runtime-ubuntu/pulse"
ENV PULSE_SERVER="unix:/tmp/runtime-ubuntu/pulse/native"

ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-system-bus"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-session-bus"

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]
