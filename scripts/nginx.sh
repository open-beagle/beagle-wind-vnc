#!/bin/bash

# 设置默认端口号
BDWIND_PORT_GSTREAMER=${BDWIND_PORT_GSTREAMER:-8081}

# 循环检查端口是否开放
until nc -z localhost ${BDWIND_PORT_GSTREAMER}; do
  sleep 0.5
done

# 启动 Nginx
/usr/sbin/nginx -g "daemon off;"
