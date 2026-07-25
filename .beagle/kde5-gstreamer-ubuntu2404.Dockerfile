# ==============================================================================
# GStreamer Build Base Image
#
# This image pre-installs ALL build dependencies (apt, pip, rust, cargo-c)
# and pre-clones GStreamer source so that scripts/build.sh only patches and compiles.
#
# Usage:
#   docker run --rm -it \
#     -v $(pwd)/gstreamer:/workspace \
#     -w /workspace \
#     registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:build-${GSTREAMER_VERSION} \
#     bash KDE6/build.sh
# ==============================================================================

ARG BASE=ubuntu:24.04
FROM ${BASE}

ARG GSTREAMER_VERSION=1.28.2

ENV DEBIAN_FRONTEND=noninteractive

# --- Step 1+2+3: System + GStreamer Build Deps + Codecs ---
RUN sed -i 's#http://archive.ubuntu.com#http://azure.archive.ubuntu.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    sed -i 's#http://security.ubuntu.com#http://azure.archive.ubuntu.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    apt-get update && apt-get install --no-install-recommends -y \
    apt-utils build-essential ca-certificates curl git gzip \
    pkg-config tar xz-utils \
    autopoint autoconf automake autotools-dev binutils bison flex gettext \
    khronos-api libtool-bin nasm valgrind yasm \
    libgmp-dev libgsl-dev libgcrypt20-dev libgirepository1.0-dev \
    glib-networking libglib2.0-dev libgudev-1.0-dev \
    libasound2-dev libjack-jackd2-dev libopus-dev libpulse-dev \
    libssl-dev libva-dev libvpx-dev libx264-dev libx265-dev \
    libdrm-dev libegl-dev libgl-dev libopengl-dev libgles-dev \
    libglvnd-dev libglx-dev wayland-protocols libwayland-dev \
    libinput-dev libxkbcommon-dev libgbm-dev libudev-dev libclang-dev \
    libwayland-egl-backend-dev libx11-xcb-dev libxcb-dri3-dev libxcb-sync-dev \
    libxdamage-dev libxfixes-dev libxv-dev libxtst-dev libxext-dev \
    libpipewire-0.3-dev libspa-0.2-dev \
    libopenh264-dev svt-av1 libsvtav1enc-dev aom-tools libaom-dev \
    python3-pip python3-dev python-gi-dev python3-pil python3-setuptools && \
    rm -rf /var/lib/apt/lists/*

# --- Step 4: Meson / Ninja / Python tools ---
RUN pip3 install --no-cache-dir cmake meson ninja gitlint tomli --break-system-packages

# --- Step 5: Rust / Cargo toolchain (upstream) ---
ENV CARGO_HOME="/root/.cargo"
ENV RUSTUP_HOME="/root/.rustup"
ENV PATH="/root/.cargo/bin:${PATH}"

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && \
    cargo install cargo-c

# --- Step 6 (partial): Pre-clone GStreamer source to save bandwidth ---
RUN git clone --single-branch --depth 1 --branch "${GSTREAMER_VERSION}" \
        "https://github.com/GStreamer/gstreamer.git" /opt/gst-src && \
    cd /opt/gst-src && \
    meson subprojects download

# Marker file so build.sh can detect the pre-built environment
RUN touch /etc/bdwind-build-ready

WORKDIR /workspace
