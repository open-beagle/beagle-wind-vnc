# Use ubuntu:24.04 as the base image
ARG BASE=ubuntu:24.04
FROM ${BASE}

ARG AUTHOR=mengkzhaoyun@gmail.com
ARG VERSION=ubuntu-24.04
LABEL maintainer=${AUTHOR} version=${VERSION}

# Copy the ubuntu.sources file
COPY nvidia/weston/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

# Install necessary packages
ARG DEBIAN_FRONTEND=noninteractive
RUN apt update -y && \
    apt install -y --no-install-recommends \
    weston \
    freerdp2-x11 \
    gnome-terminal \
    procps \
    sudo \
    vim \
    fonts-dejavu \
    software-properties-common \
    ca-certificates \
    locales \
    winpr-utils \
    dbus-user-session

# Create a user for running Weston
RUN useradd -G video -m -s /bin/bash beagle && \
    echo 'beagle:beagle' | chpasswd && \
    usermod -aG sudo beagle && \
    usermod -aG video beagle && \
    echo '%sudo ALL=(ALL:ALL) NOPASSWD: ALL' >> /etc/sudoers

# Create a directory for the user's runtime files
RUN mkdir -p /run/user/beagle && \
    chown beagle:beagle /run/user/beagle && \
    locale-gen en_US.UTF-8

# Set the working directory
WORKDIR /home/beagle

# Copy the Weston configuration file
COPY nvidia/weston/weston.ini /home/beagle/.config/weston.ini

# Copy the entrypoint script
COPY nvidia/weston/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

# Expose the RDP port
EXPOSE 3389

# Set the entrypoint
USER beagle
ENTRYPOINT ["/opt/entrypoint.sh"]