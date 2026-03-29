# 反向代理部署手册 — Nginx Proxy Manager

> 前置条件：`docker-01` VM 已完成系统初始化、数据盘挂载（`/data`）和 Docker Engine 安装。  
> 本文档是 `docs/12-docker-01-deployment.md` 的延续，专注于反向代理的选型、部署与日常管理。

---

## 一、选型说明

### 为什么选 Nginx Proxy Manager？

| 维度 | Nginx Proxy Manager (NPM) | Traefik |
|------|--------------------------|---------|
| 上手难度 | ★☆☆ 极低，Web UI 操作 | ★★★ 需熟悉标签/YAML 配置 |
| 适用场景 | homelab、服务较少、配置稳定 | 微服务、动态容器路由 |
| SSL 自动化 | 内置 Let's Encrypt，点击申请 | 需配置 resolver/certResolver |
| 自定义 nginx 配置 | 支持（Advanced 标签页） | 不直接支持 nginx 配置 |
| 资源占用 | 较低（~50 MB 内存） | 较低（~30 MB 内存） |
| 状态持久化 | SQLite 数据库 + 证书目录 | 配置文件 |

**结论：homelab 场景下 NPM 是最快落地的选择。** 在服务较少（10–20 个）、配置不频繁变化的情况下，优先使用 NPM；如未来迁移到 Docker Swarm 或 Kubernetes，再考虑 Traefik。

---

## 二、目录规划

在 `docker-01` 上执行：

```bash
# 创建 Compose 配置目录
mkdir -p /data/compose/nginx-proxy

# 创建持久化数据目录
mkdir -p /data/nginx-proxy/data
mkdir -p /data/nginx-proxy/letsencrypt
```

目录说明：

```
/data/
├── compose/
│   └── nginx-proxy/
│       └── docker-compose.yml    # Compose 编排文件
└── nginx-proxy/
    ├── data/                     # NPM 数据库、配置（SQLite）
    └── letsencrypt/              # SSL 证书文件
```

---

## 三、Compose 文件

创建 `/data/compose/nginx-proxy/docker-compose.yml`：

```bash
cat > /data/compose/nginx-proxy/docker-compose.yml << 'EOF'
services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    # 建议：将 latest 替换为固定版本号（如 2.12.1），以避免自动更新带来意外变更。
    # 查看可用版本：https://hub.docker.com/r/jc21/nginx-proxy-manager/tags
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"       # HTTP 流量入口
      - "443:443"     # HTTPS 流量入口
      - "81:81"       # NPM Web 管理界面
    volumes:
      - /data/nginx-proxy/data:/data
      - /data/nginx-proxy/letsencrypt:/etc/letsencrypt
EOF
```

---

## 四、启动与初始验证

```bash
cd /data/compose/nginx-proxy

# 拉取镜像并启动
docker compose up -d

# 确认容器运行状态
docker compose ps

# 查看启动日志（等待出现 "Nginx started" 后再访问）
docker compose logs -f --tail=50
```

预期输出中应包含：

```
nginx-proxy-manager  | [services.d] done.
```

验证端口监听：

```bash
ss -lntp | grep -E '80|81|443'
```

---

## 五、首次登录与安全加固

### 5.1 登录管理界面

浏览器访问：`http://<docker-01-ip>:81`

默认凭据（**公开已知，必须立即修改**）：

| 字段 | 默认值 |
|------|--------|
| 邮箱 | `admin@example.com` |
| 密码 | `changeme` |

### 5.2 立即修改凭据

1. 登录后点击右上角用户名 → **Edit Profile**
2. 修改邮箱为你自己的邮箱
3. 修改密码（建议 16 位以上，含大小写字母+数字+符号）
4. 保存并重新登录

> **⚠️ 安全要求：端口 81 管理界面不得对公网开放。建议通过防火墙规则限制为仅内网可访问，或通过 VPN / SSH 隧道访问。**

---

## 六、配置第一个代理主机（Proxy Host）

### 6.1 前提：域名解析

有两种方式：

**方式 A：公网域名**
- 在 DNS 提供商将子域名 A 记录指向 `docker-01` 的公网 IP（或路由器 WAN IP + 端口转发）
- 适合需要外网访问的服务

**方式 B：内网 hosts / 本地 DNS**
- 在路由器 DNS / AdGuard / Pi-hole 中添加解析记录，指向 `docker-01` 内网 IP
- 适合仅内网使用的 homelab 服务

### 6.2 在 NPM 中添加代理主机

