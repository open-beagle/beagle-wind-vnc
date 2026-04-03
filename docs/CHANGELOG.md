# 更新日志

## 2026-02-18

### 修复

- **文件系统所有权问题**：只对必要的目录（`/home/ubuntu`, `/opt`, `/usr/local`, `/run/user/1000`）更改所有权为 ubuntu 用户，保持系统目录（`/var/lib`, `/usr/bin`, `/etc` 等）为 root 所有者。解决了 Flatpak 等依赖标准权限的工具无法正常工作的问题。详见 [修复说明](./CHANGELOG-ownership-fix.md)

- **Web 界面回车键闪烁**：在 `handleKeyDown` 方法中添加状态检查，只在显示"开启"按钮时响应回车键，避免误触发导致的视频流中断。详见 [修复说明](./CHANGELOG-enter-key-fix.md)

### 变更的文件

- `scripts/base/base-system-setup.sh`
- `nvidia/egl/Dockerfile`
- `nvidia/glx/Dockerfile`
- `addons/gstreamer-web/src/app.js`
