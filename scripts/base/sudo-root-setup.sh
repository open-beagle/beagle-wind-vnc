#!/bin/bash
set -e

# =============================================================================
# sudo-root权限设置脚本
# 通过uid 0启用sudo-root权限
# =============================================================================

# 检测sudo库文件路径
if [ -d "/usr/libexec/sudo" ]; then
  SUDO_LIB="/usr/libexec/sudo"
else
  SUDO_LIB="/usr/lib/sudo"
fi

# 为sudo相关文件提供root权限
chown -R -f -h --no-preserve-root root:root /usr/bin/sudo-root /etc/sudo.conf /etc/sudoers /etc/sudoers.d /etc/sudo_logsrvd.conf "${SUDO_LIB}" || echo 'Failed to provide root permissions in some paths relevant to sudo'

# 为sudo-root设置setuid权限
chmod -f 4755 /usr/bin/sudo-root || echo 'Failed to set chmod setuid for root'
