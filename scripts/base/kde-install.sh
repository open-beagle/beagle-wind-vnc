#!/bin/bash
set -e

# =============================================================================
# KDE桌面环境安装脚本
# 安装KDE和其他GUI包
# =============================================================================

# 配置Firefox PPA，禁用snap版本
mkdir -pm755 /etc/apt/preferences.d
echo "Package: firefox*\n\
Pin: version 1:1snap*\n\
Pin-Priority: -1" >/etc/apt/preferences.d/firefox-nosnap

# 添加Mozilla团队PPA密钥
mkdir -pm755 /etc/apt/trusted.gpg.d
curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x738BEB9321D1AAEC13EA9391AEBDF4819BE21867" | gpg --dearmor -o /etc/apt/trusted.gpg.d/mozillateam-ubuntu-ppa.gpg

# 添加Mozilla团队PPA源
mkdir -pm755 /etc/apt/sources.list.d
echo "deb https://ppa.launchpadcontent.net/mozillateam/ppa/ubuntu $(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"') main" >"/etc/apt/sources.list.d/mozillateam-ubuntu-ppa-$(grep '^VERSION_CODENAME=' /etc/os-release | cut -d= -f2 | tr -d '\"').list"

# 安装KDE桌面环境及常用GUI包
# 分类说明：
# - KDE基础应用：kde-baseapps, plasma-desktop, plasma-workspace, dolphin, kwrite, kcalc, kcharselect, kdeadmin
# - 主题和图标：adwaita-icon-theme-full, breeze, breeze-cursor-theme, breeze-gtk-theme, breeze-icon-theme
# - 系统工具：kinfocenter, systemsettings, kdf, kfind, kget, khotkeys, kmenuedit, kmix, kmousetool, kmouth, ktimer, kwin-addons, kwin-x11
# - 输入法框架：fcitx系列包（fcitx, fcitx-frontend-gtk2/gtk3/qt5, fcitx-module-*, fcitx-hangul, fcitx-libpinyin, fcitx-m17n, fcitx-mozc, fcitx-sayura, fcitx-unikey）
# - 实用工具：ark, filelight, gwenview, kde-spectacle, kdialog, ksshaskpass, sweeper, print-manager, qapt-deb-installer
# - KDE框架库：frameworkintegration, kio, kio-extras, libkf5*系列包
# - 多媒体支持：kimageformat-plugins, libqt5multimedia5-plugins, qtspeech5-flite-plugin, qtvirtualkeyboard-plugin
# - Plasma组件：plasma-browser-integration, plasma-calendar-addons, plasma-dataengines-addons, plasma-discover, plasma-integration, plasma-runners-addons, plasma-widgets-addons
# - QML模块：qml-module-org-kde-runnermodel, qml-module-org-kde-qqc2desktopstyle, qml-module-qtgraphicaleffects, qml-module-qt-labs-platform, qml-module-qtquick-xmllistmodel
# - Qt主题和插件：qt5-gtk-platformtheme, qt5-image-formats-plugins, qt5-style-plugins
# - 其他工具：appmenu-gtk3-module, dbus-x11, debconf-kde-helper, desktop-file-utils, enchant-2, haveged, hunspell, im-config, libdbusmenu-*, libgail-common, libgdk-pixbuf2.0-bin, libgtk-*, librsvg2-common, media-player-info, okular, okular-extra-backends, software-properties-qt, sonnet-plugins, ubuntu-drivers-common, xdg-user-dirs, xdg-utils
# - 媒体播放器：vlc系列包（vlc, vlc-plugin-access-extra, vlc-plugin-notify, vlc-plugin-samba, vlc-plugin-skins2, vlc-plugin-video-splitter, vlc-plugin-visualization）
# - 桌面环境工具：kdeconnect, kde-config-fcitx, kde-config-gtk-style, kde-config-gtk-style-preview, kdegraphics-thumbnailers, kmag
# - 网络浏览器：firefox, transmission-qt
apt-get update
apt-get install --no-install-recommends -y \
  kde-baseapps \
  plasma-desktop \
  plasma-workspace \
  adwaita-icon-theme-full \
  appmenu-gtk3-module \
  ark \
  aspell \
  aspell-en \
  breeze \
  breeze-cursor-theme \
  breeze-gtk-theme \
  breeze-icon-theme \
  dbus-x11 \
  debconf-kde-helper \
  desktop-file-utils \
  dolphin \
  dolphin-plugins \
  enchant-2 \
  fcitx \
  fcitx-frontend-gtk2 \
  fcitx-frontend-gtk3 \
  fcitx-frontend-qt5 \
  fcitx-module-dbus \
  fcitx-module-kimpanel \
  fcitx-module-lua \
  fcitx-module-x11 \
  fcitx-tools \
  fcitx-hangul \
  fcitx-libpinyin \
  fcitx-m17n \
  fcitx-mozc \
  fcitx-sayura \
  fcitx-unikey \
  filelight \
  frameworkintegration \
  gwenview \
  haveged \
  hunspell \
  im-config \
  kwrite \
  kcalc \
  kcharselect \
  kdeadmin \
  kde-config-fcitx \
  kde-config-gtk-style \
  kde-config-gtk-style-preview \
  kdeconnect \
  kdegraphics-thumbnailers \
  kde-spectacle \
  kdf \
  kdialog \
  kfind \
  kget \
  khotkeys \
  kimageformat-plugins \
  kinfocenter \
  kio \
  kio-extras \
  kmag \
  kmenuedit \
  kmix \
  kmousetool \
  kmouth \
  ksshaskpass \
  ktimer \
  kwin-addons \
  kwin-x11 \
  libdbusmenu-glib4 \
  libdbusmenu-gtk3-4 \
  libgail-common \
  libgdk-pixbuf2.0-bin \
  libgtk2.0-bin \
  libgtk-3-bin \
  libkf5baloowidgets-bin \
  libkf5dbusaddons-bin \
  libkf5iconthemes-bin \
  libkf5kdelibs4support5-bin \
  libkf5khtml-bin \
  libkf5parts-plugins \
  libqt5multimedia5-plugins \
  librsvg2-common \
  media-player-info \
  okular \
  okular-extra-backends \
  plasma-browser-integration \
  plasma-calendar-addons \
  plasma-dataengines-addons \
  plasma-discover \
  plasma-integration \
  plasma-runners-addons \
  plasma-widgets-addons \
  print-manager \
  qapt-deb-installer \
  qml-module-org-kde-runnermodel \
  qml-module-org-kde-qqc2desktopstyle \
  qml-module-qtgraphicaleffects \
  qml-module-qt-labs-platform \
  qml-module-qtquick-xmllistmodel \
  qt5-gtk-platformtheme \
  qt5-image-formats-plugins \
  qt5-style-plugins \
  qtspeech5-flite-plugin \
  qtvirtualkeyboard-plugin \
  software-properties-qt \
  sonnet-plugins \
  sweeper \
  systemsettings \
  ubuntu-drivers-common \
  vlc \
  vlc-plugin-access-extra \
  vlc-plugin-notify \
  vlc-plugin-samba \
  vlc-plugin-skins2 \
  vlc-plugin-video-splitter \
  vlc-plugin-visualization \
  xdg-user-dirs \
  xdg-utils \
  firefox \
  transmission-qt

