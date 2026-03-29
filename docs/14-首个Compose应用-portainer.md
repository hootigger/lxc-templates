# 首个 Compose 应用部署手册 — Portainer CE

> 前置条件：`docker-01` 已安装 Docker Engine，Nginx Proxy Manager 已运行（`docs/13`）。  
> Portainer 是 Docker 的 Web 管理界面，是 homelab 中最值得最先部署的应用之一。

---

## 一、为什么先部署 Portainer？

| 理由 | 说明 |
|------|------|
| 可视化容器管理 | 无需 SSH 即可查看容器状态、日志、资源占用 |
| 简化 Compose 操作 | 可在界面中启停、更新 Compose 应用 |
| 排查问题更直观 | 容器日志、环境变量、挂载点一览无余 |
| 零外部依赖 | 不依赖 MySQL / Redis，最适合作为第一个应用 |
| 资源占用极低 | 常驻内存约 30–50 MB |

---

## 二、目录规划

在 `docker-01` 上执行：

```bash
# 创建 Compose 配置目录
mkdir -p /data/compose/portainer

# 创建持久化数据目录
mkdir -p /data/portainer
```

目录说明：

```
/data/
├── compose/
│   └── portainer/
│       └── docker-compose.yml
└── portainer/          # Portainer 数据库（portainer.db）
```

---

## 三、Compose 文件

创建 `/data/compose/portainer/docker-compose.yml`：

```bash
cat > /data/compose/portainer/docker-compose.yml << 'EOF'
services:
  portainer:
    image: portainer/portainer-ce:latest
    # 建议：将 latest 替换为固定版本号（如 2.21.4），以避免自动更新带来意外变更。
    # 查看可用版本：https://hub.docker.com/r/portainer/portainer-ce/tags
    container_name: portainer
    restart: unless-stopped
    ports:
      - "9000:9000"     # Web UI（HTTP）
      - "9443:9443"     # Web UI（HTTPS，自签名证书）
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /data/portainer:/data
EOF
```

> **说明：** 挂载 `/var/run/docker.sock` 使 Portainer 能管理本机 Docker，这是 Portainer CE 的标准部署方式。该挂载等价于 root 权限，因此端口 9000/9443 **不得对公网开放**，仅内网访问。

---

## 四、启动与初始验证

```bash
cd /data/compose/portainer

# 拉取镜像并启动
docker compose up -d

# 确认容器运行状态
docker compose ps

# 查看启动日志
docker compose logs --tail=30
```

验证端口监听：

```bash
ss -lntp | grep -E '9000|9443'
```

---

## 五、首次初始化

### 5.1 访问 Web UI

浏览器访问：`http://<docker-01-ip>:9000`

> 首次访问有 **5 分钟** 时间窗口完成初始化，超时后 Portainer 会锁定，需重启容器重置：  
> `docker restart portainer`

### 5.2 创建管理员账号

1. 输入用户名（如 `admin`）和密码（建议 12 位以上）
2. 点击 **Create user**

### 5.3 连接本地 Docker 环境

1. 选择 **Get Started**（使用本地 Docker Socket）
2. 点击 **local** 环境，进入主界面

---

## 六、通过 Nginx Proxy Manager 代理 Portainer

Portainer 部署完成后，建议通过 NPM 统一入口访问，避免记忆端口号。

### 6.1 在 NPM 中添加代理主机

登录 NPM 管理界面 → **Hosts** → **Proxy Hosts** → **Add Proxy Host**：

| 字段 | 值 |
|------|----|
| Domain Names | `portainer.home.example.com`（或其他你设置的域名） |
| Scheme | `http` |
| Forward Hostname / IP | `127.0.0.1` |
| Forward Port | `9000` |
| Websockets Support | **开启**（Portainer 需要） |
| Block Common Exploits | 开启 |

保存后访问：`http://portainer.home.example.com`（或配置 SSL 后使用 HTTPS）

### 6.2 可选：申请 SSL 证书

在代理主机 **SSL** 标签页，按 `docs/13` 中的步骤申请证书，启用 HTTPS 和 Force SSL。

---

## 七、Portainer 常用操作

### 7.1 查看容器

**Home** → 点击 **local** 环境 → **Containers**

可以看到所有容器的状态、端口、镜像、启动时间。

### 7.2 查看容器日志

在 Containers 列表中，点击容器名 → **Logs**，选择：

- **Auto-refresh logs**：自动刷新（类似 `docker logs -f`）
- **Lines**：显示最后 N 行

### 7.3 在界面中管理 Compose 应用（Stacks）

**Stacks** → **Add stack** → 选择 **Upload** 或粘贴 Compose 内容

> 推荐在 SSH 中直接用 `docker compose` 命令管理；Portainer 的 Stacks 功能适合临时部署或快速验证。

### 7.4 查看资源占用

**Dashboard** 中可以看到 CPU、内存、镜像数量、容器数量总览。

---

## 八、日常运维

```bash
cd /data/compose/portainer

# 查看容器状态
docker compose ps

# 更新到最新版本
docker compose pull
docker compose up -d

# 查看日志
docker compose logs -f

# 停止（不删除数据）
docker compose down
```

> 更新 Portainer 时，数据存储在 `/data/portainer/portainer.db`，更新不会丢失配置。

---

## 九、验收检查

- [ ] Portainer 容器运行正常（`docker compose ps` 显示 `Up`）
- [ ] 浏览器可访问 `http://<docker-01-ip>:9000`
- [ ] 管理员账号已创建，默认凭据已替换
- [ ] 在 Portainer 中可看到 `nginx-proxy-manager`、`portainer` 等容器
- [ ] 可在 Portainer 中查看容器日志
- [ ] 数据文件存在：`ls -lh /data/portainer/portainer.db`
- [ ] （可选）NPM 代理主机配置完成，可通过域名访问

---

## 十、安全建议

| 建议 | 操作 |
|------|------|
| 不暴露端口 9000/9443 到公网 | 防火墙规则限制为内网访问 |
| 使用 NPM + HTTPS 访问 | 避免密码在 HTTP 中明文传输 |
| 定期更新镜像 | `docker compose pull && docker compose up -d` |
| 备份 portainer.db | 纳入 PVE 备份，或定期复制 `/data/portainer/` |

---

## 十一、当前基础设施全貌

部署完成后，你的 homelab 已具备：

```
PVE 9 宿主机
├── LXC CT 201  redis-01        (192.168.1.201)   → 缓存层
├── LXC CT 202  mysql-01        (192.168.1.202)   → 数据库层
└── KVM VM  301  docker-01      (192.168.1.101)
                 ├── nginx-proxy-manager  :80/:443/:81   → 统一反向代理入口
                 └── portainer           :9000           → 容器管理 UI
```

> **说明：** 示例 IP 地址仅为演示，请替换为你实际规划的内网静态 IP。

---

## 十二、下一步建议

基础平台就绪后，可按需部署以下服务：

| 服务 | 说明 | 优先级 |
|------|------|--------|
| **Gitea** | 自托管 Git 服务，代码和配置版本管理 | ★★★ |
| **Grafana + Prometheus** | 可观测性，监控宿主机、LXC、容器指标 | ★★★ |
| **MinIO** | S3 兼容对象存储，用于应用附件/备份 | ★★☆ |
| **Vaultwarden** | 密码管理器（Bitwarden 兼容）| ★★☆ |
| **Uptime Kuma** | 服务健康监控和状态页 | ★★☆ |
