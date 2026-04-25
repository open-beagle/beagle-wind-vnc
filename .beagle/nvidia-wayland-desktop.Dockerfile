# =============================================================================
# P8: Arch Linux Desktop Image (Steam, Wine, Lutris, Hyprland)
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
RUN pacman -Sy --noconfirm --needed \
    wine \
    winetricks \
    joyutils \
    mangohud \
    gamemode \
    jq \
    inetutils \
    lutris \
    steam \
    nginx \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    chromium \
    waybar \
    foot \
    foot-terminfo \
    wofi \
    dolphin \
    kded \
    kio-extras \
    swaybg \
    wl-clipboard && \
    pacman -Scc --noconfirm

# 向桌面灌入系统默认壁纸底图
COPY src/img/ /usr/share/backgrounds/beagle/
RUN ln -sf /usr/share/backgrounds/beagle/1920x1080.png /usr/share/backgrounds/beagle/default.png

# =============================================================================
# 部署自编译的 GStreamer 1.28.2 串流引擎 + Aquamarine 0.10.0 补丁版
# =============================================================================
# 1. NVRTC 动态库（GStreamer nvcodec 隐式依赖）
#    注意：libnvrtc.so 内部会 dlopen("libnvrtc-builtins.so.12.9")，
#    必须创建带完整版本号的符号链接，否则 NVENC 编码器无法注册。
RUN pip install --break-system-packages nvidia-cuda-nvrtc-cu12 && \
    ln -sf /usr/lib/python3.*/site-packages/nvidia/cuda_nvrtc/lib/libnvrtc.so.12 /usr/lib/libnvrtc.so || true && \
    ln -sf /usr/lib/python3.*/site-packages/nvidia/cuda_nvrtc/lib/libnvrtc-builtins.so* /usr/lib/libnvrtc-builtins.so || true && \
    for f in /usr/lib/python3.*/site-packages/nvidia/cuda_nvrtc/lib/libnvrtc-builtins.so.*; do \
        [ -f "$f" ] && ln -sf "$f" "/usr/lib/$(basename $f)" || true; \
    done

# 2. 从 OSS 拉取自编译的 Arch Linux 专属版 GStreamer 1.28.2
RUN curl -O -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gstreamer-1.28.2-archlinux.tar.gz" && \
    tar -xzf bdwind-gstreamer-1.28.2-archlinux.tar.gz -C /opt && \
    rm -f bdwind-gstreamer-1.28.2-archlinux.tar.gz

# 3. 部署自编译的 Aquamarine 0.10.0（§30.1 锁控流补丁版）
#    修复 headless 后端 DRM render node + idleCallbacks 时序
RUN curl -O -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-aquamarine-0.10.0-archlinux.tar.gz" && \
    tar -xzf bdwind-aquamarine-0.10.0-archlinux.tar.gz -C /opt && \
    rm -f bdwind-aquamarine-0.10.0-archlinux.tar.gz && \
    cd /opt/aquamarine/lib && \
    ln -sf libaquamarine.so.0.10.0 libaquamarine.so && \
    ln -sf libaquamarine.so.0.10.0 libaquamarine.so.0

# 4. WebRTC 前端 + Gamepad 服务
RUN mkdir -p /opt/gstreamer/patches /opt/bdwind/webrtc && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-gamepad-1.1.0.tar.gz" | tar -xzf - -C /opt/gstreamer/patches/ && \
    curl -fsSL "https://cache.ali.wodcloud.com/vscode/bdwind/bdwind-webrtc-1.28.2.tar.gz" | tar -xzf - -C /opt/bdwind/webrtc --strip-components=1 || true

# 拷贝 Wayland 下专属控制配置文件与环境
# 注意：所有配置统一放 /etc/beagle-wind-vnc/，用户级配置由 entrypoint.sh 启动时拷贝到 ~/.config/
# 这样 /home/beagle 被挂载外部卷时不会丢失默认配置
RUN mkdir -p /etc/beagle-wind-vnc/user/hypr /etc/beagle-wind-vnc/user/waybar
COPY ./nvidia/wayland/entrypoint.sh /etc/beagle-wind-vnc/entrypoint.sh
COPY ./nvidia/wayland/bdwind-gstreamer.sh /etc/beagle-wind-vnc/bdwind-gstreamer.sh
COPY ./nvidia/wayland/bdwind-gamepad.sh /etc/beagle-wind-vnc/bdwind-gamepad.sh
COPY ./nvidia/wayland/bdwind-hyprland.sh /etc/beagle-wind-vnc/bdwind-hyprland.sh
COPY ./nvidia/wayland/mock-picker.sh /etc/beagle-wind-vnc/mock-picker.sh
COPY ./nvidia/wayland/supervisord.conf /etc/beagle-wind-vnc/supervisord.conf
COPY ./nvidia/wayland/user/hypr/hyprland.conf /etc/beagle-wind-vnc/user/hypr/hyprland.conf
COPY ./nvidia/wayland/user/hypr/xdph.conf /etc/beagle-wind-vnc/user/hypr/xdph.conf
COPY ./nvidia/wayland/user/waybar/config /etc/beagle-wind-vnc/user/waybar/config
COPY ./nvidia/wayland/user/waybar/style.css /etc/beagle-wind-vnc/user/waybar/style.css
COPY ./nvidia/wayland/user/wofi /etc/beagle-wind-vnc/user/wofi
COPY ./nvidia/wayland/user/foot /etc/beagle-wind-vnc/user/foot

