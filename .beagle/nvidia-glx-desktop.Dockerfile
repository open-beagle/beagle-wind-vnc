# Start from the base GLX image built directly from vnc/nvidia/glx/Dockerfile
FROM ghcr.io/open-beagle/beagle-wind-vnc:nvidia-glx-latest

LABEL maintainer="https://github.com/open-beagle"

# Switch to root and standard shell for package installation
USER 0
SHELL ["/bin/sh", "-c"]

# Copy custom scripts needed for steam and joystick
COPY ./addons/js-interposer/.tmp/joystick-server /usr/bin/joystick-server
COPY --chown=1000:1000 ./nvidia/egl/steam-game.sh /etc/beagle-wind-vnc/steam-game.sh
COPY ./nvidia/egl/bgctl.sh /etc/beagle-wind-vnc/bgctl.sh

# Append required services to supervisord.conf
RUN echo "\n\
[program:joystick-server]\n\
command=sudo /usr/bin/joystick-server\n\
stdout_logfile=/tmp/joystick-server.log\n\
stdout_logfile_maxbytes=5MB\n\
stdout_logfile_backups=0\n\
redirect_stderr=true\n\
stopasgroup=true\n\
stopsignal=INT\n\
autostart=true\n\
autorestart=true\n\
\n\
[program:steam-game]\n\
command=/etc/beagle-wind-vnc/steam-game.sh\n\
environment=DISPLAY=\"%(ENV_DISPLAY)s\",HOME=\"%(ENV_HOME)s\",USER=\"%(ENV_USER)s\",DBUS_SESSION_BUS_ADDRESS=\"%(ENV_DBUS_SESSION_BUS_ADDRESS)s\",DBUS_SYSTEM_BUS_ADDRESS=\"%(ENV_DBUS_SYSTEM_BUS_ADDRESS)s\",XDG_RUNTIME_DIR=\"%(ENV_XDG_RUNTIME_DIR)s\"\n\
stdout_logfile=/tmp/steam-game.log\n\
stdout_logfile_maxbytes=5MB\n\
stdout_logfile_backups=0\n\
redirect_stderr=true\n\
stopasgroup=true\n\
stopsignal=INT\n\
autostart=true\n\
autorestart=false\n\
priority=999\n\
\n\
[program:bgctl]\n\
command=/etc/beagle-wind-vnc/bgctl.sh\n\
environment=DISPLAY=\"%(ENV_DISPLAY)s\",HOME=\"%(ENV_HOME)s\",USER=\"%(ENV_USER)s\"\n\
redirect_stderr=true\n\
" >> /etc/supervisord.conf && \
    chmod 755 /usr/bin/joystick-server /etc/beagle-wind-vnc/steam-game.sh /etc/beagle-wind-vnc/bgctl.sh

ARG DEBIAN_FRONTEND=noninteractive
# Install Steam and extra packages missing from GLX base
RUN apt update && \
  apt install -y xboxdrv joystick jstest-gtk mangohud gamemode && \
  apt install -y pipx && pipx ensurepath && pipx install protontricks && \
  curl -o /tmp/steam_latest.deb -fL https://repo.steampowered.com/steam/archive/precise/steam_latest.deb && \
  apt install -y /tmp/steam_latest.deb && rm -f /tmp/steam_latest.deb && \
  apt update && apt install -y steam steam-launcher \
  libc6:amd64 libc6:i386 \
  libegl1:amd64 libegl1:i386 \
  libgbm1:amd64 libgbm1:i386 \
  libgl1-mesa-dri:amd64 libgl1-mesa-dri:i386 \
  libgl1:amd64 libgl1:i386 \
  steam-libs-amd64:amd64 steam-libs-i386:i386 \
  xdg-desktop-portal xdg-desktop-portal-kde xterm && \
  curl -o /tmp/vscode.deb -fsSL "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" && \
  apt install -y /tmp/vscode.deb && rm -f /tmp/vscode.deb && \
  curl -o /tmp/baidunetdisk_4.17.7_amd64.deb -fsSL "https://issuecdn.baidupcs.com/issue/netdisk/LinuxGuanjia/4.17.7/baidunetdisk_4.17.7_amd64.deb" && \
  apt install -y /tmp/baidunetdisk_4.17.7_amd64.deb && rm -f /tmp/baidunetdisk_4.17.7_amd64.deb && \
  # Latest python for pipx/tools
  add-apt-repository -y ppa:deadsnakes/ppa && apt-get update && apt-get install -y python3.12-venv && \
  apt clean && rm -rf /var/lib/apt/lists/*

COPY src/img/ /usr/share/wallpapers/Next/contents/images/

USER 1000
SHELL ["/bin/sh", "-c"]

ENV PATH="/usr/local/games:/usr/games:$PATH"
