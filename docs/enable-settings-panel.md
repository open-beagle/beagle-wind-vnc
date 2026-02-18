# 如何启用 Web 界面设置面板

## 概述

Web 界面右侧的设置面板（视频码率、视频帧率、音频码率、自动调整分辨率等）默认处于禁用状态。这是一个设计特性，用于防止用户在不了解参数含义的情况下误操作导致性能问题。

## 为什么默认禁用？

设置面板中的参数直接影响视频流的质量和性能：

- **视频码率**：过高会占用大量带宽，过低会导致画质模糊
- **视频帧率**：过高会增加 CPU/GPU 负载，过低会导致画面卡顿
- **音频码率**：影响音频质量和带宽占用
- **自动调整分辨率**：可能导致频繁的分辨率切换

为了避免新手用户误操作，默认情况下这些设置被禁用，使用预设的推荐值。

## 如何启用设置面板

### 方法：设置环境变量

在启动容器时添加环境变量 `BEAGLE_ENABLE_DEBUG=true`：

```bash
docker run -d \
  --name vnc-desktop \
  # ... 其他参数 ...
  -e BEAGLE_ENABLE_DEBUG=true \
  # ... 其他环境变量 ...
  registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop-1.0.9
```

### 完整启动命令示例

```bash
docker run -d \
  --name vnc-desktop \
  --hostname my-desktop \
  --gpus '"device=0"' \
  --privileged \
  --security-opt seccomp=unconfined \
  --security-opt no-new-privileges=false \
  --cap-add=SYS_RAWIO \
  --tmpfs /dev/shm:rw,size=2g \
  --device /dev/dri \
  --group-add $(getent group render | cut -d: -f3) \
  --restart always \
  -v /dev/input:/dev/input \
  -v /data/nvidia:/data/nvidia \
  -v /data/vnc/home:/home/ubuntu \
  -v /data/vnc/flatpak:/var/lib/flatpak \
  -e TZ="Asia/Shanghai" \
  -e DISPLAY_SIZEW=1920 \
  -e DISPLAY_SIZEH=1080 \
  -e DISPLAY_REFRESH=60 \
  -e DISPLAY_DPI=96 \
  -e DISPLAY_CDEPTH=24 \
  -e PASSWD=mypassword \
  -e SELKIES_ENCODER=nvh264enc \
  -e SELKIES_VIDEO_BITRATE=4000 \
  -e SELKIES_FRAMERATE=60 \
  -e SELKIES_AUDIO_BITRATE=24000 \
  -e SELKIES_ENABLE_RESIZE=true \
  -e SELKIES_BASIC_AUTH_PASSWORD=mypassword \
  -e SELKIES_ENABLE_HTTPS="false" \
  -e SELKIES_TURN_HOST=stun.example.com \
  -e SELKIES_TURN_PORT=3478 \
  -e SELKIES_TURN_PROTOCOL=udp \
  -e SELKIES_TURN_USERNAME=username \
  -e SELKIES_TURN_PASSWORD=password \
  -e BEAGLE_ENABLE_DEBUG=true \
  -p 48080:8080 \
  registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop-1.0.9
```

**关键配置**：`-e BEAGLE_ENABLE_DEBUG=true`

## 验证设置面板已启用

1. 启动容器后，在浏览器中访问 Web 界面（如 `http://your-server:48080`）
2. 点击右侧的设置按钮（齿轮图标）
3. 检查以下设置项是否可以点击和修改：
   - 视频 码率
   - 视频 帧率
   - 音频 码率
   - 自动调整分辨率
4. 如果这些选项可以修改，说明设置面板已成功启用

## 推荐的参数设置

启用设置面板后，你可以根据实际情况调整参数：

### 高质量场景（本地网络或高带宽）

- **视频码率**：8000-12000 kbps
- **视频帧率**：60 fps
- **音频码率**：48000 bps
- **自动调整分辨率**：关闭

### 平衡场景（一般网络）

- **视频码率**：4000-6000 kbps
- **视频帧率**：30-60 fps
- **音频码率**：24000 bps
- **自动调整分辨率**：开启

