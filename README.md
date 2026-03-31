# beagle-wind-vnc

比格 Wind VNC 服务

## 🚀 流水线触发与调试指南

在多线开发过程中，为了避免在主工程目录（`beagle-wind-desktop`）与子模块（`vnc`）之间反复进出 `cd` 切换而打断心流，你可以直接**在主工程根目录下**执行以下专属的连招指令。

这将极速完成“切入发版分支 -> 吸收最新特性 -> 触发远端镜像构建流水线 -> 瞬间切回继续热更开发”的纯享闭环：

```bash
# 极速连招：切换流水线分支 -> 合并代码 -> 推送触发构建 -> 成功后无缝切回 dev 开发分支（带异常阻断，更安全）
# nvidia-glx-app
git -C vnc checkout nvidia-glx-app && \
  git -C vnc merge dev && \
  git -C vnc push origin nvidia-glx-app && \
  git -C vnc checkout dev

# nvidia-gstreamer
git -C vnc checkout nvidia-gstreamer && \
  git -C vnc merge dev && \
  git -C vnc push origin nvidia-gstreamer && \
  git -C vnc checkout dev
```
