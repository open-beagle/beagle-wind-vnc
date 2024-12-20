# weston

```bash
docker run \
  -it --rm \
  -v $PWD:/go/src/github.com/open-beagle/beagle-wind-vnc \
  -w /go/src/github.com/open-beagle/beagle-wind-vnc \
  -e DEBIAN_FRONTEND=noninteractive \
  -p 3389:3389 \
  registry.cn-qingdao.aliyuncs.com/wod/ubuntu:v24.04-amd64 \
  bash

cp nvidia/weston/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

mkdir -p /home/beagle/.config
cp nvidia/weston/weston.ini /home/beagle/.config/weston.ini
cp nvidia/weston/entrypoint.sh /home/beagle/entrypoint.sh
chown beagle:beagle -R /home/beagle

su beagle

bash /home/beagle/entrypoint.sh

locale-gen en_US.UTF-8

docker run -it --rm \
  -p 3389:3389 \
  registry.cn-qingdao.aliyuncs.com/wod/beagle-wind-vnc:weston
```

## ubuntu

```bash
docker pull ubuntu:24.04 && \
docker tag ubuntu:24.04 registry.cn-qingdao.aliyuncs.com/wod/ubuntu:v24.04-amd64 && \
docker push registry.cn-qingdao.aliyuncs.com/wod/ubuntu:v24.04-amd64
```