# 文件系统所有权问题分析

> **📌 注意**：这是一个历史问题分析文档。该问题已在 2026-02-18 修复。
> 
> - ✅ **问题已修复**：详见 [修复说明](./CHANGELOG-ownership-fix.md)
> - 📋 **更新日志**：详见 [CHANGELOG](./CHANGELOG.md)
> 
> 本文档保留用于：
> - 理解问题的根本原因
> - 作为技术决策的参考
> - 帮助理解 rootless 容器的设计权衡

---

## 问题描述

在容器中执行 `ls -la /var/lib` 会发现大部分文件夹的所有者都是 `ubuntu:ubuntu`，而不是标准 Linux 系统中的 `root:root`。

```bash
# 标准 Linux 系统
drwxr-xr-x  root root  /var/lib/apt
drwxr-xr-x  root root  /var/lib/dpkg
drwxr-xr-x  root root  /var/lib/systemd

# 这个容器镜像
drwxr-xr-x  ubuntu ubuntu  /var/lib/apt
drwxr-xr-x  ubuntu ubuntu  /var/lib/dpkg
drwxr-xr-x  ubuntu ubuntu  /var/lib/systemd
```

## 根本原因

### 罪魁祸首：一行激进的 chown 命令

在 `scripts/base/base-system-setup.sh` 第 51 行：

```bash
# 将整个文件系统的所有权更改为ubuntu用户
chown -R -f -h --no-preserve-root ubuntu:ubuntu /
```

这行命令做了什么？

```
chown -R              # 递归修改
      -f              # 忽略错误
      -h              # 修改符号链接本身
      --no-preserve-root  # 允许修改根目录
      ubuntu:ubuntu   # 改为 ubuntu 用户
      /               # 从根目录开始，整个文件系统！
```

**结果**：整个文件系统（包括 `/var/lib`、`/usr`、`/etc` 等）的所有文件都被改成了 `ubuntu:ubuntu`。

## 这和 fakeroot 有什么关系？

### 关系 1：fakeroot 无法阻止这个操作

很多人误以为使用了 fakeroot 就不会真正改变文件所有权，但实际上：

1. **这行 chown 是在 Dockerfile 构建时以 root 用户执行的**
2. **不是在 fakeroot 环境中执行的**
3. **所以它真实地改变了镜像中的文件所有权**

看 Dockerfile 的执行顺序：

```dockerfile
# .beagle/nvidia-egl-base.Dockerfile

# 第 1 步：以 root 用户安装基础包
FROM ubuntu:24.04
RUN /etc/beagle-wind-vnc/scripts/base-system-setup.sh  # ← 这里执行 chown -R

# 第 2 步：切换到 ubuntu 用户
USER 1000

# 第 3 步：使用 fakeroot 作为 shell
SHELL ["/usr/bin/fakeroot", "--", "/bin/sh", "-c"]

# 第 4 步：后续的 RUN 指令在 fakeroot 环境中执行
RUN /etc/beagle-wind-vnc/scripts/os-libraries-install.sh
```

**关键点**：`chown -R ubuntu:ubuntu /` 是在第 1 步以 root 用户执行的，不是在 fakeroot 环境中！

### 关系 2：fakeroot 是为了后续构建步骤

fakeroot 的作用是在**后续的构建步骤**中（USER 1000 之后）：

- 允许 ubuntu 用户执行 `sudo apt install`（实际上是 fakeroot）
- 不需要真正的 root 权限
- 简化 Dockerfile 的编写

但 fakeroot **无法撤销**已经执行的 `chown -R ubuntu:ubuntu /`。

## 为什么要执行 chown -R ubuntu:ubuntu / ？

### 设计意图

从注释可以看出设计意图：

```bash
# 将整个文件系统的所有权更改为ubuntu用户（保留root权限）
chown -R -f -h --no-preserve-root ubuntu:ubuntu /
```

**目的**：
1. 让 ubuntu 用户可以读写所有文件
2. 避免权限问题导致的错误
3. 简化后续的构建和运行

### 实际效果

**好处**：
- ✅ ubuntu 用户可以修改任何文件
- ✅ 不需要频繁使用 sudo
- ✅ 简化了 Dockerfile 的编写

**坏处**：
- ❌ 破坏了 Linux 标准的文件权限模型
- ❌ `/var/lib` 下的系统文件不应该属于普通用户
- ❌ 某些程序依赖文件所有者进行安全检查（如 Flatpak）
- ❌ 调试困难，与标准系统行为不一致

## 这是一个设计缺陷

### 问题分析

这个设计有两个主要问题：

#### 问题 1：过于激进

```bash
# 当前做法：改变整个文件系统
chown -R ubuntu:ubuntu /

# 合理做法：只改变必要的目录
chown -R ubuntu:ubuntu /home/ubuntu /tmp /var/tmp /opt /usr/local
```

#### 问题 2：与 rootless 设计理念冲突

- **Rootless 容器的目标**：以普通用户运行，降低安全风险
- **这个做法**：让普通用户拥有整个文件系统，实际上给了"伪 root"权限
- **矛盾**：形式上是 rootless，实质上权限很大

### 类比说明

这就像：

