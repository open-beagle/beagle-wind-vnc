# Beagle Desktop 透明代理方案

这个方案为Beagle Desktop容器提供了完全透明的科学上网功能，所有网络流量都会自动通过XRay代理，无需手动配置任何应用程序。

## 🎯 方案特点

### 核心优势
- **完全透明**: 所有TCP/UDP流量自动走代理
- **智能分流**: 国内直连，国外走代理
- **无需配置**: 应用程序无需设置代理
- **DNS优化**: 自动使用公共DNS服务器
- **容器化**: 完全在容器内实现，不影响主机

### 技术实现
- **TPROXY**: 使用Linux TPROXY技术实现透明代理
- **iptables**: 通过iptables规则重定向流量
- **路由表**: 自定义路由表处理标记流量
- **XRay**: 使用dokodemo-door协议接收透明代理流量

## 🏗️ 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    Desktop Pod                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐    ┌─────────────────┐                │
│  │   Desktop       │    │   XRay          │                │
│  │   Container     │◄──►│   Transparent   │                │
│  │                 │    │   Proxy         │                │
│  │  - KDE Plasma   │    │                 │                │
│  │  - VNC Server   │    │  - TPROXY       │                │
│  │  - WebRTC       │    │  - iptables     │                │
│  │  - 所有应用     │    │  - 路由规则     │                │
│  └─────────────────┘    └─────────────────┘                │
└─────────────────────────────────────────────────────────────┘
```

## 📋 部署步骤

### 1. 配置XRay服务器信息

编辑 `k8s/desktop-transparent-proxy.yaml` 中的XRay配置：

```yaml
# 修改以下字段为你的实际配置
"address": "your-vmess-server.com",  # 你的VMess服务器地址
"port": 443,                        # 服务器端口
"id": "your-uuid-here",            # 用户UUID
"path": "/path",                   # WebSocket路径
```

### 2. 部署到Kubernetes

```bash
# 创建命名空间
kubectl create namespace beagle-desktop

# 部署透明代理配置
kubectl apply -f k8s/desktop-transparent-proxy.yaml -n beagle-desktop

# 检查部署状态
kubectl get pods -n beagle-desktop
kubectl get svc -n beagle-desktop
```

### 3. 验证透明代理

```bash
# 进入Desktop容器
kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- bash

# 测试透明代理
curl -I https://www.google.com
curl -I https://www.youtube.com
nslookup google.com

# 检查iptables规则
iptables -t nat -L XRAY_TCP -n
iptables -t mangle -L XRAY_TCP -n
iptables -t mangle -L XRAY_UDP -n
```

## 🔧 工作原理

### 1. 流量重定向

```bash
# TCP流量重定向
iptables -t nat -A XRAY_TCP -p tcp -j REDIRECT --to-ports 12345

# UDP流量TPROXY
iptables -t mangle -A XRAY_UDP -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
```

### 2. 路由规则

```bash
# 创建自定义路由表
echo "200 xray" >> /etc/iproute2/rt_tables

# 添加路由规则
ip rule add fwmark 1 table xray
ip route add local 0.0.0.0/0 dev lo table xray
```

### 3. XRay配置

```json
{
  "inbounds": [
    {
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    }
  ]
}
```

## 🛡️ 安全考虑

### 网络隔离
- 代理仅在容器内部可用
- 通过Cilium网络策略控制访问
- 支持TLS加密传输

### 权限控制
```yaml
securityContext:
  capabilities:
    add:
    - NET_ADMIN    # 网络管理权限
    - NET_RAW      # 原始套接字权限
```

### 资源限制
```yaml
resources:
  requests:
    memory: "64Mi"
    cpu: "50m"
  limits:
    memory: "128Mi"
    cpu: "100m"
```

## 🔍 故障排查

### 常见问题

1. **透明代理不工作**
   ```bash
   # 检查XRay是否启动
   kubectl logs deployment/beagle-desktop-transparent -c xray -n beagle-desktop
   
   # 检查iptables规则
   kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- iptables -t nat -L XRAY_TCP -n
   ```

2. **DNS解析失败**
   ```bash
   # 检查DNS配置
   kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- cat /etc/resolv.conf
   
   # 测试DNS解析
   kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- nslookup google.com
   ```

3. **网络连接问题**
   ```bash
   # 检查网络连通性
   kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- curl -I https://www.google.com
   
   # 检查路由表
   kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- ip rule show
   ```

### 清理脚本

如果遇到问题需要清理：

```bash
# 进入容器执行清理
kubectl exec -it deployment/beagle-desktop-transparent -c desktop -n beagle-desktop -- /tmp/cleanup-transparent-proxy.sh
```

## 📊 性能优化

### 1. 连接池优化
```json
{
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "your-server.com",
            "port": 443,
            "users": [
              {
                "id": "your-uuid",
                "alterId": 0,
                "security": "auto"
              }
            ]
          }
        ]
      }
    }
  ]
}
```

### 2. 路由优化
- 国内网站直连
- 国外网站走代理
- 私有网络直连

### 3. DNS优化
- 使用公共DNS服务器
- 启用DNS缓存
- 避免DNS污染

## 🎉 使用效果

部署完成后，你将获得：

1. **完全透明的网络访问**: 所有应用无需配置代理
2. **智能分流**: 国内网站直连，国外网站走代理
3. **高性能**: 基于XRay的高性能代理
4. **稳定性**: 容器化部署，易于管理和维护
5. **安全性**: 网络隔离和权限控制

这个透明代理方案让你的Desktop容器拥有了完整的科学上网能力，同时保持了简单易用的特点！ 