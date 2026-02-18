# Docker 容器中 Flatpak bwrap 权限问题分析

## 问题描述

在 Docker 容器 `registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop-1.0.9` 中安装 Flatpak 后，遇到 `/usr/bin/bwrap` 文件权限无法修改的问题。

### 现象

```bash
ubuntu@container:~$ ls -l /usr/bin/bwrap
-rwxr-xr-x 1 ubuntu ubuntu 72160  9月 24  2024 /usr/bin/bwrap

ubuntu@container:~$ sudo chown root:root /usr/bin/bwrap
ubuntu@container:~$ sudo chmod 4755 /usr/bin/bwrap

ubuntu@container:~$ ls -l /usr/bin/bwrap
-rwsr-xr-x 1 ubuntu ubuntu 72160  9月 24  2024 /usr/bin/bwrap
```

执行 `chown` 后，所有者仍然是 `ubuntu:ubuntu` 而不是 `root:root`，虽然 setuid 位（s）设置成功了。

### 容器启动参数

```bash
docker run -d \
  --privileged \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=false \
  ...
```

## 根本原因分析

### 1. 镜像的文件系统所有权设计

查看 `nvidia/egl/Dockerfile` 的构建过程，发现关键问题：

```dockerfile
# 第 24-26 行
chown -R -f -h --no-preserve-root ubuntu:ubuntu / || echo 'Failed to set filesystem ownership in some paths to ubuntu user' && \
# Preserve setuid/setgid removed by chown
chmod -f 4755 /usr/lib/dbus-1.0/dbus-daemon-launch-helper /usr/bin/chfn /usr/bin/chsh ...
```

**核心问题**：镜像构建时执行了 `chown -R ubuntu:ubuntu /`，将整个根文件系统的所有权递归地改为 `ubuntu:ubuntu`。这是一个非常激进的操作，导致：

1. 所有系统文件的所有者都变成了 `ubuntu:ubuntu`
2. 后续在容器运行时安装的任何软件包，其文件所有权也会受到影响
3. 即使使用 `sudo chown root:root` 也无法改变，因为 `sudo` 被替换为 `fakeroot`

### 2. sudo 被替换为 fakeroot

```dockerfile
# 第 19 行
mv -f /usr/bin/sudo /usr/bin/sudo-root && \
ln -snf /usr/bin/fakeroot /usr/bin/sudo && \
```

镜像将真正的 `sudo` 重命名为 `sudo-root`，并将 `sudo` 符号链接到 `fakeroot`。这意味着：

- 普通的 `sudo` 命令实际上是 `fakeroot`，只能模拟 root 权限
- `fakeroot` 无法真正改变文件的所有者，只能在其环境内模拟
- 只有 `sudo-root` 才是真正的 sudo，但需要容器有真正的 root 权限

### 3. 为什么 setuid 位能设置成功

`chmod 4755` 能够成功设置 setuid 位，是因为：

- `chmod` 修改的是文件权限位，不涉及所有权
- 即使文件所有者是 `ubuntu`，也可以设置 setuid 位
- 但是，setuid 位对非 root 所有者的文件没有实际意义（不会提升权限）

## Flatpak 的要求

Flatpak 的沙箱机制依赖 `bwrap` (bubblewrap) 工具，要求：

```bash
-rwsr-xr-x 1 root root /usr/bin/bwrap
```

- 所有者必须是 `root:root`
- 必须设置 setuid 位（4755）
- 这样普通用户执行时才能获得必要的权限来创建命名空间和沙箱

## 立即可用的解决方案

### 方案 A：在运行中的容器内修复（推荐，立即生效）

如果你已经有一个运行中的容器，可以立即执行以下命令：

```bash
# 1. 进入容器
docker exec -it <container_id> bash

# 2. 安装 Flatpak（如果还没安装）
sudo apt update && sudo apt install -y flatpak

# 3. 使用 sudo-root 修复 bwrap 权限
sudo-root chown root:root /usr/bin/bwrap
sudo-root chmod 4755 /usr/bin/bwrap

# 4. 验证权限
ls -l /usr/bin/bwrap
# 应该显示：-rwsr-xr-x 1 root root

# 5. 测试 Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak search firefox
```

**注意事项**：

- 容器必须以 `--privileged` 或 `--security-opt no-new-privileges=false` 启动
- 这个修复在容器重启后会失效，需要重新执行

### 方案 B：通过 entrypoint 脚本自动修复（持久化）

修改容器启动脚本，让每次启动时自动修复权限。

编辑 `nvidia/egl/entrypoint.sh`，在文件开头添加：

```bash
# 在 "set -e" 之后添加
# 修复 Flatpak bwrap 权限
if [ -f "/usr/bin/bwrap" ]; then
    echo "Fixing Flatpak bwrap permissions..."
    sudo-root chown root:root /usr/bin/bwrap 2>/dev/null || true
    sudo-root chmod 4755 /usr/bin/bwrap 2>/dev/null || true
fi
```

