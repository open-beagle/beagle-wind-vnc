ARG BASE=ubuntu:26.04
FROM ${BASE}

ARG GSTREAMER_VERSION=1.28.5
ARG BAIDUNETDISK_VERSION=4.17.7
ARG BAIDUNETDISK_SHA256=50ec18f05626a13f57ef034630416d481682bc1018539f33397d5c71bc653b3d

LABEL maintainer="https://github.com/open-beagle"
LABEL org.opencontainers.image.title="beagle-wind-vnc KDE6"
LABEL org.opencontainers.image.description="KDE Plasma 6 Wayland image with Smithay capture and GStreamer 1.28.5"
LABEL org.opencontainers.image.version="1.2.0"
LABEL com.beagle.gstreamer.version="${GSTREAMER_VERSION}"
LABEL com.beagle.gstreamer.lock="/etc/beagle-wind-vnc/kde6-gstreamer.lock"
LABEL com.beagle.webrtc.lock="/etc/beagle-wind-vnc/kde6-webrtc.lock"
LABEL com.beagle.desktop.apps="chrome,code,baidunetdisk,libreoffice,vlc,okular,gwenview,ark"

ARG DEBIAN_FRONTEND=noninteractive
ARG TZ=Asia/Shanghai

ENV TZ="${TZ}"
ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=zh_CN.UTF-8
ENV SHELL=/bin/bash
ENV DISPLAY_SIZEW=1920
ENV DISPLAY_SIZEH=1080
ENV DISPLAY_REFRESH=60
ENV XDG_SESSION_TYPE=wayland
ENV XDG_CURRENT_DESKTOP=KDE
ENV XDG_SESSION_DESKTOP=KDE
ENV XDG_CONFIG_DIRS=/etc/xdg
ENV XDG_MENU_PREFIX=plasma-
ENV DESKTOP_SESSION=plasma
ENV KDE_FULL_SESSION=true
ENV KDE_SESSION_VERSION=6
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all
ENV __GL_SYNC_TO_VBLANK=0
ENV GBM_BACKEND=nvidia-drm
ENV __GLX_VENDOR_LIBRARY_NAME=nvidia
ENV KWIN_OPENGL_INTERFACE=egl
ENV KWIN_DRM_NO_DIRECT_SCANOUT=1
ENV BDWIND_KDE6_MODE=nested-smithay
ENV BDWIND_PORTAL_VIRTUAL_PROBE=false
ENV BDWIND_ENABLE_WEBRTC=false
ENV BDWIND_GSTREAMER_REQUIRED_VERSION="${GSTREAMER_VERSION}"
ENV BDWIND_WEB_ROOT=/opt/bdwind/webrtc
ENV GSTREAMER_PATH=/opt/gstreamer
ENV PATH="/opt/gstreamer/hooks:/opt/gstreamer/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/gstreamer/lib/x86_64-linux-gnu"
ENV GST_PLUGIN_PATH="/opt/gstreamer/lib/x86_64-linux-gnu/gstreamer-1.0"
ENV GST_PLUGIN_SYSTEM_PATH="/home/beagle/.local/share/gstreamer-1.0/plugins:/usr/lib/x86_64-linux-gnu/gstreamer-1.0"
ENV GI_TYPELIB_PATH="/opt/gstreamer/lib/x86_64-linux-gnu/girepository-1.0:/usr/lib/x86_64-linux-gnu/girepository-1.0"
ENV PYTHONPATH="/opt/gstreamer/lib/python3/dist-packages"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN sed -i 's/archive.ubuntu.com/azure.archive.ubuntu.com/g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    sed -i 's/security.ubuntu.com/azure.archive.ubuntu.com/g' /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true && \
    apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install --no-install-recommends -y \
      apt-utils \
      ca-certificates \
      curl \
      dbus \
      dbus-user-session \
      dbus-x11 \
      dnsutils \
      fonts-noto-cjk \
      fcitx5 \
      fcitx5-chinese-addons \
      fcitx5-config-qt \
      fcitx5-frontend-all \
      locales \
      sudo \
      supervisor \
      tzdata \
      udev \
      procps \
      pciutils \
      kmod \
      jq \
      python3 \
      python3-dbus \
      python3-gi \
      python3-pil \
      python3-pip \
      python3-setuptools \
      python3-wheel \
      nginx \
      apache2-utils \
      pipewire \
      pipewire-pulse \
      pipewire-alsa \
      pipewire-audio-client-libraries \
      pipewire-jack \
      pipewire-v4l2 \
      libpipewire-0.3-modules \
      libspa-0.2-modules \
      wireplumber \
      plasma-desktop \
      plasma-workspace \
      kwin-wayland \
      xwayland \
      xdg-desktop-portal \
      xdg-desktop-portal-kde \
      qtwayland5 \
      qdbus-qt6 \
      kscreen \
      konsole \
      kate \
      dolphin \
      xdg-utils \
      xclip \
      wl-clipboard \
      wev \
      mesa-utils \
      vulkan-tools \
      libdrm2 \
      libegl1 \
      libgbm1 \
      libgl1 \
      libglvnd0 \
      libglx0 \
      libgles2 \
      libopengl0 \
      gstreamer1.0-tools \
      gstreamer1.0-pipewire \
      gstreamer1.0-plugins-base \
      gstreamer1.0-plugins-good \
      gstreamer1.0-plugins-bad \
      gir1.2-gstreamer-1.0 \
      gir1.2-gst-plugins-base-1.0 && \
    (apt-get install --no-install-recommends -y libnvidia-egl-wayland1 libnvidia-egl-gbm1 || true) && \
    locale-gen en_US.UTF-8 zh_CN.UTF-8 zh_CN.GBK && \
    update-locale LANG=zh_CN.UTF-8 && \
    fc-match -f '%{family}\n' 'sans-serif:lang=zh-cn' | grep -q 'Noto Sans CJK SC' && \
    ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && \
    echo "${TZ}" >/etc/timezone && \
    if getent group 1000 >/dev/null; then \
      group_name="$(getent group 1000 | cut -d: -f1)"; \
      if [ "${group_name}" != "beagle" ]; then groupmod -n beagle "${group_name}"; fi; \
    else \
      groupadd -g 1000 beagle; \
    fi && \
    if id -u beagle >/dev/null 2>&1; then \
      usermod -u 1000 -g 1000 -d /home/beagle -m -s /bin/bash beagle; \
    elif getent passwd 1000 >/dev/null; then \
      user_name="$(getent passwd 1000 | cut -d: -f1)"; \
      usermod -l beagle -d /home/beagle -m -s /bin/bash "${user_name}"; \
      usermod -g 1000 beagle; \
    else \
      useradd -ms /bin/bash -u 1000 -g 1000 beagle; \
    fi && \
    for group in adm audio cdrom dialout dip games input netdev plugdev render sudo tty video; do \
      getent group "${group}" >/dev/null || groupadd -r "${group}" 2>/dev/null || true; \
    done && \
    usermod -a -G adm,audio,cdrom,dialout,dip,games,input,netdev,plugdev,render,sudo,tty,video beagle && \
    echo "beagle ALL=(ALL:ALL) NOPASSWD: ALL" >/etc/sudoers.d/99-beagle && \
    chmod 0440 /etc/sudoers.d/99-beagle && \
    mkdir -p /run/user/1000 /home/beagle/.config /var/lib/nginx/body /var/lib/nginx/proxy /var/lib/nginx/fastcgi /var/lib/nginx/uwsgi /var/lib/nginx/scgi && \
    chown -R beagle:beagle /run/user/1000 /home/beagle /var/lib/nginx && \
    sed -i -e 's#/var/log/nginx/access.log#/dev/stdout#g' -e 's#/var/log/nginx/error.log#/dev/stderr#g' -e 's#/run/nginx.pid#/tmp/nginx.pid#g' /etc/nginx/nginx.conf && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# Baseline desktop application layer. Chrome and VS Code are downloaded from
