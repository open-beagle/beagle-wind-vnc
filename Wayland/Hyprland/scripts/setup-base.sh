#!/bin/bash
set -e

# =============================================================================
# 基础系统设置脚本
# 为容器环境配置无root权限的用户环境，适用于受限条件下的约束环境
# =============================================================================

# 清理并更新系统包，安装基础依赖
sed -i '/\[options\]/a DisableDownloadTimeout' /etc/pacman.conf || true
pacman -Syu --noconfirm \
  kmod \
  sudo \
  tzdata \
  base-devel

# 清理系统缓存和临时文件
rm -rf /var/cache/pacman/pkg/* /var/log/* /tmp/* /var/tmp/*

# 生成系统语言环境
sed -i -e 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
sed -i -e 's/#zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
sed -i -e 's/#zh_CN.GBK GBK/zh_CN.GBK GBK/' /etc/locale.gen
locale-gen

# 设置默认语言为中文UTF-8
echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
# 设置时区
ln -snf "/usr/share/zoneinfo/${TZ}" /etc/localtime && echo "${TZ}" >/etc/timezone
# =============================================================================
# 配置sudo权限系统
# ubuntu用户可以使用sudo执行需要root权限的操作
# =============================================================================
# 不再使用fakeroot，保持标准sudo功能
# =============================================================================
# 创建ubuntu用户和组
# =============================================================================
groupadd -g 1000 ubuntu || echo 'Failed to add ubuntu group'
useradd -ms /bin/bash ubuntu -u 1000 -g 1000 || echo 'Failed to add ubuntu user'
# 将ubuntu用户添加到各种系统组
usermod -a -G adm,audio,cdrom,disk,floppy,games,input,lp,rfkill,render,tty,video ubuntu || true
# 配置sudo权限，允许ubuntu用户无密码执行所有命令
echo "ubuntu ALL=(ALL:ALL) NOPASSWD: ALL" >>/etc/sudoers
# 设置ubuntu用户密码
echo "ubuntu:${PASSWD}" | chpasswd
# =============================================================================
# 设置文件系统所有权
# =============================================================================
# 只对必要的目录更改所有权为ubuntu用户，保持系统目录为root所有者
# 用户主目录
chown -R -f ubuntu:ubuntu /home/ubuntu || echo 'Failed to set /home/ubuntu ownership'
# 应用程序目录（存放 gstreamer、selkies-gstreamer-web 等）
chown -R -f ubuntu:ubuntu /opt || echo 'Failed to set /opt ownership'
# 本地安装目录（存放 Python 包、NVIDIA 库、工具等）
chown -R -f ubuntu:ubuntu /usr/local || echo 'Failed to set /usr/local ownership'
# 运行时目录
mkdir -p /run/user/1000
chown -R -f ubuntu:ubuntu /run/user/1000 || echo 'Failed to set /run/user/1000 ownership'
# 临时目录
chown -R -f ubuntu:ubuntu /tmp /var/tmp || echo 'Failed to set /tmp ownership'
# =============================================================================
# 恢复被chown移除的setuid/setgid权限
# =============================================================================
# 设置setuid权限（4755）
chmod -f 4755 /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/bin/chfn /usr/bin/chsh /usr/bin/mount /usr/bin/gpasswd /usr/bin/passwd /usr/bin/newgrp /usr/bin/umount /usr/bin/su /usr/bin/sudo /usr/bin/fusermount || echo 'Failed to set chmod setuid for some paths'
# 设置setgid权限（2755）
chmod -f 2755 /var/local /var/mail /usr/sbin/unix_chkpwd /usr/sbin/pam_extrausers_chkpwd /usr/bin/expiry /usr/bin/chage || echo 'Failed to set chmod setgid for some paths'
