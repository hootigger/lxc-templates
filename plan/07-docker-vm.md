# Docker VM 初始化与 Compose 规范

> 虚拟机：`docker-01`（VM ID 301，KVM 虚拟机）  
> 数据目录：`/data`（独立数据盘挂载）

---

## 一、在 PVE 中创建 VM

### 1.1 创建参数

| 字段        | 推荐值                              |
|-------------|-------------------------------------|
| VM ID       | 301                                 |
| Name        | docker-01                           |
| OS          | Debian 12 / Ubuntu 22.04 Server     |
| vCPU        | 4                                   |
| 内存        | 8192 MB                             |
| 系统盘      | 32 GB（存放系统 + Docker 镜像层）   |
| 数据盘      | 另加 100 GB+（挂载到 `/data`）      |
| 网络        | 固定 IP，如 192.168.1.101           |
| 开机自启    | 是                                  |

### 1.2 数据盘挂载

系统安装完成后，在 PVE 中添加第二块磁盘，并在 VM 内挂载到 `/data`：

```bash
# 查看新磁盘设备名（通常为 /dev/sdb 或 /dev/vdb）
lsblk

# 格式化数据盘
mkfs.ext4 /dev/sdb

# 创建挂载点
mkdir -p /data

# 获取磁盘 UUID
blkid /dev/sdb

# 编辑 /etc/fstab，添加开机自动挂载
echo "UUID=<磁盘UUID> /data ext4 defaults 0 2" >> /etc/fstab

# 挂载
mount -a

# 验证
df -h /data
```

---

## 二、系统基础初始化

```bash
# 更新系统
apt update && apt upgrade -y

# 安装常用工具
apt install -y curl wget vim git net-tools htop

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 确认时区
date
```

---

## 三、安装 Docker Engine

```bash
# 安装依赖
apt install -y ca-certificates curl gnupg

# 添加 Docker 官方 GPG 密钥
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# 添加 Docker 软件源
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

# 安装 Docker
apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 启动并设置开机自启
systemctl enable docker
systemctl start docker

# 验证
docker version
docker compose version
```

---

## 四、配置 Docker 数据目录

将 Docker 数据目录迁移到数据盘（可选但推荐）：

```bash
# 停止 Docker
systemctl stop docker

# 创建 Docker 数据目录
mkdir -p /data/docker

# 配置 Docker daemon
cat > /etc/docker/daemon.json << 'EOF'
{
  "data-root": "/data/docker",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

# 启动 Docker
systemctl start docker

# 验证数据目录
docker info | grep "Docker Root Dir"
```

---

## 五、Compose 项目目录规范

所有 Compose 项目统一放在 `/data/compose/` 下：

```
/data/compose/
├── project-a/
│   ├── docker-compose.yml
│   ├── .env
│   └── data/           # 容器数据挂载目录
│       ├── config/
│       ├── storage/
│       └── logs/
├── project-b/
│   ├── docker-compose.yml
│   ├── .env
│   └── data/
└── nginx-proxy/        # 反向代理
    ├── docker-compose.yml
    ├── .env
    └── data/
        ├── conf.d/
        ├── certs/
        └── logs/
```

### 目录创建

```bash
mkdir -p /data/compose
```

---

## 六、Compose 项目模板

```yaml
# docker-compose.yml 示例
services:
  app:
    image: your-image:tag
    container_name: project-a
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./data/config:/app/config
      - ./data/storage:/app/storage
      - ./data/logs:/app/logs
    networks:
      - proxy
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.project-a.rule=Host(`project-a.example.com`)"

networks:
  proxy:
    external: true
    name: proxy
```

`.env` 文件示例：

```env
# 数据库连接（指向 LXC 中的 mysql-01）
DB_HOST=192.168.1.201
DB_PORT=3306
DB_NAME=myapp
DB_USER=myapp
DB_PASS=你的数据库密码

# Redis 连接（指向 LXC 中的 redis-01）
REDIS_HOST=192.168.1.202
REDIS_PORT=6379
REDIS_PASS=你的Redis密码

# MinIO 连接（指向 LXC 中的 minio-01）
MINIO_ENDPOINT=192.168.1.203:9000
MINIO_ACCESS_KEY=myapp-user
MINIO_SECRET_KEY=myapp强密码
```

---

## 七、部署反向代理（Traefik）

```bash
mkdir -p /data/compose/traefik/data/{certs,logs}

cat > /data/compose/traefik/docker-compose.yml << 'EOF'
services:
  traefik:
    image: traefik:v3.0
    container_name: traefik
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./data/traefik.yml:/traefik.yml:ro
      - ./data/certs:/certs
      - ./data/logs:/logs
    networks:
      - proxy

networks:
  proxy:
    name: proxy
    driver: bridge
EOF

# 创建 proxy 网络（所有 Compose 项目共用）
docker network create proxy

# 启动反向代理
cd /data/compose/traefik
docker compose up -d
```

---

## 八、验收检查

```bash
# 1. Docker 版本
docker version
docker compose version

# 2. 数据目录确认
docker info | grep "Docker Root Dir"
# 预期：/data/docker

# 3. 启动测试容器
docker run --rm hello-world

# 4. Compose 项目测试
cd /data/compose/traefik
docker compose ps

# 5. 重启后验证
shutdown -r now
# 重启后确认 Docker 和所有 Compose 项目自动恢复
```
