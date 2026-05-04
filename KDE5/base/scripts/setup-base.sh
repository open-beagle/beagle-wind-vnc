#!/bin/bash
set -e

# =============================================================================
# 基础系统设置脚本
# 为容器环境配置无root权限的用户环境，适用于受限条件下的约束环境
# =============================================================================
# 清理并更新系统包，安装基础依赖
apt-get clean && apt-get update && apt-get dist-upgrade -y
apt-get install --no-install-recommends -y \
  apt-utils \
  dbus-user-session \
  fuse \
  kmod \
  locales \
  ssl-cert \
  sudo \
  udev \
  tzdata
# 清理系统缓存和临时文件
apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/debconf/* /var/log/* /tmp/* /var/tmp/*
# 生成系统语言环境
locale-gen en_US.UTF-8
locale-gen zh_CN.UTF-8
locale-gen zh_CN.GBK
# 设置默认语言为中文UTF-8
update-locale LANG=zh_CN.UTF-8
# 设置时区
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" >/etc/timezone

# =============================================================================
# 配置sudo权限系统
# beagle用户可以使用sudo执行需要root权限的操作
# =============================================================================
# 不再使用fakeroot，保持标准sudo功能
# =============================================================================
# 创建beagle用户
# =============================================================================
# 如果是 Ubuntu 24.04 官方镜像，默认已经有一个 UID 1000 的 ubuntu 用户，直接重命名并迁移 home 目录即可
if id "ubuntu" &>/dev/null; then
    usermod -l beagle ubuntu || echo 'Failed to rename ubuntu user'
    groupmod -n beagle ubuntu || echo 'Failed to rename ubuntu group'
    usermod -d /home/beagle -m beagle || echo 'Failed to move home directory'
else
    groupadd -g 1000 beagle || echo 'Failed to add beagle group'
    useradd -ms /bin/bash beagle -u 1000 -g 1000 || echo 'Failed to add beagle user'
fi
# 将beagle用户添加到各种系统组
usermod -a -G adm,audio,cdrom,dialout,dip,fax,floppy,games,input,lp,plugdev,render,ssl-cert,sudo,tape,tty,video,voice beagle
# 配置sudo权限，允许beagle用户无密码执行所有命令
echo "beagle ALL=(ALL:ALL) NOPASSWD: ALL" >>/etc/sudoers
# 设置beagle用户密码
echo "beagle:${PASSWD}" | chpasswd

# =============================================================================
# 设置文件系统所有权
# =============================================================================
# 只对必要的目录更改所有权为beagle用户，保持系统目录为root所有者
# 用户主目录
chown -R -f beagle:beagle /home/beagle || echo 'Failed to set /home/beagle ownership'
# 应用程序目录（存放 gstreamer、selkies-gstreamer-web 等）
chown -R -f beagle:beagle /opt || echo 'Failed to set /opt ownership'
# 本地安装目录（存放 Python 包、NVIDIA 库、工具等）
chown -R -f beagle:beagle /usr/local || echo 'Failed to set /usr/local ownership'
# 运行时目录
mkdir -p /run/user/1000
chown -R -f beagle:beagle /run/user/1000 || echo 'Failed to set /run/user/1000 ownership'
# 临时目录
chown -R -f beagle:beagle /tmp /var/tmp || echo 'Failed to set /tmp ownership'

# =============================================================================
# 恢复被chown移除的setuid/setgid权限
# =============================================================================
# 设置setuid权限（4755）
chmod -f 4755 /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/bin/chfn /usr/bin/chsh /usr/bin/mount /usr/bin/gpasswd /usr/bin/passwd /usr/bin/newgrp /usr/bin/umount /usr/bin/su /usr/bin/sudo /usr/bin/fusermount || echo 'Failed to set chmod setuid for some paths'
# 设置setgid权限（2755）
chmod -f 2755 /var/local /var/mail /usr/sbin/unix_chkpwd /usr/sbin/pam_extrausers_chkpwd /usr/bin/expiry /usr/bin/chage || echo 'Failed to set chmod setgid for some paths'
