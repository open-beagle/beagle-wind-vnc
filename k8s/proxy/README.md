# Beagle Desktop with XRay Proxy

这个配置为Beagle Desktop容器添加了XRay代理功能，实现科学上网。

## 架构说明

- **Desktop Container**: 运行KDE Plasma桌面环境
- **XRay Sidecar**: 提供HTTP和SOCKS5代理服务
- **Cilium Network**: 提供网络连接和策略

## 部署步骤

### 1. 配置XRay服务器信息

编辑 `k8s/desktop-with-xray.yaml` 中的XRay配置：

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

# 部署配置
kubectl apply -f k8s/desktop-with-xray.yaml -n beagle-desktop

# 部署Ingress（可选）
kubectl apply -f k8s/desktop-ingress.yaml -n beagle-desktop
```

### 3. 验证部署

```bash
# 检查Pod状态
kubectl get pods -n beagle-desktop

# 检查服务状态
kubectl get svc -n beagle-desktop

# 查看Pod日志
kubectl logs -f deployment/beagle-desktop -c desktop -n beagle-desktop
kubectl logs -f deployment/beagle-desktop -c xray -n beagle-desktop
```

## 代理配置

### 自动配置

容器启动时会自动配置以下代理：

- **HTTP代理**: `http://localhost:8080`
- **SOCKS5代理**: `socks5://localhost:1080`
- **环境变量**: 自动设置 `http_proxy`, `https_proxy` 等
- **应用配置**: apt, git, pip, npm等工具的代理配置

### 手动配置

如果需要手动配置代理，可以在Desktop中：

```bash
# 设置环境变量
export http_proxy="http://localhost:8080"
export https_proxy="http://localhost:8080"

# 测试代理
curl -x http://localhost:8080 https://www.google.com
```

## 网络策略

### Cilium网络策略示例

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: desktop-network-policy
  namespace: beagle-desktop
spec:
  endpointSelector:
    matchLabels:
      app: beagle-desktop
  ingress:
  - fromEndpoints:
    - matchLabels:
        k8s:io.kubernetes.pod.namespace: ingress-nginx
    toPorts:
    - ports:
      - port: "8080"
        protocol: TCP
  egress:
  - toEntities:
    - world
  - toEndpoints:
    - matchLabels:
        app: beagle-desktop
```

## 故障排除

### 1. 代理连接问题

```bash
# 检查XRay容器状态
kubectl exec -it deployment/beagle-desktop -c xray -n beagle-desktop -- xray version

# 检查代理端口
kubectl exec -it deployment/beagle-desktop -c desktop -n beagle-desktop -- netstat -tlnp
```

### 2. 网络连接问题

```bash
# 检查Cilium状态
cilium status

# 检查网络策略
kubectl get ciliumnetworkpolicies -n beagle-desktop
```

### 3. 性能优化

- 调整XRay资源配置
- 优化路由规则
- 配置DNS解析

## 安全注意事项

1. **TLS证书**: 确保使用有效的TLS证书
2. **访问控制**: 配置适当的网络策略
3. **日志监控**: 监控代理访问日志
4. **资源限制**: 设置合理的资源限制

## 扩展功能

### 1. 多协议支持

XRay支持多种协议，可以根据需要修改配置：

- VMess
- VLESS
- Trojan
- Shadowsocks

### 2. 负载均衡

可以配置多个出站代理实现负载均衡：

```json
{
  "outbounds": [
    {
      "protocol": "vmess",
      "tag": "proxy1",
      "settings": { ... }
    },
    {
      "protocol": "vmess", 
      "tag": "proxy2",
      "settings": { ... }
    }
  ],
  "routing": {
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "balancerTag": "proxy-balancer"
      }
    ],
    "balancers": [
      {
        "tag": "proxy-balancer",
        "strategy": "random",
        "selector": ["proxy1", "proxy2"]
      }
    ]
  }
}
``` 