# 安装LibreOffice办公套件
apt-get install --install-recommends -y \
  libreoffice \
  libreoffice-kf5 \
  libreoffice-plasma \
  libreoffice-style-breeze

# ===============================
# 中文语言支持与KDE本地化
# ===============================
# 安装中文语言包和KDE中文支持
apt-get install --no-install-recommends -y \
  language-pack-zh-hans \
  language-pack-gnome-zh-hans \
  language-pack-kde-zh-hans \
  kde-l10n-zhcn || true

# KDE Plasma 默认语言设置（全局）
echo '[Locale]' > /etc/xdg/plasma-localerc
echo 'LANG=zh_CN.UTF-8' >> /etc/xdg/plasma-localerc

# 确保Firefox作为默认网络浏览器
xdg-settings set default-web-browser firefox.desktop
update-alternatives --set x-www-browser /usr/bin/firefox

# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*

# =============================================================================
# 修复容器中KDE启动权限问题
# =============================================================================
MULTI_ARCH=$(dpkg --print-architecture | sed -e 's/arm64/aarch64-linux-gnu/' -e 's/armhf/arm-linux-gnueabihf/' -e 's/riscv64/riscv64-linux-gnu/' -e 's/ppc64el/powerpc64le-linux-gnu/' -e 's/s390x/s390x-linux-gnu/' -e 's/i.*86/i386-linux-gnu/' -e 's/amd64/x86_64-linux-gnu/' -e 's/unknown/x86_64-linux-gnu/')
cp -f /usr/lib/${MULTI_ARCH}/libexec/kf5/start_kdeinit /tmp/
rm -f /usr/lib/${MULTI_ARCH}/libexec/kf5/start_kdeinit
cp -f /tmp/start_kdeinit /usr/lib/${MULTI_ARCH}/libexec/kf5/start_kdeinit
rm -f /tmp/start_kdeinit

# =============================================================================
# KDE桌面环境配置
# =============================================================================
# 禁用屏幕锁定
echo "[Daemon]\n\
Autolock=false\n\
LockOnResume=false" >/etc/xdg/kscreenlockerrc
# 禁用合成器
echo "[Compositing]\n\
Enabled=false" >/etc/xdg/kwinrc
# 配置KDE全局设置
echo "[KDE]\n\
SingleClick=false\n\
\n\
[KDE Action Restrictions]\n\
action/lock_screen=false\n\
logout=false\n\
\n\
[General]\n\
BrowserApplication=firefox.desktop" >/etc/xdg/kdeglobals
