# 文件系统所有权修复说明

## 修复日期

2026-02-18

## 问题描述

之前的镜像构建过程中，执行了 `chown -R ubuntu:ubuntu /`，将整个文件系统的所有权改为 ubuntu 用户。这导致：

1. `/var/lib` 等系统目录的所有者变成 ubuntu，而不是标准的 root
2. 某些依赖文件所有者进行安全检查的程序无法正常工作（如 Flatpak 的 bwrap）
3. 与标准 Linux 系统的行为不一致，增加调试难度

## 修复内容

### 修改的文件

1. `scripts/base/base-system-setup.sh`
2. `nvidia/egl/Dockerfile`
3. `nvidia/glx/Dockerfile`

### 修改前

```bash
# 将整个文件系统的所有权更改为ubuntu用户
chown -R -f -h --no-preserve-root ubuntu:ubuntu /
```

### 修改后

```bash
# 只对必要的目录更改所有权为ubuntu用户，保持系统目录为root所有者
chown -R -f ubuntu:ubuntu /home/ubuntu
chown -R -f ubuntu:ubuntu /tmp
chown -R -f ubuntu:ubuntu /var/tmp
chown -R -f ubuntu:ubuntu /opt
chown -R -f ubuntu:ubuntu /usr/local
mkdir -p /run/user/1000
chown -R -f ubuntu:ubuntu /run/user/1000
```

## 影响范围

### 保持 root:root 所有者的目录

以下目录现在保持标准的 `root:root` 所有者：

- `/var/lib/apt` - APT 包管理器数据
- `/var/lib/dpkg` - DPKG 包管理器数据
- `/var/lib/systemd` - Systemd 数据
- `/usr/bin` - 系统二进制文件
- `/usr/sbin` - 系统管理工具
- `/usr/lib` - 系统库文件
- `/etc` - 系统配置文件

### 改为 ubuntu:ubuntu 所有者的目录

以下目录的所有者为 `ubuntu:ubuntu`：

- `/home/ubuntu` - 用户主目录
- `/tmp` - 临时文件目录
- `/var/tmp` - 临时文件目录
- `/opt` - 可选应用程序目录
- `/usr/local` - 本地安装的程序目录
- `/run/user/1000` - 用户运行时目录

## 预期效果

### 解决的问题

1. ✅ Flatpak 的 bwrap 工具可以正常工作（需要 root 所有者）
2. ✅ 符合标准 Linux 系统的文件权限模型
3. ✅ 其他依赖文件所有者的安全检查可以正常工作
4. ✅ 调试和问题排查更容易

### 保持的功能

1. ✅ ubuntu 用户仍然可以在必要的目录工作
2. ✅ 保持 rootless 容器的安全优势
3. ✅ 所有现有功能继续正常工作

## 验证方法

### 方法 1：手动检查权限

```bash
# 检查系统目录（应该是 root:root）
ls -ld /var/lib/apt
ls -ld /usr/bin
ls -ld /etc

# 检查用户目录（应该是 ubuntu:ubuntu）
ls -ld /home/ubuntu
ls -ld /opt
ls -ld /usr/local

# 检查 bwrap 权限（应该是 root:root 且有 setuid 位）
ls -l /usr/bin/bwrap
```

### 方法 2：测试 Flatpak

```bash
# 安装 Flatpak
sudo apt update && sudo apt install -y flatpak

# 使用 sudo-root 修复 bwrap 权限（如果需要）
sudo-root chown root:root /usr/bin/bwrap
sudo-root chmod 4755 /usr/bin/bwrap

# 测试 Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak search firefox
```

## 兼容性说明

### 向后兼容性

这个修复**可能**影响以下场景：

1. **自定义脚本**：如果有脚本假设所有文件都属于 ubuntu 用户，可能需要调整
2. **权限依赖**：如果有代码依赖特定目录的所有者，可能需要检查

### 建议的迁移步骤

1. **测试环境验证**：在测试环境中构建新镜像并充分测试
2. **检查自定义脚本**：检查是否有脚本依赖文件所有权
3. **更新文档**：更新相关文档说明新的权限模型
4. **逐步部署**：先在非生产环境部署，确认无问题后再推广

## 构建新镜像

### 构建命令

```bash
# 构建基础镜像
docker build -f .beagle/nvidia-egl-base.Dockerfile -t beagle-wind-vnc:nvidia-egl-base .

# 构建桌面镜像
docker build -f .beagle/nvidia-egl-desktop.Dockerfile -t beagle-wind-vnc:nvidia-egl-desktop .
```

### 验证构建

```bash
# 启动容器
docker run -it --rm beagle-wind-vnc:nvidia-egl-desktop bash

# 检查文件权限
ls -ld /var/lib/apt /usr/bin /home/ubuntu /opt
```

## 回滚方案

如果发现问题需要回滚，可以：

1. **使用旧版本镜像**：切换回修复前的镜像版本
2. **临时修改**：在容器启动时执行 `chown -R ubuntu:ubuntu /`（不推荐）

## 相关文档

- [文件系统所有权问题分析](./filesystem-ownership-issue.md)
- [Flatpak bwrap 权限问题](./flatpak-bwrap-permission-issue.md)
- [fakeroot 深入分析](./fakeroot.md)

## 技术支持

如有问题，请：

1. 查看相关文档
2. 检查文件权限：`ls -ld /var/lib/apt /usr/bin /home/ubuntu`
3. 提交 GitHub Issue 并附上权限信息

## 总结

这次修复解决了文件系统所有权过于激进的问题，在保持 rootless 容器安全优势的同时，恢复了标准的 Linux 文件权限模型。这使得更多依赖标准权限的工具（如 Flatpak）可以正常工作。