1. 点击 **Hosts** → **Proxy Hosts** → **Add Proxy Host**
2. 填写 **Details** 标签页：

   | 字段 | 说明 | 示例 |
   |------|------|------|
   | Domain Names | 访问该服务的域名 | `portainer.home.example.com` |
   | Scheme | 后端协议 | `http`（内网一般 HTTP） |
   | Forward Hostname / IP | 后端服务地址 | `127.0.0.1`（本机）或内网 IP |
   | Forward Port | 后端服务端口 | `9000` |
   | Cache Assets | 可选 | 通常关闭 |
   | Block Common Exploits | **开启** | |
   | Websockets Support | 按需 | Portainer 需要开启 |

3. 点击 **Save**

### 6.3 代理转发 LXC 容器服务（示例）

如果需要将内网 LXC 容器的服务（如 redis-01 的 Web 界面、mysql-01 的管理工具）通过 NPM 代理：

| 服务 | 内网 IP | 端口 | NPM Forward IP |
|------|---------|------|----------------|
| Portainer（docker-01 本机） | `127.0.0.1` | `9000` | `127.0.0.1` |
| Gitea | `192.168.1.x` | `3000` | LXC 容器内网 IP |
| Grafana | `192.168.1.x` | `3000` | monitor-01 内网 IP |

---

## 七、申请 SSL 证书（Let's Encrypt）

> 申请 SSL 需要域名能从公网访问（HTTP-01 验证），或使用支持的 DNS 提供商（DNS-01 验证）。仅内网使用可跳过本节。

### 7.1 HTTP-01 验证（域名公网可达）

在代理主机配置页 → **SSL** 标签页：

1. **SSL Certificate**：选择 **Request a new SSL Certificate**
2. **Force SSL**：**开启**（所有 HTTP 请求重定向到 HTTPS）
3. **HTTP/2 Support**：开启
4. **Email Address**：填写有效邮箱（Let's Encrypt 证书过期提醒用）
5. 勾选 **I Agree to the Let's Encrypt Terms of Service**
6. 点击 **Save**，等待 30–60 秒证书签发

### 7.2 DNS-01 验证（内网服务 / 泛域名）

适用场景：服务不对外网暴露，但希望使用 HTTPS（如内网泛域名 `*.home.example.com`）。

1. **SSL Certificate**：选择 **Request a new SSL Certificate**
2. 勾选 **Use a DNS Challenge**
3. 选择 DNS 提供商（Cloudflare、Aliyun 等）
4. 填写 API Token / 凭据
5. 保存并等待签发

---

## 八、TCP/UDP 流代理（Stream）

NPM 支持四层流代理，适合代理 MySQL、Redis 等 TCP 服务（**非 Web 服务**）。

> 注意：Stream 代理仅做端口转发，不具备 HTTP 七层路由能力，通常只在特殊场景使用。

配置入口：**Hosts** → **Streams** → **Add Stream**

| 字段 | 说明 |
|------|------|
| Incoming Port | NPM 监听端口（如 `3306`） |
| Forward Host | 后端服务 IP（如 mysql-01 内网 IP） |
| Forward Port | 后端端口（如 `3306`） |
| TCP / UDP | 选择协议 |

> **⚠️ 不建议通过公网暴露 MySQL / Redis 的 Stream 端口。如需远程访问，使用 VPN 或 SSH 隧道。**

---

## 九、日常运维

```bash
# 查看容器状态
cd /data/compose/nginx-proxy
docker compose ps

# 查看实时日志
docker compose logs -f

# 查看 nginx 访问日志
docker exec nginx-proxy-manager tail -f /data/logs/proxy-host-1_access.log

# 更新到最新版本
docker compose pull
docker compose up -d

# 重启 NPM（在界面点击保存配置后一般无需手动重启）
docker compose restart
```

---

## 十、验收检查

完成部署后，逐项确认：

- [ ] NPM 容器正常运行（`docker compose ps` 显示 `Up`）
- [ ] 管理界面可通过 `http://<docker-01-ip>:81` 访问
- [ ] 默认凭据已修改
- [ ] 端口 80 和 443 已监听（`ss -lntp | grep -E ':80|:443'`）
- [ ] 至少一个代理主机配置成功并可访问
- [ ] 数据目录 `/data/nginx-proxy/` 中存在配置文件

---

## 十一、下一步

反向代理就绪后，可以继续部署：

- **[docs/14] Portainer**：容器管理 Web UI，通过 NPM 代理访问
- **[后续]** Gitea、Grafana 等 Compose 应用，均通过 NPM 统一入口暴露
