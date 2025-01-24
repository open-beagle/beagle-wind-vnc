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
# https://github.com/selkies-project/docker-nvidia-egl-desktop/pkgs/container/nvidia-egl-desktop
docker pull ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241222100454 && \
docker tag ghcr.io/selkies-project/nvidia-egl-desktop:24.04-20241222100454 registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop24.04-20241222100454 && \
docker push registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:nvidia-egl-desktop24.04-20241222100454
```
