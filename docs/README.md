# 文档索引

欢迎查阅 beagle-wind-vnc 项目文档。

## 📋 更新日志

- **[CHANGELOG.md](./CHANGELOG.md)** - 项目更新日志，记录所有重要变更

## 🚀 快速开始

- **[启用 Web 界面设置面板](./enable-settings-panel.md)** - 如何启用和使用 Web 界面的设置功能

## 🔧 问题解决

### 常见问题

- **[Flatpak bwrap 权限问题](./flatpak-bwrap-permission-issue.md)** - Flatpak 安装和使用指南

### 已修复问题

- **[文件系统所有权问题分析](./filesystem-ownership-issue.md)** - 问题根因分析（✅ 已修复）
- **[文件系统所有权修复说明](./CHANGELOG-ownership-fix.md)** - 详细修复说明
- **[Bug 追踪：按回车键导致页面闪烁](./bug-enter-key-flicker.md)** - Bug 分析和修复（✅ 已修复）

## 📚 技术文档

### 架构设计

- **[fakeroot 深入分析](./fakeroot.md)** - rootless 容器设计理念、fakeroot 工作原理、安全性分析

## 📖 按主题浏览

### 安全性

- [fakeroot 深入分析](./fakeroot.md) - rootless 容器安全设计
- [文件系统所有权问题](./filesystem-ownership-issue.md) - 权限模型分析

### Web 界面

- [启用设置面板](./enable-settings-panel.md) - 设置面板使用指南
- [回车键闪烁问题](./bug-enter-key-flicker.md) - Bug 分析和修复（✅ 已修复）

### 应用支持

- [Flatpak 使用指南](./flatpak-bwrap-permission-issue.md) - Flatpak 安装和配置

## 🔍 按角色浏览

### 普通用户

1. [启用 Web 界面设置面板](./enable-settings-panel.md) - 了解如何调整视频质量等参数
2. [Flatpak 使用指南](./flatpak-bwrap-permission-issue.md) - 如果需要使用 Flatpak 安装应用

### 系统管理员

1. [CHANGELOG](./CHANGELOG.md) - 了解最新变更
2. [文件系统所有权修复说明](./CHANGELOG-ownership-fix.md) - 了解权限模型变更
3. [fakeroot 深入分析](./fakeroot.md) - 了解安全设计

### 开发者

1. [fakeroot 深入分析](./fakeroot.md) - 理解 rootless 容器实现
2. [文件系统所有权问题分析](./filesystem-ownership-issue.md) - 理解设计权衡
3. [Bug 追踪文档](./bug-enter-key-flicker.md) - 了解已知问题和修复计划

## 🆘 获取帮助

### 遇到问题？

1. **查看文档**：先查看相关文档，大多数问题都有解决方案
2. **检查权限**：`ls -ld /var/lib/apt /usr/bin /home/ubuntu` 检查文件权限
3. **查看日志**：`docker logs <container_name>` 查看容器日志
4. **提交 Issue**：如果问题未解决，请提交 GitHub Issue

### 提交 Issue 时请包含

- 问题描述和复现步骤
- 容器启动命令
- 相关文件权限信息（如果相关）
- 容器日志（如果相关）
- 镜像版本

## 📝 贡献文档

欢迎贡献文档！请：

1. Fork 项目
2. 在 `docs/` 目录下创建或修改文档
3. 更新本索引文件
4. 提交 Pull Request

### 文档规范

- 使用 Markdown 格式
- 添加清晰的标题和目录
- 包含代码示例
- 添加相关文档的链接

## 📚 外部资源

### Docker 安全

- [Docker Security Best Practices](https://www.betterstack.com/community/guides/scaling-docker/docker-security-best-practices/)
- [Rootless Docker Documentation](https://docs.docker.com/engine/security/rootless/)

### Kubernetes

- [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)

### Linux 权限

- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [fakeroot Manual](https://manpages.debian.org/testing/fakeroot/fakeroot.1.en.html)

## 📞 联系方式

- **GitHub Issues**: https://github.com/open-beagle/beagle-wind-vnc/issues
- **项目主页**: https://github.com/open-beagle/beagle-wind-vnc

---

最后更新：2026-02-18