### 低带宽场景（移动网络或远程访问）

- **视频码率**：2000-3000 kbps
- **视频帧率**：30 fps
- **音频码率**：16000 bps
- **自动调整分辨率**：开启

## 通过环境变量预设参数

你也可以在启动容器时通过环境变量预设这些参数，而不需要在 Web 界面中手动调整：

```bash
-e SELKIES_VIDEO_BITRATE=4000      # 视频码率（kbps）
-e SELKIES_FRAMERATE=60            # 视频帧率
-e SELKIES_AUDIO_BITRATE=24000     # 音频码率（bps）
-e SELKIES_ENABLE_RESIZE=true      # 自动调整分辨率
```

## 相关环境变量说明

| 环境变量                | 默认值  | 说明             | 推荐值                    |
| ----------------------- | ------- | ---------------- | ------------------------- |
| `BEAGLE_ENABLE_DEBUG`   | `false` | 启用设置面板     | `true`（如需调整参数）    |
| `SELKIES_VIDEO_BITRATE` | -       | 视频码率（kbps） | 4000-8000                 |
| `SELKIES_FRAMERATE`     | -       | 视频帧率         | 30-60                     |
| `SELKIES_AUDIO_BITRATE` | -       | 音频码率（bps）  | 16000-48000               |
| `SELKIES_ENABLE_RESIZE` | `false` | 自动调整分辨率   | `true`（响应式）          |
| `SELKIES_ENCODER`       | -       | 视频编码器       | `nvh264enc`（NVIDIA GPU） |

## 注意事项

1. **性能影响**：调整参数可能会影响系统性能，建议根据实际硬件配置和网络状况调整
2. **带宽占用**：高码率和高帧率会显著增加网络带宽占用
3. **GPU 负载**：使用硬件编码器（如 `nvh264enc`）可以降低 CPU 负载，但需要 NVIDIA GPU 支持
4. **实时调整**：在 Web 界面中调整的参数会立即生效，无需重启容器

## 故障排查

### 设置面板仍然禁用

如果添加了 `BEAGLE_ENABLE_DEBUG=true` 后设置面板仍然禁用：

1. **检查环境变量是否生效**：

```bash
docker exec vnc-desktop env | grep BEAGLE_ENABLE_DEBUG
```

应该输出：`BEAGLE_ENABLE_DEBUG=true`

2. **查看后端日志**：

```bash
docker logs vnc-desktop | grep debug_enabled
```

3. **检查 WebSocket 消息**：

在浏览器开发者工具（F12）的 Network 标签中：

- 找到 WebSocket 连接
- 查看 Messages
- 搜索 `debug_enabled` 消息，确认值为 `true`

4. **检查前端状态**：

在浏览器开发者工具 Console 中执行：

```javascript
console.log("disabled:", app.disabled);
```

应该输出：`disabled: false`

### 重启现有容器

如果你已经有一个运行中的容器，需要重新创建才能应用新的环境变量：

```bash
# 停止并删除现有容器
docker stop vnc-desktop
docker rm vnc-desktop

# 使用新的环境变量重新创建容器
docker run -d \
  --name vnc-desktop \
  # ... 添加 -e BEAGLE_ENABLE_DEBUG=true ...
```

## 技术说明

### 实现原理

设置面板的启用/禁用状态由以下机制控制：

1. **后端**：`src/selkies_gstreamer/__main__.py` 读取环境变量 `BEAGLE_ENABLE_DEBUG`
2. **WebSocket**：后端通过 WebSocket 发送 `debug_enabled` 消息给前端
3. **前端**：`addons/gstreamer-web/src/app.js` 接收消息并设置 `disabled` 变量
4. **UI**：Vue.js 根据 `disabled` 变量控制设置项的启用/禁用状态

### 为什么叫 DEBUG？

这个功能最初是为了调试目的设计的，允许开发者在运行时调整参数。后来保留了这个功能，让高级用户也能根据需要调整参数。

## 相关文档

- [环境变量完整列表](./environment-variables.md)（如果有）
- [性能优化指南](./performance-tuning.md)（如果有）
- [故障排查指南](./troubleshooting.md)（如果有）