然后重新构建镜像。

### 方案 C：在 Dockerfile 中预装 Flatpak（最佳实践）

在镜像构建时就处理好权限问题，这样用户使用时就不会遇到问题。

## 长期解决方案

### 方案 1：在 Dockerfile 构建时预装 Flatpak（推荐）

在镜像构建阶段安装 Flatpak，此时可以正确设置权限：

```dockerfile
# 在 nvidia/egl/Dockerfile 或 .beagle/nvidia-egl-desktop.Dockerfile 中添加
RUN apt-get update && apt-get install -y flatpak && \
    # 确保 bwrap 有正确的权限
    sudo-root chown root:root /usr/bin/bwrap && \
    sudo-root chmod 4755 /usr/bin/bwrap && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
```

### 方案 2：修改镜像构建逻辑，不对整个根文件系统执行 chown

这是更根本的解决方案，但需要重新设计镜像：

```dockerfile
# 不要执行 chown -R ubuntu:ubuntu /
# 而是只对必要的目录执行 chown
chown -R ubuntu:ubuntu /home/ubuntu /tmp /var/tmp
```

但这可能会影响现有的容器运行逻辑，需要全面测试。

### 方案 3：在容器启动时使用 entrypoint 脚本修复权限

修改 `nvidia/egl/entrypoint.sh`，在启动时修复 bwrap 权限：

```bash
# 在 entrypoint.sh 开头添加
if [ -f "/usr/bin/bwrap" ]; then
    sudo-root chown root:root /usr/bin/bwrap 2>/dev/null || true
    sudo-root chmod 4755 /usr/bin/bwrap 2>/dev/null || true
fi
```

### 方案 4：使用 --user-ns-remap 或特权容器

如果必须在运行时安装 Flatpak，可以：

1. 使用真正的 `sudo-root` 而不是 `sudo`：

```bash
sudo-root chown root:root /usr/bin/bwrap
sudo-root chmod 4755 /usr/bin/bwrap
```

2. 或者在容器启动时添加 `--cap-add=SYS_ADMIN` 和 `--cap-add=SETUID`：

```bash
docker run -d \
  --privileged \
  --cap-add=SYS_ADMIN \
  --cap-add=SETUID \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=false \
  ...
```

## 推荐实施步骤

根据你的情况选择最合适的方案：

### 场景 1：你现在就想用 Flatpak（立即解决）

**使用方案 A - 在运行中的容器内修复**

```bash
# 1. 进入你的容器
docker exec -it <你的容器名或ID> bash

# 2. 安装 Flatpak
sudo apt update && sudo apt install -y flatpak

# 3. 使用 sudo-root 修复权限（关键步骤！）
sudo-root chown root:root /usr/bin/bwrap
sudo-root chmod 4755 /usr/bin/bwrap

# 4. 验证权限是否正确
ls -l /usr/bin/bwrap
# 必须显示：-rwsr-xr-x 1 root root

# 5. 添加 Flathub 仓库
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

# 6. 测试安装一个应用
flatpak install -y flathub org.mozilla.firefox
flatpak run org.mozilla.firefox
```

**注意**：容器重启后需要重新执行步骤 3。

### 场景 2：你在构建自己的镜像（推荐方案）

**使用方案 1 + 方案 B - Dockerfile + entrypoint 双保险**

1. **编辑 `.beagle/nvidia-egl-desktop.Dockerfile`**，在安装其他软件后添加：

```dockerfile
# 在 Steam、Chrome 等软件安装之后添加
# Install Flatpak
RUN sudo apt-get update && sudo apt-get install -y flatpak && \
    # 使用 sudo-root 设置正确的权限
    sudo-root chown root:root /usr/bin/bwrap && \
    sudo-root chmod 4755 /usr/bin/bwrap && \
    # 添加 Flathub 仓库
    flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo && \
    sudo apt-get clean && rm -rf /var/lib/apt/lists/*
```

2. **编辑 `nvidia/egl/entrypoint.sh`**，在 `set -e` 之后添加：

```bash
#!/bin/bash

set -e

trap "echo TRAPed signal" HUP INT QUIT TERM

# 修复 Flatpak bwrap 权限（如果已安装）
if [ -f "/usr/bin/bwrap" ]; then
    echo "Fixing Flatpak bwrap permissions..."
    sudo-root chown root:root /usr/bin/bwrap 2>/dev/null || echo "Warning: Failed to fix bwrap permissions"
    sudo-root chmod 4755 /usr/bin/bwrap 2>/dev/null || true
fi

# Wait for XDG_RUNTIME_DIR
until [ -d "${XDG_RUNTIME_DIR}" ]; do sleep 0.5; done
# ... 其余代码保持不变
```

3. **重新构建镜像**：

