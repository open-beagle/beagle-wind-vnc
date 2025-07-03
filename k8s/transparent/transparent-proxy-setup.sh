#!/bin/bash

# 透明代理设置脚本
# 配置iptables规则实现透明代理

set -e

echo "Setting up transparent proxy..."

# 等待XRay启动
echo "Waiting for XRay to be ready..."
until nc -z localhost 12345; do
  echo "Waiting for XRay transparent proxy on port 12345..."
  sleep 2
done

echo "XRay is ready!"

# 创建新的iptables链
iptables -t nat -N XRAY_TCP 2>/dev/null || true
iptables -t mangle -N XRAY_TCP 2>/dev/null || true
iptables -t mangle -N XRAY_UDP 2>/dev/null || true

# 清空现有规则
iptables -t nat -F XRAY_TCP
iptables -t mangle -F XRAY_TCP
iptables -t mangle -F XRAY_UDP

# 设置TCP透明代理规则
echo "Setting up TCP transparent proxy rules..."

# 跳过本地地址
iptables -t nat -A XRAY_TCP -d 0.0.0.0/8 -j RETURN
iptables -t nat -A XRAY_TCP -d 10.0.0.0/8 -j RETURN
iptables -t nat -A XRAY_TCP -d 127.0.0.0/8 -j RETURN
iptables -t nat -A XRAY_TCP -d 169.254.0.0/16 -j RETURN
iptables -t nat -A XRAY_TCP -d 172.16.0.0/12 -j RETURN
iptables -t nat -A XRAY_TCP -d 192.168.0.0/16 -j RETURN
iptables -t nat -A XRAY_TCP -d 224.0.0.0/4 -j RETURN
iptables -t nat -A XRAY_TCP -d 240.0.0.0/4 -j RETURN

# 跳过XRay代理端口
iptables -t nat -A XRAY_TCP -p tcp --dport 12345 -j RETURN
iptables -t nat -A XRAY_TCP -p tcp --dport 1080 -j RETURN
iptables -t nat -A XRAY_TCP -p tcp --dport 8080 -j RETURN

# 重定向TCP流量到XRay
iptables -t nat -A XRAY_TCP -p tcp -j REDIRECT --to-ports 12345

# 设置mangle表规则（用于TPROXY）
echo "Setting up mangle table rules..."

# 跳过本地地址
iptables -t mangle -A XRAY_TCP -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_TCP -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_TCP -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_TCP -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY_TCP -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY_TCP -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A XRAY_TCP -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_TCP -d 240.0.0.0/4 -j RETURN

# 跳过XRay代理端口
iptables -t mangle -A XRAY_TCP -p tcp --dport 12345 -j RETURN
iptables -t mangle -A XRAY_TCP -p tcp --dport 1080 -j RETURN
iptables -t mangle -A XRAY_TCP -p tcp --dport 8080 -j RETURN

# 标记TCP流量
iptables -t mangle -A XRAY_TCP -p tcp -j TPROXY --on-port 12345 --tproxy-mark 1

# 设置UDP透明代理规则
echo "Setting up UDP transparent proxy rules..."

# 跳过本地地址
iptables -t mangle -A XRAY_UDP -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_UDP -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_UDP -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A XRAY_UDP -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A XRAY_UDP -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A XRAY_UDP -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A XRAY_UDP -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A XRAY_UDP -d 240.0.0.0/4 -j RETURN

# 跳过XRay代理端口
iptables -t mangle -A XRAY_UDP -p udp --dport 12345 -j RETURN
iptables -t mangle -A XRAY_UDP -p udp --dport 1080 -j RETURN
iptables -t mangle -A XRAY_UDP -p udp --dport 8080 -j RETURN

# 标记UDP流量
iptables -t mangle -A XRAY_UDP -p udp -j TPROXY --on-port 12345 --tproxy-mark 1

# 将链添加到PREROUTING
iptables -t nat -A PREROUTING -p tcp -j XRAY_TCP
iptables -t mangle -A PREROUTING -p tcp -j XRAY_TCP
iptables -t mangle -A PREROUTING -p udp -j XRAY_UDP

# 设置路由规则
echo "Setting up routing rules..."

# 创建路由表
echo "200 xray" >> /etc/iproute2/rt_tables 2>/dev/null || true

# 添加路由规则
ip rule add fwmark 1 table xray 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table xray 2>/dev/null || true

# 配置DNS
echo "Configuring DNS..."

# 备份原始DNS配置
cp /etc/resolv.conf /etc/resolv.conf.backup

# 设置DNS服务器（使用公共DNS）
cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

# 测试透明代理
echo "Testing transparent proxy..."

# 测试TCP连接
if curl -s -o /dev/null -w "%{http_code}" https://www.google.com | grep -q "200"; then
  echo "✅ TCP transparent proxy is working!"
else
  echo "⚠️  TCP transparent proxy test failed"
fi

# 测试DNS解析
if nslookup google.com >/dev/null 2>&1; then
  echo "✅ DNS resolution is working!"
else
  echo "⚠️  DNS resolution test failed"
fi

echo "Transparent proxy setup completed!"

# 创建清理脚本
cat > /tmp/cleanup-transparent-proxy.sh << 'EOF'
#!/bin/bash
echo "Cleaning up transparent proxy rules..."

# 删除iptables规则
iptables -t nat -D PREROUTING -p tcp -j XRAY_TCP 2>/dev/null || true
iptables -t mangle -D PREROUTING -p tcp -j XRAY_TCP 2>/dev/null || true
iptables -t mangle -D PREROUTING -p udp -j XRAY_UDP 2>/dev/null || true

# 删除链
iptables -t nat -F XRAY_TCP 2>/dev/null || true
iptables -t nat -X XRAY_TCP 2>/dev/null || true
iptables -t mangle -F XRAY_TCP 2>/dev/null || true
iptables -t mangle -X XRAY_TCP 2>/dev/null || true
iptables -t mangle -F XRAY_UDP 2>/dev/null || true
iptables -t mangle -X XRAY_UDP 2>/dev/null || true

# 删除路由规则
ip rule del fwmark 1 table xray 2>/dev/null || true
ip route del local 0.0.0.0/0 dev lo table xray 2>/dev/null || true

# 恢复DNS配置
if [ -f /etc/resolv.conf.backup ]; then
  cp /etc/resolv.conf.backup /etc/resolv.conf
fi

echo "Cleanup completed!"
EOF

chmod +x /tmp/cleanup-transparent-proxy.sh 