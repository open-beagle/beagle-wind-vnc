#!/bin/bash

# 设置默认端口号
SELKIES_PORT=${SELKIES_PORT:-8081}

# 循环检查端口是否开放
until nc -z localhost ${SELKIES_PORT}; do
  sleep 0.5
done

# 启动 Nginx
/usr/sbin/nginx -g "daemon off;"
