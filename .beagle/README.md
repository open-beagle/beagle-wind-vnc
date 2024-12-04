# beagle-wind-vnc

比格 Wind VNC 服务

## gsteamer-web

浏览器端管理控制台

## images

```bash
# nvidia-glx
docker pull ghcr.io/selkies-project/nvidia-glx-desktop:24.04-20241103070505 && \
docker tag ghcr.io/selkies-project/nvidia-glx-desktop:24.04-20241103070505 registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-glx-desktop24.04-20241103070505 && \
docker push registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-glx-desktop24.04-20241103070505

# nvidia-egl
docker pull ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241103070509 && \
docker tag ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241103070509 registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop24.04-20241103070509 && \
docker push registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop24.04-20241103070509
```