RUN chmod 755 /opt/gstreamer/patches/joystick-server \
    /etc/beagle-wind-vnc/entrypoint.sh \
    /etc/beagle-wind-vnc/bdwind-gstreamer.sh \
    /etc/beagle-wind-vnc/bdwind-gamepad.sh \
    /etc/beagle-wind-vnc/bdwind-hyprland.sh \
    /etc/beagle-wind-vnc/mock-picker.sh \
    /etc/beagle-wind-vnc/supervisord.conf

# 切回安全用户组，准备接入 GStreamer + Wayland 信令拦截进程
USER 1000
SHELL ["/bin/bash", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"

# =============================================================================
# Project P8-Stark: 构建 Python 独立运行虚拟环境
# =============================================================================
RUN sudo pacman -Sy --noconfirm --needed base-devel cairo pkgconf gobject-introspection && \
    sudo mkdir -p /usr/share/fonts/GoogleSansCode && \
    curl -fsSL "https://github.com/sahibjotsaggu/Google-Sans-Fonts/archive/refs/heads/master.tar.gz" | sudo tar -xz -C /usr/share/fonts/GoogleSansCode --strip-components=1 && \
    sudo fc-cache -fv && \
    sudo mkdir -p /opt/stark-runtime && \
    sudo chown -R 1000:1000 /opt/stark-runtime && \
    python3 -m venv /opt/stark-runtime && \
    /opt/stark-runtime/bin/pip install setuptools PyGObject Pillow psutil evdev msgpack websockets prometheus-client basicauth pynput watchdog GPUtil dbus-python && \
    sudo pacman -Rns --noconfirm base-devel && \
    sudo pacman -Scc --noconfirm

# -----------------------------------------------------------------------------
# Expose Self-compiled GStreamer Globally
# -----------------------------------------------------------------------------
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="${GSTREAMER_PATH}/patches:${GSTREAMER_PATH}/bin${PATH:+:${PATH}}"

# Arch Linux 纯净目录映射
ENV LD_LIBRARY_PATH="${GSTREAMER_PATH}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
ENV GST_PLUGIN_PATH="${GSTREAMER_PATH}/lib/gstreamer-1.0:${GSTREAMER_PATH}/patches:/usr/lib/gstreamer-1.0${GST_PLUGIN_PATH:+:${GST_PLUGIN_PATH}}"
ENV XDG_DATA_HOME="/home/beagle/.local/share"
ENV GST_PLUGIN_SYSTEM_PATH="${GSTREAMER_PATH}/lib/gstreamer-1.0:/usr/lib/gstreamer-1.0${GST_PLUGIN_SYSTEM_PATH:+:${GST_PLUGIN_SYSTEM_PATH}}"
ENV GI_TYPELIB_PATH="${GSTREAMER_PATH}/lib/girepository-1.0:/usr/lib/girepository-1.0${GI_TYPELIB_PATH:+:${GI_TYPELIB_PATH}}"
ENV PYTHONPATH="${GSTREAMER_PATH}/lib/python3/dist-packages${PYTHONPATH:+:${PYTHONPATH}}"

ENV XDG_RUNTIME_DIR=/tmp/runtime-beagle
ENV USER=beagle
ENV PIPEWIRE_RUNTIME_DIR="/tmp/runtime-beagle"
ENV PULSE_RUNTIME_PATH="/tmp/runtime-beagle/pulse"
ENV PULSE_SERVER="unix:/tmp/runtime-beagle/pulse/native"

ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/runtime-beagle/dbus-session-bus"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/runtime-beagle/dbus-session-bus"

ENV SDL_JOYSTICK_DEVICE=/dev/input/js0

# 把控制权真正交给 entrypoint.sh
ENTRYPOINT ["/etc/beagle-wind-vnc/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/beagle-wind-vnc/supervisord.conf"]
