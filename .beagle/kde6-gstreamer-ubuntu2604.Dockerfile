# ==============================================================================
# KDE6 GStreamer Build Base Image (Ubuntu 26.04)
#
# Pre-installs the dependencies required by gstreamer/KDE6/build.sh, including
# the Rust toolchain used to build gst-wayland-display with CUDA support.
#
# Usage from the parent workspace:
#   docker run --rm -it \
#     -v "${PWD}/gstreamer:/workspace" \
#     -w /workspace \
#     registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:build-1.28.6-ubuntu2604 \
#     bash KDE6/build.sh
# ==============================================================================

ARG BASE=ubuntu:26.04
FROM ${BASE}

ARG GSTREAMER_VERSION=1.28.6
ARG RUST_VERSION=1.88.0

LABEL maintainer="https://github.com/open-beagle"
LABEL org.opencontainers.image.title="beagle-wind-vnc KDE6 GStreamer builder"
LABEL org.opencontainers.image.description="Ubuntu 26.04 builder for KDE6 GStreamer and gst-wayland-display"
LABEL com.beagle.gstreamer.version="${GSTREAMER_VERSION}"
LABEL com.beagle.rust.version="${RUST_VERSION}"

ENV DEBIAN_FRONTEND=noninteractive
ENV CARGO_HOME=/root/.cargo
ENV RUSTUP_HOME=/root/.rustup
ENV PATH=/root/.cargo/bin:${PATH}

RUN sed -i 's#http://archive.ubuntu.com#http://azure.archive.ubuntu.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    sed -i 's#http://security.ubuntu.com#http://azure.archive.ubuntu.com#g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    apt-get update && \
    apt-get install --no-install-recommends -y \
      apt-utils \
      build-essential \
      ca-certificates \
      curl \
      git \
      gzip \
      pkg-config \
      tar \
      xz-utils \
      autopoint \
      autoconf \
      automake \
      autotools-dev \
      binutils \
      bison \
      flex \
      gettext \
      khronos-api \
      libtool-bin \
      nasm \
      valgrind \
      yasm \
      libgmp-dev \
      libgsl-dev \
      libgcrypt20-dev \
      libgirepository1.0-dev \
      glib-networking \
      libglib2.0-dev \
      libgudev-1.0-dev \
      libasound2-dev \
      libjack-jackd2-dev \
      libopus-dev \
      libpulse-dev \
      libssl-dev \
      libva-dev \
      libvpx-dev \
      libx264-dev \
      libx265-dev \
      libdrm-dev \
      libegl-dev \
      libgl-dev \
      libopengl-dev \
      libgles-dev \
      libglvnd-dev \
      libglx-dev \
      wayland-protocols \
      libwayland-dev \
      libinput-dev \
      libxkbcommon-dev \
      libgbm-dev \
      libudev-dev \
      libclang-dev \
      libwayland-egl-backend-dev \
      libx11-xcb-dev \
      libxcb-dri3-dev \
      libxcb-sync-dev \
      libxdamage-dev \
      libxfixes-dev \
      libxv-dev \
      libxtst-dev \
      libxext-dev \
      libpipewire-0.3-dev \
      libspa-0.2-dev \
      libopenh264-dev \
      svt-av1 \
      libsvtav1enc-dev \
      aom-tools \
      libaom-dev \
      python3-pip \
      python3-dev \
      python-gi-dev \
      python3-pil \
      python3-setuptools && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install \
      --no-cache-dir \
      --break-system-packages \
      cmake \
      meson \
      ninja \
      gitlint \
      tomli

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --default-toolchain "${RUST_VERSION}" && \
    cargo install cargo-c --version 0.10.16 --locked

RUN git clone \
      --single-branch \
      --depth 1 \
      --branch "${GSTREAMER_VERSION}" \
      https://github.com/GStreamer/gstreamer.git \
      /opt/gst-src && \
    cd /opt/gst-src && \
    meson subprojects download

RUN touch /etc/bdwind-build-ready

WORKDIR /workspace
