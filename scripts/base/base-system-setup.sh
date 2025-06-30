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
  fakeroot \
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
# 仅对root拥有的目录(/dev, /proc, /sys)或用户/组权限操作使用sudo-root
# 不用于apt-get安装或文件/目录操作
# =============================================================================
mv -f /usr/bin/sudo /usr/bin/sudo-root
ln -snf /usr/bin/fakeroot /usr/bin/sudo
# =============================================================================
# 创建ubuntu用户和组
# =============================================================================
groupadd -g 1000 ubuntu || echo 'Failed to add ubuntu group'
useradd -ms /bin/bash ubuntu -u 1000 -g 1000 || echo 'Failed to add ubuntu user'
# 将ubuntu用户添加到各种系统组
usermod -a -G adm,audio,cdrom,dialout,dip,fax,floppy,games,input,lp,plugdev,render,polkitd,ssl-cert,sudo,tape,tty,video,voice ubuntu
# 配置sudo权限，允许ubuntu用户无密码执行所有命令
echo "ubuntu ALL=(ALL:ALL) NOPASSWD: ALL" >>/etc/sudoers
# 设置ubuntu用户密码
echo "ubuntu:${PASSWD}" | chpasswd
# =============================================================================
# 设置文件系统所有权
# =============================================================================
# 将整个文件系统的所有权更改为ubuntu用户（保留root权限）
chown -R -f -h --no-preserve-root ubuntu:ubuntu / || echo 'Failed to set filesystem ownership in some paths to ubuntu user'
# =============================================================================
# 恢复被chown移除的setuid/setgid权限
# =============================================================================
# 设置setuid权限（4755）
chmod -f 4755 /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/bin/chfn /usr/bin/chsh /usr/bin/mount /usr/bin/gpasswd /usr/bin/passwd /usr/bin/newgrp /usr/bin/umount /usr/bin/su /usr/bin/sudo-root /usr/bin/fusermount || echo 'Failed to set chmod setuid for some paths'
# 设置setgid权限（2755）
chmod -f 2755 /var/local /var/mail /usr/sbin/unix_chkpwd /usr/sbin/pam_extrausers_chkpwd /usr/bin/expiry /usr/bin/chage || echo 'Failed to set chmod setgid for some paths'
