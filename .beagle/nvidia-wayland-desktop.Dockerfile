# =============================================================================
# P8: Arch Linux Desktop Image (Steam, Wine, Lutris, Hyprland, Gamescope)
# 继承我们刚刚打好的极客版 Arch Linux Wayland 底座
# =============================================================================
ARG BASE=ghcr.io/open-beagle/beagle-wind-vnc:nvidia-wayland-base-latest
FROM ${BASE}

LABEL maintainer="https://github.com/open-beagle"

USER 0
SHELL ["/bin/bash", "-c"]

# =============================================================================
# 一站式灌入所有娱乐与生产力引擎 (Steam, Wine, Lutris)
# 抛弃 APT，迎接 Pacman 极速体验
# =============================================================================
RUN pacman -S --noconfirm --needed \
    wine \
    winetricks \
    q4wine \
    playonlinux \
    joyutils \
    mangohud \
    gamemode \
    jq \
    lutris \
    steam \
    nginx \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    chromium \
    waybar \
    kitty \
    wofi \
    dolphin \
    hyprpaper && \
    pacman -Scc --noconfirm

# 向桌面灌入系统默认壁纸底图
COPY src/img/ /usr/share/backgrounds/beagle/
RUN ln -sf /usr/share/backgrounds/beagle/1920x1080.png /usr/share/backgrounds/beagle/default.png

# 拷贝 WebRTC 前端与 Python 启动脚本至指定层
RUN mkdir -p /opt/gstreamer/patches /opt/bdwind/webrtc && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.1.0.tar.gz" | tar -xzf - -C /opt/gstreamer/patches/ && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-webrtc-1.28.2.tar.gz" | tar -xzf - -C /opt/bdwind/webrtc --strip-components=1 || true

# 拷贝 Wayland 下专属控制配置文件与环境
RUN mkdir -p /etc/beagle-wind-vnc /etc/xdg/hypr /home/ubuntu/.config/hypr
COPY ./nvidia/wayland/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./nvidia/bdwind-gstreamer.sh /etc/beagle-wind-vnc/bdwind-gstreamer.sh
COPY ./nvidia/bdwind-gamepad.sh /etc/beagle-wind-vnc/bdwind-gamepad.sh
COPY ./nvidia/wayland/supervisord.conf /etc/supervisord.conf
COPY ./nvidia/wayland/hyprland.conf /home/ubuntu/.config/hypr/hyprland.conf
COPY ./nvidia/wayland/hyprpaper.conf /home/ubuntu/.config/hypr/hyprpaper.conf

RUN chmod 755 /opt/gstreamer/patches/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/bdwind-gstreamer.sh \
    /etc/beagle-wind-vnc/bdwind-gamepad.sh \
    /etc/supervisord.conf && \
    chown -R ubuntu:ubuntu /home/ubuntu/.config

# 安装 GStreamer Python 打包出的 Wheel (bdwind-gstreamer 引擎)
RUN pip install --break-system-packages --ignore-installed --no-cache-dir /opt/gstreamer/lib/python3/dist-packages/*.whl

# 切回安全用户组，准备接入 GStreamer + Wayland 信令拦截进程
USER 1000
SHELL ["/bin/bash", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"

# -----------------------------------------------------------------------------
# Expose Self-compiled GStreamer Globally
# -----------------------------------------------------------------------------
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="${GSTREAMER_PATH}/bin${PATH:+:${PATH}}"
# Arch Linux 纯净目录映射
ENV LD_LIBRARY_PATH="${GSTREAMER_PATH}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV GST_PLUGIN_PATH="${GSTREAMER_PATH}/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}"
ENV GST_PLUGIN_SYSTEM_PATH="${XDG_DATA_HOME:-/home/ubuntu/.local/share}/gstreamer-1.0/plugins:/usr/lib/gstreamer-1.0${GST_PLUGIN_SYSTEM_PATH:+:${GST_PLUGIN_SYSTEM_PATH}}"
ENV GI_TYPELIB_PATH="${GSTREAMER_PATH}/lib/girepository-1.0:/usr/lib/girepository-1.0${GI_TYPELIB_PATH:+:${GI_TYPELIB_PATH}}"
ENV PYTHONPATH="${GSTREAMER_PATH}/lib/python3/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"

ENV XDG_RUNTIME_DIR=/tmp/runtime-ubuntu
ENV USER=ubuntu
ENV PIPEWIRE_RUNTIME_DIR="/tmp/runtime-ubuntu"
ENV PULSE_RUNTIME_PATH="/tmp/runtime-ubuntu/pulse"
ENV PULSE_SERVER="unix:/tmp/runtime-ubuntu/pulse/native"

ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-session-bus"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/runtime-ubuntu/dbus-session-bus"

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0

# 把控制权真正交给 entrypoint.sh，这样才能串行建立 DBus -> PipeWire -> Gamescope -> Supervisord
ENTRYPOINT ["/etc/beagle-wind-vnc/entrypoint.sh"]
CMD ["/usr/bin/supervisord"]