# their official Debian endpoints and baked into the image; their package
# repositories are removed afterwards so a running desktop cannot drift.
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
      ark \
      dolphin-plugins \
      ffmpeg \
      file \
      filelight \
      git \
      gwenview \
      htop \
      kde-spectacle \
      kdegraphics-thumbnailers \
      kimageformat-plugins \
      kio-extras \
      kcalc \
      libreoffice-calc \
      libreoffice-impress \
      libreoffice-kf6 \
      libreoffice-l10n-zh-cn \
      libreoffice-style-breeze \
      libreoffice-writer \
      nano \
      okular \
      pavucontrol \
      transmission-qt \
      unzip \
      vim \
      vlc \
      xdg-user-dirs \
      xz-utils \
      zip && \
    curl --retry 3 --retry-delay 2 -fsSL \
      "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" \
      -o /tmp/google-chrome-stable.deb && \
    curl --retry 3 --retry-delay 2 -fsSL \
      "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" \
      -o /tmp/vscode.deb && \
    curl --retry 3 --retry-delay 2 -fsSL \
      "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/${BAIDUNETDISK_VERSION}/baidunetdisk_${BAIDUNETDISK_VERSION}_amd64.deb" \
      -o /tmp/baidunetdisk.deb && \
    echo "${BAIDUNETDISK_SHA256}  /tmp/baidunetdisk.deb" | sha256sum -c - && \
    echo "code code/add-microsoft-repo boolean false" | debconf-set-selections && \
    apt-get install --no-install-recommends -y \
      /tmp/baidunetdisk.deb \
      /tmp/google-chrome-stable.deb \
      /tmp/vscode.deb && \
    rm -f \
      /etc/apt/sources.list.d/google-chrome.list \
      /etc/apt/sources.list.d/vscode.list \
      /tmp/baidunetdisk.deb \
      /tmp/google-chrome-stable.deb \
      /tmp/vscode.deb && \
    test -x /usr/bin/google-chrome-stable && \
    test -x /usr/bin/code && \
    test -f /usr/share/applications/google-chrome.desktop && \
    test -f /usr/share/applications/code.desktop && \
    test -f /usr/share/applications/baidunetdisk.desktop && \
    ln -sf /usr/bin/qtpaths6 /usr/local/bin/qtpaths && \
    sed -i \
      's#^Exec=/opt/baidunetdisk/baidunetdisk --no-sandbox#Exec=/opt/baidunetdisk/baidunetdisk --no-sandbox --disable-gpu --disable-gpu-compositing#' \
      /usr/share/applications/baidunetdisk.desktop && \
    sed -i \
      's#^Exec=/usr/bin/google-chrome-stable#Exec=/usr/bin/google-chrome-stable --password-store=basic#' \
      /usr/share/applications/google-chrome.desktop && \
    grep -q -- '--disable-gpu --disable-gpu-compositing' \
      /usr/share/applications/baidunetdisk.desktop && \
    grep -q -- '--password-store=basic' \
      /usr/share/applications/google-chrome.desktop && \
    printf '[Wallet]\nEnabled=false\nFirst Use=false\n' >/etc/xdg/kwalletrc && \
    google-chrome-stable --version && \
    dpkg-query -W -f='${Package}=${Version}\n' \
      ark baidunetdisk code google-chrome-stable gwenview libreoffice-core okular vlc && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

