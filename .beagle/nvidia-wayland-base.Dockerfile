# =============================================================================
# P8: Arch Linux + Gamescope + Hyprland 云游戏底座
#
# 替代原 Ubuntu 25.04 Wayland 底座
# Arch Linux 才是唯一真神
# =============================================================================
FROM archlinux:latest

LABEL maintainer="https://github.com/open-beagle"

ARG TZ=Asia/Shanghai

SHELL ["/bin/bash", "-c"]

# =============================================================================
# Step 1: 镜像源 + 系统初始化
# =============================================================================
RUN echo 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' > /etc/pacman.d/mirrorlist && \
    echo 'Server = https://mirror.rackspace.com/archlinux/$repo/os/$arch' >> /etc/pacman.d/mirrorlist && \
    # 启用 multilib 仓库 (32 位库支持，Dota 2 / Wine 需要)
    echo -e '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist' >> /etc/pacman.conf && \
    # 放开容器精简版对 Locale 包生成的限制
    sed -i 's/^NoExtract/#NoExtract/g' /etc/pacman.conf && \
    pacman-key --init && \
    pacman-key --populate archlinux && \
    pacman -Sy --noconfirm archlinux-keyring && \
    # 强制重制 glibc，使其将之前因为 NoExtract 被吃掉的语言字典吐出来
    pacman -Syu --noconfirm && pacman -S --noconfirm glibc

# =============================================================================
# Step 2: 基础系统工具 + 语言环境
# =============================================================================
RUN pacman -S --noconfirm \
    base-devel \
    bash \
    sudo \
    dbus \
    fuse3 \
    kmod \
    tzdata \
    ca-certificates \
    curl \
    wget \
    git \
    jq \
    nano \
    vim \
    htop \
    net-tools \
    openbsd-netcat \
    unzip \
    zip \
    xz \
    zstd \
    pkg-config \
    python \
    python-pip \
    python-setuptools \
    python-wheel \
    python-pillow \
    python-gobject \
    python-cairo && \
    # 语言环境
    echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen && \
    echo 'zh_CN.UTF-8 UTF-8' >> /etc/locale.gen && \
    echo 'zh_CN.GBK GBK' >> /etc/locale.gen && \
    locale-gen && \
    echo 'LANG=zh_CN.UTF-8' > /etc/locale.conf && \
    # 时区
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" > /etc/timezone

ENV LANG="zh_CN.UTF-8"
ENV LANGUAGE="zh_CN:zh"

# =============================================================================
# Step 3: NVIDIA 驱动 + Vulkan (含 32 位支持，Dota 2 / Wine 需要)
# =============================================================================
RUN pacman -S --noconfirm --ask 4 --needed \
    nvidia-utils \
    lib32-nvidia-utils \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    vulkan-tools \
    mesa-utils \
    libva-nvidia-driver \
    opencl-nvidia \
    clinfo \
    nvtop \
    || pacman -S --noconfirm --ask 4 --needed \
    nvidia-utils \
    lib32-nvidia-utils \
    vulkan-icd-loader \
    lib32-vulkan-icd-loader \
    vulkan-tools \
    mesa-utils \
    libva-nvidia-driver \
    opencl-nvidia \
    clinfo \
    nvtop

ENV PATH="/usr/local/nvidia/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/nvidia/lib:/usr/local/nvidia/lib64"
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# =============================================================================
# Step 4: Gamescope + Hyprland + XWayland (核心合成器)
# =============================================================================
# 注意：pacman 安装的 gamescope 仅提供运行时依赖 (libei, seatd 等)
#       实际二进制会被 Step 6.5 中自编译的 v6 补丁版覆盖
RUN pacman -S --noconfirm \
    gamescope \
    hyprland \
    xdg-desktop-portal-hyprland \
    xorg-xwayland \
    wayland-protocols \
    libinput \
    libxkbcommon \
    wlr-randr \
    wl-clipboard \
    xdg-utils \
    xdg-user-dirs && \
    pacman -R --noconfirm xdg-desktop-portal-cosmic || true

# =============================================================================
# Step 5: PipeWire 音频全家桶
# =============================================================================
RUN pacman -S --noconfirm \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    pipewire-jack \
    wireplumber \
    libpulse \
    alsa-utils \
    gst-plugin-pipewire

