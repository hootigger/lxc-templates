# Docker 部署手册（docker-01）

本文档描述在 Proxmox VE 上创建 **KVM 虚拟机** 作为 Docker 运行层（`docker-01`）的完整流程，涵盖 VM 规格、系统初始化、Docker/Compose 安装、目录规范及首个应用上线步骤。

> **为什么用 VM 而非 LXC？**
> Docker 在无特权 LXC 中运行需要特殊配置，兼容性有限。`docker-01` 直接使用 KVM 虚拟机，避免嵌套虚拟化带来的权限和兼容性问题，适合作为所有 Compose 应用的主运行层。

---

## 一、VM 创建参数

| 参数 | 推荐值 | 说明 |
|------|--------|------|
| 类型 | KVM 虚拟机 | 非 LXC |
| VM ID | `301` | 与 LXC CT ID 分段管理 |
| 主机名 | `docker-01` | |
| 系统镜像 | Debian 12 | 与 LXC 保持一致 |
| CPU | 2–4 vCPU | 可按实际应用数量扩容 |
| 内存 | 4096–8192 MB | 建议从 4 GB 起步 |
| 系统盘（scsi0） | 20–40 GB | 存放 OS、Docker 引擎、镜像层 |
| 数据盘（scsi1） | 50 GB+ | 存放应用数据、Compose 配置、volume |
| 网卡 | VirtIO | 性能更好 |
| 开机自启 | **是** | |
| QEMU Guest Agent | **安装启用** | 便于 PVE 管理 |

---

## 二、系统初始化

首次进入 VM 后执行：

```bash
# 验证主机名与网络
hostname
ip a
df -h

# 更新系统
apt update && apt upgrade -y

# 安装常用工具
apt install -y curl wget vim bash-completion htop qemu-guest-agent

# 启用 QEMU Guest Agent
systemctl enable --now qemu-guest-agent

# 启用 SSH 开机自启
systemctl enable ssh

# 配置时区（如需）
timedatectl set-timezone Asia/Shanghai
timedatectl
```

---

## 三、数据盘挂载

将第二块磁盘（`/dev/sdb` 或 `/dev/vdb`，按实际设备名为准）挂载到 `/data`：

```bash
# 确认磁盘设备名
lsblk

# 分区（整盘一个分区）
parted /dev/sdb -- mklabel gpt mkpart primary 0% 100%

# 格式化为 ext4
mkfs.ext4 /dev/sdb1

# 创建挂载点
mkdir -p /data

# 获取分区 UUID
blkid /dev/sdb1
```

将 UUID 写入 `/etc/fstab`（替换 `<UUID>` 为实际值）：

```bash
echo "UUID=<UUID> /data ext4 defaults 0 2" >> /etc/fstab

# 挂载并验证
mount -a
df -h | grep /data
```

---

## 四、安装 Docker Engine

使用 Docker 官方安装脚本（适合快速上手，生产环境建议优先使用下方手动安装方式）：

```bash
# 建议先查看脚本内容再执行：curl -fsSL https://get.docker.com | less
curl -fsSL https://get.docker.com | sh
```

或使用官方 APT 仓库手动安装：

```bash
# 添加 Docker 官方 GPG key 和仓库
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

启用并验证：

```bash
systemctl enable --now docker
docker version
docker compose version
```

---

## 五、应用目录规范

所有 Compose 应用统一放在 `/data/compose/<app-name>/`，持久化数据放在 `/data/<app-name>/`。

```
/data/
├── compose/              # Compose 配置和管理目录
│   ├── nginx-proxy/      # 反向代理
│   ├── app-demo/         # 示例应用
│   └── ...
├── nginx-proxy/          # 反向代理持久化数据（证书、配置）
├── app-demo/             # 示例应用持久化数据
└── ...
```

创建目录：

```bash
mkdir -p /data/compose
```

每个应用的 Compose 目录结构示例：

```
/data/compose/app-demo/
├── docker-compose.yml    # 主编排文件
├── .env                  # 环境变量（不入库）
└── .env.example          # 环境变量模板（可入库）
```

---

## 六、部署反向代理

建议将反向代理作为第一个上线的应用，用于统一管理域名访问。以下以 **Nginx Proxy Manager** 为例：

```bash
mkdir -p /data/compose/nginx-proxy
mkdir -p /data/nginx-proxy/{data,letsencrypt}