COPY .beagle/kde6-gstreamer.lock /etc/beagle-wind-vnc/kde6-gstreamer.lock

RUN set -a && \
    . /etc/beagle-wind-vnc/kde6-gstreamer.lock && \
    set +a && \
    test "${GSTREAMER_VERSION}" = "${GSTREAMER_VERSION_LOCKED}" && \
    mkdir -p /opt && \
    echo "Downloading bdwind-gstreamer ${GSTREAMER_VERSION} (${GSTREAMER_COMMIT}) from ${GSTREAMER_TARBALL_URL}" && \
    curl -fsSL "${GSTREAMER_TARBALL_URL}" -o /tmp/bdwind-gstreamer.tar.gz && \
    echo "${GSTREAMER_TARBALL_SHA256}  /tmp/bdwind-gstreamer.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/bdwind-gstreamer.tar.gz -C /opt && \
    rm -f /tmp/bdwind-gstreamer.tar.gz && \
    test -x /opt/gstreamer/gst-env && \
    sed -i 's/import json, urllib\.parse, os/import urllib.parse/g' /opt/gstreamer/lib/python3/dist-packages/bdwind_gstreamer/signaling/signaling_server.py && \
    sed -i \
      's/enabled=args\.encoder\.startswith("nv")/enabled=args.encoder.startswith("nv") and os.environ.get("BDWIND_DISABLE_GPU_MONITOR") != "true"/' \
      /opt/gstreamer/lib/python3/dist-packages/bdwind_gstreamer/__main__.py && \
    grep -q 'BDWIND_DISABLE_GPU_MONITOR' /opt/gstreamer/lib/python3/dist-packages/bdwind_gstreamer/__main__.py && \
    . /opt/gstreamer/gst-env && \
    gst-launch-1.0 --version | tee /tmp/bdwind-gstreamer-version.txt && \
    grep -Eq "(GStreamer|version) ${GSTREAMER_VERSION}" /tmp/bdwind-gstreamer-version.txt && \
    gst-inspect-1.0 pipewiresrc | tee /tmp/bdwind-pipewiresrc.txt && \
    grep -q "Filename" /tmp/bdwind-pipewiresrc.txt && \
    rm -f /tmp/bdwind-gstreamer-version.txt /tmp/bdwind-pipewiresrc.txt

COPY .beagle/kde6-webrtc.lock /etc/beagle-wind-vnc/kde6-webrtc.lock

RUN set -a && \
    . /etc/beagle-wind-vnc/kde6-webrtc.lock && \
    set +a && \
    mkdir -p /opt/bdwind/webrtc && \
    echo "Downloading bdwind WebRTC ${WEBRTC_VERSION_LOCKED} (${WEBRTC_COMMIT}) from ${WEBRTC_TARBALL_URL}" && \
    curl -fsSL "${WEBRTC_TARBALL_URL}" -o /tmp/bdwind-webrtc.tar.gz && \
    echo "${WEBRTC_TARBALL_SHA256}  /tmp/bdwind-webrtc.tar.gz" | sha256sum -c - && \
    tar -xzf /tmp/bdwind-webrtc.tar.gz -C /opt/bdwind/webrtc && \
    rm -f /tmp/bdwind-webrtc.tar.gz && \
    test "$(cat /opt/bdwind/webrtc/.bdwind/bdwind-webrtc.commit)" = "${WEBRTC_COMMIT}" && \
    rm -rf /opt/bdwind/webrtc/.bdwind && \
    test -f /opt/bdwind/webrtc/index.html && \
    test -d /opt/bdwind/webrtc/assets

COPY KDE6/beagle-wind-vnc/ /etc/beagle-wind-vnc/

RUN chmod +x /etc/beagle-wind-vnc/*.sh /etc/beagle-wind-vnc/*.py && \
    chown -R beagle:beagle /etc/beagle-wind-vnc

USER beagle
WORKDIR /home/beagle

ENTRYPOINT ["/etc/beagle-wind-vnc/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/beagle-wind-vnc/supervisord.conf"]
