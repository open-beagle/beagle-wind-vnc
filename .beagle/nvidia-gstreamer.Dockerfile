# ==============================================================================
# GStreamer 1.28.2 Build Base Image (Arch Linux)
#
# This image pre-installs ALL build dependencies (pacman, pip, rust, cargo-c)
# and pre-clones GStreamer source so that scripts/build.sh only patches and compiles.
#
# Usage:
#   docker run --rm -it \
#     -v $(pwd)/gstreamer:/workspace \
#     -w /workspace \
#     registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:build-1.28.2-arch \
#     bash scripts/build.sh
# ==============================================================================

FROM archlinux:latest

# --- Step 1: Init pacman mirroring ---
RUN echo "Server = https://mirrors.aliyun.com/archlinux/\$repo/os/\$arch" > /etc/pacman.d/mirrorlist && \
    echo "Server = https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist && \
    echo "Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch" >> /etc/pacman.d/mirrorlist && \
    sed -i '/\[options\]/a DisableDownloadTimeout' /etc/pacman.conf && \
    pacman -Syu --noconfirm

# --- Step 2+3: System + GStreamer Build Deps + Codecs ---
# ffnvcodec-headers is crucial for enabling nvh264enc / nvh265enc
RUN pacman -S --noconfirm --needed \
    base-devel git curl wget pkgconf cmake \
    meson ninja python python-pip python-gobject \
    glib2 libgudev openssl libsoup3 glib-networking \
    libdrm libglvnd vulkan-headers vulkan-icd-loader \
    wayland wayland-protocols libx11 libxcb libxext libxfixes libxdamage libxv libxtst \
    x264 x265 libvpx aom svt-av1 opus libpulse alsa-lib jack pipewire \
    ffnvcodec-headers nasm yasm gettext && \
    rm -rf /var/cache/pacman/pkg/*

# --- Step 4: Python tools ---
RUN pip install -i https://mirrors.aliyun.com/pypi/simple/ --break-system-packages --no-cache-dir gitlint tomli

# --- Step 5: Rust / Cargo toolchain (upstream) ---
ENV CARGO_HOME="/root/.cargo"
ENV RUSTUP_HOME="/root/.rustup"
ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    cargo install cargo-c

# --- Step 6 (partial): Pre-clone GStreamer source to save bandwidth ---
ENV GSTREAMER_VERSION="1.28.2"
RUN git clone --single-branch --depth 1 --branch "${GSTREAMER_VERSION}" \
        "https://github.com/GStreamer/gstreamer.git" /opt/gst-src

# Marker file so build.sh can detect the pre-built environment
RUN touch /etc/bdwind-build-ready

WORKDIR /workspace
