#!/bin/bash

# 代理设置脚本
# 用于在Desktop容器启动时配置代理环境

set -e

echo "Setting up proxy environment..."

# 等待XRay sidecar启动
echo "Waiting for XRay sidecar to be ready..."
until nc -z localhost 8080; do
  echo "Waiting for HTTP proxy on port 8080..."
  sleep 2
done

until nc -z localhost 1080; do
  echo "Waiting for SOCKS5 proxy on port 1080..."
  sleep 2
done

echo "XRay sidecar is ready!"

# 设置系统级代理
export http_proxy="http://localhost:8080"
export https_proxy="http://localhost:8080"
export HTTP_PROXY="http://localhost:8080"
export HTTPS_PROXY="http://localhost:8080"
export no_proxy="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"

# 配置apt代理
if [ ! -f /etc/apt/apt.conf.d/99proxy ]; then
  cat > /etc/apt/apt.conf.d/99proxy << EOF
Acquire::http::Proxy "http://localhost:8080";
Acquire::https::Proxy "http://localhost:8080";
EOF
fi

# 配置git代理
git config --global http.proxy http://localhost:8080
git config --global https.proxy http://localhost:8080

# 配置wget代理
if [ ! -f ~/.wgetrc ]; then
  cat > ~/.wgetrc << EOF
http_proxy=http://localhost:8080
https_proxy=http://localhost:8080
EOF
fi

# 配置curl代理
if [ ! -f ~/.curlrc ]; then
  cat > ~/.curlrc << EOF
proxy=localhost:8080
EOF
fi

# 配置pip代理
mkdir -p ~/.pip
if [ ! -f ~/.pip/pip.conf ]; then
  cat > ~/.pip/pip.conf << EOF
[global]
proxy = http://localhost:8080
https_proxy = http://localhost:8080
EOF
fi

# 配置npm代理
npm config set proxy http://localhost:8080
npm config set https-proxy http://localhost:8080

# 配置环境变量到shell配置文件
cat >> ~/.bashrc << EOF

# Proxy settings
export http_proxy="http://localhost:8080"
export https_proxy="http://localhost:8080"
export HTTP_PROXY="http://localhost:8080"
export HTTPS_PROXY="http://localhost:8080"
export no_proxy="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
EOF

# 测试代理连接
echo "Testing proxy connection..."
if curl -x http://localhost:8080 -s -o /dev/null -w "%{http_code}" https://www.google.com | grep -q "200"; then
  echo "✅ Proxy is working correctly!"
else
  echo "⚠️  Proxy test failed, but continuing..."
fi

echo "Proxy setup completed!" 