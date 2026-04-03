# ==============================================================================
# GStreamer 1.28.1 Build Base Image
#
# This image pre-installs ALL build dependencies (apt, pip, rust, cargo-c)
# and pre-clones GStreamer source so that scripts/build.sh only patches and compiles.
#
# Usage:
#   docker run --rm -it \
#     -v $(pwd)/gstreamer:/workspace \
#     -w /workspace \
#     registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:build-1.28.1 \
#     bash scripts/build.sh
# ==============================================================================

FROM ubuntu:25.04

ENV DEBIAN_FRONTEND=noninteractive

# --- Step 1+2+3: System + GStreamer Build Deps + Codecs ---
RUN apt-get update && apt-get install --no-install-recommends -y \
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
    libwayland-egl-backend-dev libx11-xcb-dev libxcb-dri3-dev \
    libxdamage-dev libxfixes-dev libxv-dev libxtst-dev libxext-dev \
    libpipewire-0.3-dev libspa-0.2-dev \
    libopenh264-dev svt-av1 libsvtav1-dev aom-tools libaom-dev \
    python3-pip python3-dev python-gi-dev && \
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
ENV GSTREAMER_VERSION="1.28.1"
RUN git clone --single-branch --depth 1 --branch "${GSTREAMER_VERSION}" \
        "https://github.com/GStreamer/gstreamer.git" /opt/gst-src

# Marker file so build.sh can detect the pre-built environment
RUN touch /etc/bdwind-build-ready

WORKDIR /workspace