cat > /data/compose/nginx-proxy/docker-compose.yml << 'EOF'
services:
  nginx-proxy-manager:
    image: jc21/nginx-proxy-manager:latest
    container_name: nginx-proxy-manager
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "81:81"
    volumes:
      - /data/nginx-proxy/data:/data
      - /data/nginx-proxy/letsencrypt:/etc/letsencrypt
EOF

cd /data/compose/nginx-proxy
docker compose up -d
docker compose ps
```

首次访问管理界面：`http://<docker-01-ip>:81`，默认账号 `admin@example.com` / `changeme`。

> **⚠️ 安全提醒：上述默认凭据是公开已知的，首次登录后必须立即修改邮箱和密码，否则任何能访问该端口的人都可以接管管理界面。**

---

## 七、首个 Compose 应用样板

以一个接入 MySQL 和 Redis 的 Web 应用为例，创建标准 Compose 文件：

```bash
mkdir -p /data/compose/app-demo
mkdir -p /data/app-demo

cat > /data/compose/app-demo/.env.example << 'EOF'
DB_HOST=<mysql-01-ip>
DB_PORT=3306
DB_NAME=app_db
DB_USER=app_user
DB_PASSWORD=

REDIS_HOST=<redis-01-ip>
REDIS_PORT=6379
REDIS_PASSWORD=

APP_PORT=8080
EOF

cp /data/compose/app-demo/.env.example /data/compose/app-demo/.env
# 编辑 .env，填入实际值
vim /data/compose/app-demo/.env
```

Compose 文件模板（`docker-compose.yml`）：

```yaml
services:
  app:
    image: <your-app-image>
    container_name: app-demo
    restart: unless-stopped
    ports:
      - "${APP_PORT}:8080"
    environment:
      - DB_HOST=${DB_HOST}
      - DB_PORT=${DB_PORT}
      - DB_NAME=${DB_NAME}
      - DB_USER=${DB_USER}
      - DB_PASSWORD=${DB_PASSWORD}
      - REDIS_HOST=${REDIS_HOST}
      - REDIS_PORT=${REDIS_PORT}
      - REDIS_PASSWORD=${REDIS_PASSWORD}
    volumes:
      - /data/app-demo:/app/data
```

> **注意：** 环境变量中的密码在 `docker inspect` 输出中可见。homelab 内网场景下这是常见做法，如需更高安全性可改用 [Docker Secrets](https://docs.docker.com/engine/swarm/secrets/) 或外部密钥管理（如 Vault）。

启动：

```bash
cd /data/compose/app-demo
docker compose up -d
docker compose ps
docker compose logs -f
```

---

## 八、常用运维命令

```bash
# 查看所有运行中的容器
docker ps

# 查看某应用日志（最新 100 行）
cd /data/compose/<app-name>
docker compose logs --tail=100 -f

# 更新镜像并重启
docker compose pull
docker compose up -d

# 停止应用
docker compose down

# 停止并清理 volume（危险，会删除数据）
docker compose down -v

# 清理未使用的镜像
docker image prune -f
```

---

## 九、验收检查

```bash
# Docker 服务状态
systemctl status docker --no-pager

# 查看所有容器
docker ps -a

# 确认数据目录挂载
df -h | grep /data
ls -la /data/

# 从内网其他机器测试反向代理
curl -I http://<docker-01-ip>
```

---

## 十、安全建议

- 不直接在公网暴露 Docker daemon API（默认 Unix socket，不暴露 TCP 端口）
- 管理员界面（如端口 81）不对外暴露，通过 VPN 或 SSH 隧道访问
- `.env` 文件不纳入版本控制（加入 `.gitignore`）
- 定期更新镜像：`docker compose pull && docker compose up -d`
- 在 PVE 中为此 VM 配置备份任务，重点备份 `/data/compose/` 目录