# =============================================================================
# Step 6: 链接库路径修复（宿主机 NVIDIA 驱动兼容）
# =============================================================================
# 显式打通 Ubuntu Host -> Arch Container 的动态链接隧道
RUN echo "/usr/lib/x86_64-linux-gnu" > /etc/ld.so.conf.d/nvidia.conf && ldconfig
# =============================================================================
# Step 7: Nginx + supervisor (进程编排)
# =============================================================================
RUN pacman -S --noconfirm \
    nginx \
    supervisor && \
    # Nginx 日志重定向到 stdout/stderr
    sed -i -e 's|/var/log/nginx/access.log|/dev/stdout|g' \
           -e 's|/var/log/nginx/error.log|/dev/stderr|g' \
           /etc/nginx/nginx.conf || true

# =============================================================================
# Step 8: 字体 (中文 + Nerd Fonts + Emoji)
# =============================================================================
RUN pacman -S --noconfirm \
    noto-fonts \
    noto-fonts-cjk \
    noto-fonts-emoji \
    noto-fonts-extra \
    ttf-dejavu \
    ttf-liberation \
    ttf-hack \
    ttf-ubuntu-font-family \
    ttf-nerd-fonts-symbols

# =============================================================================
# Step 9: 输入法 (fcitx5 中文输入)
# =============================================================================
RUN pacman -S --noconfirm \
    fcitx5 \
    fcitx5-chinese-addons \
    fcitx5-gtk \
    fcitx5-qt \
    fcitx5-configtool

ENV GTK_IM_MODULE=fcitx
ENV QT_IM_MODULE=fcitx
ENV XIM=fcitx
ENV XMODIFIERS="@im=fcitx"

# =============================================================================
# Step 10: 创建用户 + sudo 权限
# =============================================================================
RUN groupadd -g 1000 beagle || true && \
    useradd -ms /bin/bash beagle -u 1000 -g 1000 || true && \
    usermod -a -G audio,video,input,render,games,wheel beagle && \
    echo "beagle ALL=(ALL:ALL) NOPASSWD: ALL" >> /etc/sudoers && \
    echo "beagle:mypasswd" | chpasswd && \
    # 修复常见目录权限，避免挂载或缓存生成失败
    chown -R -f beagle:beagle /home/beagle || true && \
    chown -R -f beagle:beagle /opt || true && \
    # 准备运行时目录
    chown -R -f beagle:beagle /run/user/1000 || true && \
    chown -R -f beagle:beagle /tmp /var/tmp || true && \
    # sudo setuid
    chmod -f 4755 /usr/bin/sudo || true

# =============================================================================
# Step 11: 环境变量 (Wayland + Gamescope)
# =============================================================================

# XDG & Session
ENV XDG_SESSION_TYPE=wayland
ENV WAYLAND_DISPLAY=wayland-0
ENV DISPLAY=":20"

# 分辨率默认值
ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
ENV DISPLAY_DPI=96
ENV DISPLAY_CDEPTH=24

# NVIDIA Wayland 核心
ENV __GLX_VENDOR_LIBRARY_NAME=nvidia
ENV __NV_PRIME_RENDER_OFFLOAD=1
ENV WLR_RENDERER=vulkan
ENV WLR_NO_HARDWARE_CURSORS=1
ENV GBM_BACKEND=nvidia-drm

# XDG 运行时
ENV XDG_RUNTIME_DIR=/tmp/runtime-beagle
ENV USER=beagle
ENV PIPEWIRE_RUNTIME_DIR="/tmp/runtime-beagle"
ENV PULSE_RUNTIME_PATH="/tmp/runtime-beagle/pulse"
ENV PULSE_SERVER="unix:/tmp/runtime-beagle/pulse/native"

# 将 DBus Socket 指向我们的无特权 runtime
ENV DBUS_SYSTEM_BUS_ADDRESS="unix:path=/tmp/runtime-beagle/dbus-system-bus"
ENV DBUS_SESSION_BUS_ADDRESS="unix:path=/tmp/runtime-beagle/dbus-session-bus"

# Gamepad
ENV SDL_JOYSTICK_DEVICE=/dev/input/js0

# =============================================================================
# Step 12: Nginx 目录权限
# =============================================================================
RUN chmod -R 777 /etc/nginx/sites-available /etc/nginx/sites-enabled 2>/dev/null || true && \
    mkdir -p /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi && \
    chown -R 1000:1000 /var/lib/nginx && \
    chmod -R 755 /var/lib/nginx

# =============================================================================
# Step 13: 清理 pacman 缓存
# =============================================================================
RUN pacman -Scc --noconfirm && \
    rm -rf /var/cache/pacman/pkg/* /tmp/* /var/tmp/*

ENV LC_ALL="zh_CN.UTF-8"

USER 1000