```bash
# 根据你的构建流程
docker build -f .beagle/nvidia-egl-desktop.Dockerfile -t my-desktop:latest .
```

4. **测试新镜像**：

```bash
docker run -d \
  --name test-desktop \
  --privileged \
  --security-opt no-new-privileges=false \
  -p 8080:8080 \
  my-desktop:latest

# 进入容器测试
docker exec -it test-desktop bash
flatpak search firefox
```

### 场景 3：你想彻底解决这个问题（长期方案）

**使用方案 2 - 重新设计文件系统权限**

这需要修改 `scripts/base/base-system-setup.sh`：

```bash
# 不要执行 chown -R ubuntu:ubuntu /
# 改为只对必要的目录执行 chown
chown -R ubuntu:ubuntu /home/ubuntu /tmp /var/tmp /opt /usr/local
```

**警告**：这需要大量测试，可能影响现有功能。建议：

1. 先在测试环境验证
2. 检查所有依赖 ubuntu 用户权限的路径
3. 更新相关文档

### 快速决策表

| 你的需求           | 推荐方案        | 优点     | 缺点           |
| ------------------ | --------------- | -------- | -------------- |
| 现在就要用 Flatpak | 方案 A          | 立即生效 | 重启失效       |
| 构建新镜像         | 方案 1 + 方案 B | 一劳永逸 | 需要重新构建   |
| 不想重新构建       | 方案 B          | 持久化   | 需要修改代码   |
| 彻底解决           | 方案 2          | 根本解决 | 风险高，需测试 |

### 我的建议

如果你是：

- **普通用户**：使用方案 A，简单快速
- **镜像维护者**：使用方案 1 + 方案 B，为所有用户解决问题
- **架构师**：考虑方案 2，但需要充分评估和测试

## 相关文件

- `nvidia/egl/Dockerfile` - 基础镜像构建文件（第 24-26 行的 chown 操作）
- `.beagle/nvidia-egl-desktop.Dockerfile` - 桌面环境扩展镜像
- `nvidia/egl/entrypoint.sh` - 容器启动脚本

## 为什么容器要使用 fakeroot 替换 sudo？

这个镜像采用了 **Rootless Container** 安全设计模式，使用 fakeroot 替换 sudo 来实现无根容器环境。

### 核心原因概述

1. **安全性**：以非 root 用户运行容器，降低容器逃逸风险
2. **环境适配**：适应 Kubernetes、多租户等受限环境
3. **兼容性**：让软件安装脚本中的 `sudo` 调用不报错，同时不授予真实 root 权限
4. **最小权限原则**：符合容器安全最佳实践

### 实现机制

```bash
# 从 scripts/base/base-system-setup.sh
mv -f /usr/bin/sudo /usr/bin/sudo-root
ln -snf /usr/bin/fakeroot /usr/bin/sudo
```

- 真正的 sudo 被重命名为 `sudo-root`
- `sudo` 符号链接到 `fakeroot`，模拟 root 权限但不授予真实权限
- fakeroot 通过 LD_PRELOAD 拦截系统调用，在内存中维护"虚拟"权限

### Flatpak 冲突的本质

Flatpak 的 bwrap 工具设计假设：

- 运行在传统的 Linux 系统上
- `/usr/bin/bwrap` 由 root 所有，带 setuid 位
- 普通用户执行时可以提升权限创建命名空间

但在这个 rootless 容器中：

- 所有文件都属于 ubuntu 用户（`chown -R ubuntu:ubuntu /`）
- fakeroot 无法真正改变文件所有者为 root
- 即使设置了 setuid 位，也不会提升权限（因为所有者不是 root）

这是 **rootless 安全设计** 与 **传统特权工具** 之间的根本冲突。

> 📖 **深入阅读**：关于 fakeroot 的详细分析、工作原理、设计权衡和最佳实践对比，请参阅 [fakeroot.md](./fakeroot.md)

## 技术背景

- **fakeroot**：模拟 root 权限的工具，通过 LD_PRELOAD 拦截系统调用，常用于构建 deb 包，但不能真正改变文件所有权
- **bubblewrap (bwrap)**：轻量级沙箱工具，Flatpak 用它创建应用隔离环境，需要 setuid root 权限
- **setuid bit**：允许普通用户以文件所有者身份执行程序的特殊权限位
- **Rootless Container**：容器安全最佳实践，以非 root 用户运行容器进程，降低安全风险
- **Principle of Least Privilege**：最小权限原则，只授予完成任务所需的最小权限

## 验证方法

安装 Flatpak 后，执行以下命令验证：

```bash
# 检查 bwrap 权限
ls -l /usr/bin/bwrap
# 应该显示：-rwsr-xr-x 1 root root

# 测试 Flatpak
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo
flatpak search firefox
```

如果权限正确，Flatpak 应该能正常工作而不报错。
