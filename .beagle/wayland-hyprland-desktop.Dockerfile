# 继承我们刚刚打好的神级 Wayland 底座
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:wayland-hyprland-base-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

USER 0
SHELL ["/bin/sh", "-c"]

ARG DEBIAN_FRONTEND=noninteractive

# =============================================================================
# 一站式灌入所有娱乐与生产力引擎 (Steam, Wine, Lutris)
# 在 Wayland 下，不管是跑 GLX 还是 EGL 的游戏，全都通过 Xwayland 或 Native Wayland 降维打击统一处理！
# =============================================================================
RUN pacman -Syu --noconfirm && \
  # 1. 安装 Wine 体系 (跑 Windows 游戏必备)
  pacman -S --noconfirm wine wine-mono wine-gecko q4wine winetricks && \
  # 2. 安装手柄和外设管理工具
  pacman -S --noconfirm xboxdrv joystick mangohud gamemode jq python-pipx && \
  pipx ensurepath && pipx install protontricks && \
  # 3. 安装 Lutris 和 Steam
  pacman -S --noconfirm lutris steam && \
  # 4. 安装 Chromium (替代 Chrome)
  pacman -S --noconfirm chromium && \
  sed -i '/^Exec=/ s/$/ --password-store=basic --in-process-gpu/' /usr/share/applications/chromium.desktop || true && \
  # 5. 清理战场
  rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/* /usr/share/vulkan/icd.d/*.json ~/.cache/pip /var/log/* /tmp/* /var/tmp/*

# 向桌面灌入默认背景图，适配 beagle-wind-desktop 的多分辨率读取特性
COPY assets/wallpapers/ /usr/share/backgrounds/beagle/
RUN ln -sf /usr/share/backgrounds/beagle/1920x1080.png /usr/share/backgrounds/beagle/default.png

# =============================================================================
# Beagle-Wind WebRTC & Streaming Engine Setup
# =============================================================================
# 安装运行时核心依赖 (由于废弃了独立安装脚本，必须在此处补齐 Python 与 GStreamer 的强绑定库)
RUN pacman -Syu --noconfirm \
  hyprland \
  xdg-desktop-portal-hyprland \
  waybar \
  swaybg \
  foot \
  wofi \
  xorg-xcursorgen \
  cairo \
  wayland \
  wayland-protocols \
  base-devel \
  git \
  egl-wayland \
  wl-clipboard \
  python-pip \
  python-gobject \
  python-setuptools \
  python-wheel \
  libgcrypt \
  gobject-introspection \
  glib-networking \
  glib2 \
  libgudev \
  alsa-lib \
  libpulse \
  opus \
  libvpx \
  x264 \
  x265 \
  aom \
  svt-av1 \
  libnice \
  libsoup3 \
  libsrtp \
  graphene \
  gssdp \
  gupnp \
  gupnp-igd \
  brotli && \
  rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*

# 从 Aliyun OSS 取得编译好的 GStreamer 1.28.2 容器引擎压缩包
RUN curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gstreamer-1.28.2-archlinux.tar.gz" | tar -xzf - -C /opt || true

# 拷贝 WebRTC 前端与 Python 启动脚本至指定层
RUN mkdir -p /opt/gstreamer/hooks /opt/bdwind/webrtc && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.1.0.tar.gz" | tar -xzf - -C /opt/gstreamer/hooks/ && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-webrtc-1.28.2-archlinux.tar.gz" | tar -xzf - -C /opt/bdwind/webrtc --strip-components=1 || true

# 注入 xdg-desktop-portal-hyprland 静态授权配门 (通过自定义脚本跳过交互弹窗)
COPY ./Wayland/Hyprland/mock-picker.sh /etc/beagle-wind-vnc/mock-picker.sh
RUN chmod 755 /etc/beagle-wind-vnc/mock-picker.sh

# 拷贝 Wayland 下专属控制配置文件
COPY ./Wayland/Hyprland/user /etc/beagle-wind-vnc/user
COPY ./Wayland/Hyprland/local.conf /etc/beagle-wind-vnc/local.conf
COPY ./Wayland/Hyprland/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./Wayland/Hyprland/scripts/start-webrtc.sh /etc/beagle-wind-vnc/start-webrtc.sh
COPY ./Wayland/Hyprland/scripts/start-gamepad.sh /etc/beagle-wind-vnc/start-gamepad.sh
COPY ./Wayland/Hyprland/supervisord.conf /etc/supervisord.conf

RUN chmod 755 /opt/gstreamer/hooks/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/start-webrtc.sh \
    /etc/beagle-wind-vnc/start-gamepad.sh \
    /etc/supervisord.conf

# 安装 GStreamer Python 打包出的 Wheel (bdwind-gstreamer 引擎)
RUN pip3 install --break-system-packages --ignore-installed --no-cache-dir /opt/gstreamer/lib/python*/site-packages/*.whl || true

# 切回安全用户组，准备接入 GStreamer + Wayland 信令拦截进程
USER 1000
SHELL ["/bin/sh", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"

# -----------------------------------------------------------------------------
# Expose Self-compiled GStreamer Globally
# -----------------------------------------------------------------------------
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="${GSTREAMER_PATH}/bin${PATH:+:${PATH}}"
ENV LD_LIBRARY_PATH="${GSTREAMER_PATH}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV GST_PLUGIN_PATH="${GSTREAMER_PATH}/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}"
ENV GST_PLUGIN_SYSTEM_PATH="${XDG_DATA_HOME:-/home/ubuntu/.local/share}/gstreamer-1.0/plugins:/usr/lib/gstreamer-1.0${GST_PLUGIN_SYSTEM_PATH:+:${GST_PLUGIN_SYSTEM_PATH}}"
ENV GI_TYPELIB_PATH="${GSTREAMER_PATH}/lib/girepository-1.0:/usr/lib/girepository-1.0${GI_TYPELIB_PATH:+:${GI_TYPELIB_PATH}}"
ENV PYTHONPATH="${GSTREAMER_PATH}/lib/python3.14/site-packages${PYTHONPATH:+:${PYTHONPATH}}"

ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV USER=ubuntu
ENV PIPEWIRE_RUNTIME_DIR="/tmp/runtime-ubuntu"
ENV PULSE_RUNTIME_PATH="/tmp/runtime-ubuntu/pulse"
ENV PULSE_SERVER="unix:/tmp/runtime-ubuntu/pulse/native"

ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-system-bus"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-session-bus"

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0
ENTRYPOINT ["/usr/bin/supervisord"]
