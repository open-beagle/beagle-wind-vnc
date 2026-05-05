# Beagle Wind Desktop (VNC)

Beagle Wind 是一款基于 WebRTC、GStreamer 1.28 以及硬件加速 (NVENC) 的超低延迟云桌面推流系统。它能够通过浏览器为您提供原生主机般的流畅桌面体验。

## 🏛 核心架构分支介绍

为了满足不同的业务场景，Beagle Wind 提供了三种底层显示服务器与渲染架构，您可根据应用场景选择不同的镜像版本：

### 1. EGL 架构 (通用云桌面/高密度多开)
- **底层技术**：`Xvfb` (虚拟帧缓冲) + `VirtualGL` (EGL 硬件加速注入)
- **屏幕采集**：`ximagesrc` (共享内存采集)
- **适用场景**：日常办公、标准云桌面、需要在单台宿主机上**同时运行多个**桌面实例（高密度部署）。
- **优势**：兼容性极佳，不依赖物理显示器输出，不受 NVIDIA NVFBC 授权限制。

### 2. GLX 架构 (云游戏/高性能渲染)
- **底层技术**：真实 `Xorg` 服务器 + GPU 直连输出
- **屏幕采集**：`nvfbcsrc` (NVIDIA 零拷贝帧缓冲捕获)
- **适用场景**：大型 3D 云游戏、高帧率要求的专业渲染环境。
- **优势**：延迟极低，画面捕获完全在 GPU 显存内流转（Zero-Copy），性能损耗降至极限。

### 3. Hyprland 架构 (下一代/开发中 🚧)
- **底层技术**：纯正 `Wayland` 生态
- **适用场景**：追求极致现代化、极简主义与纯净渲染链路的高级玩家。
- **优势**：彻底摒弃历史包袱沉重的 X11 协议，带来丝滑的平铺窗口管理体验及更高的安全与性能上限。

---

## 🚀 快速开始

以下是一个标准的 **EGL 架构** 启动模板。此模板使用 Docker 桥接模式（Bridge），确保在一台机器上运行多个容器时不会发生端口冲突。

```bash
docker run -d \
  --name vnc-desktop-1 \
  --hostname beagle-desktop \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt no-new-privileges=false \
  --cap-add=SYS_RAWIO \
  --shm-size=4g \
  --device /dev/uinput:/dev/uinput \
  --device nvidia.com/gpu=0 \
  -v /data/my-desktop:/home/beagle \
  -e BDWIND_PASSWORD=YourSecretPassword123 \
  -e BDWIND_UDP_PORT_MIN=59010 \
  -e BDWIND_UDP_PORT_MAX=59019 \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -e VGL_DISPLAY=/dev/dri/card0 \
  -p 48080:8080 \
  -p 59010-59019:59010-59019/udp \
  registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:1.0.14
```

> **访问方式**：容器启动后，在浏览器中打开 `http://<您的服务器IP>:48080`，输入 `BDWIND_PASSWORD` 的密码即可登入桌面！

---

## ⚙️ 核心环境变量 (BDWIND_*)

您可以通过在 `docker run` 中传递 `-e` 环境变量来高度定制您的云桌面系统：

### 基础设置
| 参数 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `BDWIND_PASSWORD` | WebUI 登录密码及 Basic Auth 验证密码 | *必填* |
| `BDWIND_ENABLE_RESIZE` | 是否允许前端网页拉伸调整后端云桌面分辨率 | `true` |
| `BDWIND_ENABLE_DEBUG` | 开启详细的 GStreamer 和 WebRTC 调试日志 | `false` |

### 编码与推流
| 参数 | 说明 | 默认值 |
| :--- | :--- | :--- |
| `BDWIND_ENCODER` | 视频硬编码器 (`nvh265enc`, `nvh264enc`, `vp9enc`) | `nvh264enc` |
| `BDWIND_FRAMERATE` | 目标推流帧率 (建议 `60` 或 `120`) | `60` |
| `BDWIND_VIDEO_BITRATE` | 视频最大码率 (kbps) | `10000` |
| `BDWIND_AUDIO_BITRATE` | 音频码率 (bps) | `24000` |

### 网络与 WebRTC (重要)
如果您的客户端与服务器位于不同的网络环境（如外网访问内网），合理的 WebRTC 设置至关重要：

| 参数 | 说明 |
| :--- | :--- |
| `BDWIND_ICE_IP` | 强制指定云桌面的公网出口 IP（当 P2P 打洞失败时，强制客户端向此 IP 发起连接）。 |
| `BDWIND_UDP_PORT_MIN`<br>`BDWIND_UDP_PORT_MAX` | 限制 WebRTC 建立连接时使用的 UDP 端口范围。**强烈建议**在 Bridge 网络下手动指定，并通过 `docker -p` 将此段 UDP 端口映射到宿主机。 |
| `BDWIND_TURN_HOST` | 中继服务器 (STUN/TURN) 地址。例如 `stun.ali.wodcloud.com`。 |
| `BDWIND_TURN_PORT` | 中继服务器端口，默认 `3478`。 |
| `BDWIND_TURN_PROTOCOL` | `udp` 或 `tcp`。 |
| `BDWIND_TURN_SHARED_SECRET`| TURN 服务器的共享密钥（用于生成长效凭证）。 |

---

## 🛠️ 网络部署模式指南

Beagle Wind 提供了极大的灵活性，您可以根据宿主机条件选择两种网络映射模式：

1. **Host 模式 (`--network host`)**
   - **配置**：移除所有的 `-p` 映射，直接在 docker run 追加 `--network host`。
   - **优点**：配置极简，WebRTC 原生穿透率高，无需规划 UDP 端口。
   - **缺点**：容器内的所有服务（包括 `Xvfb`、`Nginx` 等）都会直接监听宿主机端口。**如果单台宿主机要跑多个实例，绝对会发生端口冲突（例如报错 X server already running）**。
   - **适用**：每台云服务器/节点**只跑唯一一个**桌面实例时使用（如 `selkies-game`）。

2. **Bridge 桥接模式 (推荐)**
   - **配置**：如上方的【快速开始】示例，使用 `-p` 分别映射 Nginx 管理端口（8080）和指定的 UDP 音视频传输范围（如 59010-59019）。
   - **优点**：网络完全隔离，支持在同一台机器上高密度部署 N 个云桌面环境，互不干扰。
   - **缺点**：必须为每个实例精心规划对应的 `BDWIND_UDP_PORT_MIN/MAX` 并对外暴露。