```
目标：让员工在办公室工作，但不给管理员权限
做法：把整个办公楼的钥匙都给员工

结果：员工可以进入任何房间，包括机房、财务室
      虽然名义上不是管理员，但实际上权限很大
```

## 如何优化？

### 推荐方案：精确控制所有权

修改 `scripts/base/base-system-setup.sh`：

```bash
# 不要执行 chown -R ubuntu:ubuntu /
# 改为只对必要的目录执行 chown

# 用户目录
chown -R ubuntu:ubuntu /home/ubuntu

# 临时目录
chown -R ubuntu:ubuntu /tmp /var/tmp

# 应用程序目录
chown -R ubuntu:ubuntu /opt /usr/local

# 运行时目录（如果需要）
mkdir -p /run/user/1000
chown -R ubuntu:ubuntu /run/user/1000
```

### 需要保持 root 所有者的目录

以下目录应该保持 `root:root` 所有者：

```bash
/var/lib/apt       # APT 包管理器数据
/var/lib/dpkg      # DPKG 包管理器数据
/var/lib/systemd   # Systemd 数据
/usr/bin           # 系统二进制文件
/usr/sbin          # 系统管理工具
/usr/lib           # 系统库文件
/etc               # 系统配置文件
```

### 实施步骤

1. **修改 `scripts/base/base-system-setup.sh`**：

```bash
# =============================================================================
# 设置文件系统所有权
# =============================================================================
# 只对必要的目录更改所有权为ubuntu用户
chown -R -f ubuntu:ubuntu /home/ubuntu || echo 'Failed to set /home/ubuntu ownership'
chown -R -f ubuntu:ubuntu /tmp || echo 'Failed to set /tmp ownership'
chown -R -f ubuntu:ubuntu /var/tmp || echo 'Failed to set /var/tmp ownership'
chown -R -f ubuntu:ubuntu /opt || echo 'Failed to set /opt ownership'
chown -R -f ubuntu:ubuntu /usr/local || echo 'Failed to set /usr/local ownership'

# 创建并设置运行时目录
mkdir -p /run/user/1000
chown -R -f ubuntu:ubuntu /run/user/1000 || echo 'Failed to set /run/user/1000 ownership'
```

2. **测试所有功能**：

```bash
# 构建镜像
docker build -f .beagle/nvidia-egl-base.Dockerfile -t test-base .

# 启动容器
docker run -it --rm test-base bash

# 测试关键功能
- 桌面环境能否启动
- 应用程序能否安装
- 用户文件能否读写
- Flatpak 能否正常工作
```

3. **检查权限**：

```bash
# 在容器中执行
ls -la /var/lib/apt     # 应该是 root:root
ls -la /usr/bin/bwrap   # 应该是 root:root
ls -la /home/ubuntu     # 应该是 ubuntu:ubuntu
ls -la /opt             # 应该是 ubuntu:ubuntu
```

## 为什么之前没有发现这个问题？

### 原因 1：大多数程序不检查文件所有者

大多数程序只检查文件权限（rwx），不检查所有者：

```bash
# 这些程序不关心所有者是谁
apt install package     # 只要能读写 /var/lib/apt
systemctl start service # 只要能访问 /var/lib/systemd
```

### 原因 2：Flatpak 是特例

Flatpak 的 bwrap 工具是少数会检查文件所有者的程序：

```c
// bwrap 源码中的检查
if (stat("/usr/bin/bwrap", &st) == 0) {
    if (st.st_uid != 0) {  // 必须是 root 所有者
        error("bwrap must be owned by root");
    }
}
```

### 原因 3：容器环境的特殊性

在容器中，很多系统服务不运行：

- 没有 systemd
- 没有 cron
- 没有 syslog

所以很多依赖标准权限的功能不会被触发。

## 总结

### 问题本质

`/var/lib` 下文件被改成 ubuntu 用户，**不是 fakeroot 导致的**，而是：

1. **直接原因**：`chown -R ubuntu:ubuntu /` 这行命令
2. **执行时机**：在 Dockerfile 构建时以 root 用户执行
3. **设计缺陷**：过于激进，改变了整个文件系统

### fakeroot 的角色

- **fakeroot 不是问题的原因**
- **fakeroot 是后续构建步骤的工具**
- **fakeroot 无法撤销已经执行的 chown**

### 解决方案

**推荐**：精确控制所有权，只 chown 必要的目录

```bash
# 不要
chown -R ubuntu:ubuntu /

# 应该
chown -R ubuntu:ubuntu /home/ubuntu /tmp /var/tmp /opt /usr/local
```

**效果**：
- ✅ 保持标准的 Linux 文件权限模型
- ✅ Flatpak 等工具可以正常工作
- ✅ 仍然保持 rootless 容器的安全优势
- ✅ ubuntu 用户仍然可以在必要的目录工作

### 行动建议

1. **立即**：在文档中说明这个问题
2. **短期**：修改 `base-system-setup.sh`，精确控制所有权
3. **中期**：充分测试，确保所有功能正常
4. **长期**：重新评估 rootless 设计的实现方式

## 相关文档

- [fakeroot 深入分析](./fakeroot.md)
- [Flatpak bwrap 权限问题](./flatpak-bwrap-permission-issue.md)
