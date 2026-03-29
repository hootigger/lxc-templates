# Redis 与 MySQL 完成后的下一阶段推进指南

> 适用阶段：`redis-01` 和 `mysql-01` 已通过验收，准备推进 homelab 下一批建设。  
> 原则：每步都可验证、不跳跃、按需扩展。

---

## 一、先确认当前基础是否真的稳固

**不要急着推进，先花 10 分钟过一遍这个清单：**

### Redis 验收复核

```bash
# 登入 redis-01，执行：
systemctl status redis-server
redis-cli -a '你的密码' ping            # 期望：PONG
redis-cli -a '你的密码' CONFIG GET dir  # 期望：/data/redis
ls -lh /data/redis/                     # 应有 dump.rdb 或 appendonly.aof
```

- [ ] Redis 服务正常运行
- [ ] 数据目录确认为 `/data/redis`
- [ ] 持久化文件存在
- [ ] 重启容器后数据保留（上次测试通过）
- [ ] 从内网其他机器可连通

### MySQL 验收复核

```bash
# 登入 mysql-01，执行：
systemctl status mariadb
mysql -e "SHOW VARIABLES LIKE 'datadir';"  # 期望：/data/mysql/
mysql -e "SHOW DATABASES;"
ls -lh /data/mysql/
```

- [ ] MySQL/MariaDB 服务正常运行
- [ ] 数据目录确认为 `/data/mysql`
- [ ] 业务账号已创建且可从内网连接
- [ ] 备份脚本已配置并可执行
- [ ] 重启容器后数据保留

> **如果以上任一未通过，先修复，再往下走。**

---

## 二、下一阶段建设顺序

```
当前：redis-01 ✅  mysql-01 ✅
         ↓
第 2 阶段：docker-01 VM（Docker 宿主机）
         ↓
第 3 阶段：反向代理（运行在 docker-01 上）
         ↓
第 4 阶段：第一个 Compose 样板应用
         ↓
第 5 阶段：备份策略整合
         ↓
第 6 阶段：可观测性（monitor-01：Prometheus + Grafana）
```

---

## 三、第 2 阶段：docker-01 VM

### 为什么是 VM 而不是 LXC？

Docker 需要完整内核能力（overlay 文件系统、cgroup v2、iptables 等），在**无特权 LXC** 中运行 Docker 需要额外配置且维护复杂。建议：

> **docker-01 使用 Debian 12 VM，不用 LXC。**

### 创建参数建议

| 参数 | 推荐值 |
|------|--------|
| VM ID | 101 |
| 名称 | docker-01 |
| 系统 | Debian 12（cloud-init 或手动安装） |
| vCPU | 4 |
| 内存 | 8 GiB |
| 系统盘 | 32 GiB（SSD） |
| 数据盘 | 100 GiB（独立磁盘，挂载到 `/data`） |
| 网络 | 静态 IP，如 `192.168.1.101/24` |

### 初始化步骤

```bash
# 系统更新
apt update && apt upgrade -y
timedatectl set-timezone Asia/Shanghai
apt install -y curl wget vim htop

# 数据盘挂载（假设数据盘为 /dev/sdb）
mkfs.ext4 /dev/sdb
mkdir -p /data
echo '/dev/sdb /data ext4 defaults 0 2' >> /etc/fstab
mount -a
df -h /data  # 确认挂载成功

# 安装 Docker Engine
curl -fsSL https://get.docker.com | sh

# 配置非 root 用户（可选）
usermod -aG docker $USER

# 配置 Docker 日志轮转，防止日志无限膨胀
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "data-root": "/data/docker"
}
EOF

systemctl restart docker
systemctl enable docker

# 验证
docker version
docker compose version
docker run --rm hello-world
```

### 验收清单

- [ ] `docker version` 正常
- [ ] `docker compose version` 正常
- [ ] `hello-world` 容器运行成功
- [ ] Docker 数据目录在 `/data/docker`（不在系统盘）
- [ ] 日志轮转配置已生效
- [ ] 重启 VM 后 Docker 自动恢复

---

## 四、第 3 阶段：反向代理

### 方案选择

| 方案 | 适合场景 | 说明 |
|------|----------|------|
| Nginx Proxy Manager | 入门、有 Web UI | 上手最快 |
| Traefik | 自动服务发现 | 配置偏复杂但更灵活 |
| Caddy | 简洁、自动 HTTPS | 适合对 HTTPS 有需求 |

> **homelab 起步推荐 Nginx Proxy Manager（NPM）**，有 Web UI，最容易上手。

### 使用 Nginx Proxy Manager 快速部署

在 `docker-01` 上创建目录并启动：

```bash
mkdir -p /data/nginx-proxy-manager/{data,letsencrypt}
cd /data/nginx-proxy-manager

cat > docker-compose.yml << 'EOF'
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
      - /data/nginx-proxy-manager/data:/data
      - /data/nginx-proxy-manager/letsencrypt:/etc/letsencrypt
EOF

docker compose up -d
```

### 初始访问

- 管理界面：`http://docker-01-ip:81`
- 默认账号：`admin@example.com`
- 默认密码：`changeme`（**第一次登录后立即修改**）

### 验收清单

- [ ] 管理界面可访问
- [ ] 已修改默认管理员账号密码
- [ ] 至少配置一个内网域名代理测试（如 `gitea.lan` → `gitea-01:3000`）
- [ ] 代理规则可正常转发请求
- [ ] 重启后服务自动恢复

---

## 五、第 4 阶段：第一个 Compose 样板应用

### 目的

用一个最简单的应用走通整条链路：

```
域名访问 → 反向代理 → Compose 应用 → MySQL + Redis
```

### 推荐样板：Uptime Kuma（服务状态监控）

Uptime Kuma 是一个轻量的自托管监控页面，部署简单，效果直观，非常适合作为第一个样板。

```bash
mkdir -p /data/uptime-kuma
cd /data/uptime-kuma

cat > docker-compose.yml << 'EOF'
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1.23.16
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "3001:3001"
    volumes:
      - /data/uptime-kuma:/app/data
EOF

docker compose up -d
```

部署完成后：
1. 在 Nginx Proxy Manager 中添加代理规则：`uptime.lan` → `localhost:3001`
2. 访问 `http://uptime.lan` 验证链路
3. 添加对 `redis-01` 和 `mysql-01` 的监控（TCP 端口探测）

### Compose 项目目录约定（统一规范）

从第一个项目开始就建立规范，后续所有项目遵循：

```
/data/<appname>/
├── docker-compose.yml   # 服务定义
├── .env                 # 环境变量（敏感信息，不提交 Git）
├── data/                # 应用数据（如需要）
└── logs/                # 日志（可选）
```

```bash
# .env 示例
APP_PORT=3001
APP_DOMAIN=uptime.lan
DB_HOST=192.168.1.202
DB_USER=myapp
DB_PASS=yourpassword
REDIS_HOST=192.168.1.201
REDIS_PASS=yourpassword
```

### 验收清单

- [ ] 应用容器正常运行：`docker compose ps`
- [ ] 通过反向代理域名可访问
- [ ] 使用 `.env` 管理所有配置，未硬编码密码
- [ ] 数据持久化到 `/data/<appname>/`
- [ ] 重启 docker-01 后应用自动恢复

---

## 六、第 5 阶段：备份策略整合

### 当前需要备份的对象

| 对象 | 类型 | 备份方式 | 建议频率 |
|------|------|----------|----------|
| redis-01 | LXC | PVE 快照 + Redis AOF/RDB | 每日 |
| mysql-01 | LXC | PVE 快照 + mysqldump | 每日 |
| docker-01 | VM | PVE 快照 | 每周 |
| `/data` on docker-01 | 数据目录 | rsync 到备份盘 | 每日 |

### 数据库备份脚本（mysql-01 上）

如果 `mysql-01` 上还没有备份脚本，参考以下配置：

```bash
# 创建 MySQL 认证配置（避免密码出现在进程列表）
cat > /root/.my.cnf << 'EOF'
[mysqldump]
user=root
password=你的root密码
EOF
chmod 600 /root/.my.cnf

cat > /usr/local/bin/mysql-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/data/mysql/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

mysqldump --defaults-file=/root/.my.cnf \
  --all-databases \
  --single-transaction \
  > "$BACKUP_DIR/all_databases_$DATE.sql"

gzip "$BACKUP_DIR/all_databases_$DATE.sql"
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
echo "[$(date)] 备份完成：all_databases_$DATE.sql.gz"
EOF

chmod +x /usr/local/bin/mysql-backup.sh

# 每天凌晨 3 点执行
echo "0 3 * * * root /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1" \
  > /etc/cron.d/mysql-backup
```

### 备份验证（至少做一次）

```bash
# 在 mysql-01 上手动执行一次备份
/usr/local/bin/mysql-backup.sh

# 确认备份文件存在且有内容
ls -lh /data/mysql/backups/
zcat /data/mysql/backups/all_databases_*.sql.gz | head -20

# 恢复演练：在测试环境重建一张表
# mysql -u root -p < /tmp/restore_test.sql
```

### PVE 层快照建议

在 PVE Web 界面：
- 进入 Datacenter → Backup
- 添加备份任务，选择 `redis-01` 和 `mysql-01`
- 建议频率：每天执行，保留最近 7 份
- 备份存储：**不要和系统盘共用同一存储**

### 验收清单

- [ ] mysql-01 备份脚本可执行，定时任务已配置
- [ ] redis-01 持久化策略已验证（重启后数据保留）
- [ ] PVE 层 LXC 备份任务已配置
- [ ] 完成至少一次备份 + 恢复演练
- [ ] 备份文件存储位置与系统盘分离

---

## 七、第 6 阶段：可观测性（monitor-01）

### 部署前提

- docker-01 已稳定运行
- 反向代理已配置

### 推荐方案：Prometheus + Grafana（Compose 部署在 docker-01）

> 也可以单独建一个 `monitor-01` LXC，取决于你是否希望监控与应用完全隔离。  
> **起步阶段推荐直接跑在 docker-01 上，简单省事。**

```bash
mkdir -p /data/monitor/{prometheus,grafana}
cd /data/monitor

# Prometheus 配置
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # 如果 redis-01 / mysql-01 上安装了 exporter，在这里添加
  # - job_name: 'redis'
  #   static_configs:
  #     - targets: ['192.168.1.201:9121']
EOF

cat > docker-compose.yml << 'EOF'
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    restart: unless-stopped
    ports:
      - "9090:9090"
    volumes:
      - /data/monitor/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - /data/monitor/prometheus:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--storage.tsdb.retention.time=30d'

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    restart: unless-stopped
    ports:
      - "3000:3000"
    volumes:
      - /data/monitor/grafana:/var/lib/grafana
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=your_grafana_password
      - GF_USERS_ALLOW_SIGN_UP=false

EOF

docker compose up -d
```

### 接入 Redis 和 MySQL 监控（可选，推荐）

```bash
# 在 redis-01 上安装 redis_exporter
# 在 mysql-01 上安装 mysqld_exporter
# 然后在 prometheus.yml 中添加对应 scrape 配置
# Grafana 导入对应 Dashboard（Redis：ID 11835，MySQL：ID 7362）
```

### 验收清单

- [ ] Prometheus 界面可访问：`http://docker-01:9090` 或通过反向代理域名
- [ ] Grafana 界面可访问，已修改默认密码
- [ ] 至少有一个数据源已配置（Prometheus → Grafana）
- [ ] 至少有一个 Dashboard 可以显示指标
- [ ] redis-01 和 mysql-01 的基础指标可在 Grafana 中查看（如已配置 exporter）

---

## 八、阶段总结与里程碑

完成以上 6 个阶段后，你的 homelab 应具备：

| 能力 | 状态 |
|------|------|
| 缓存服务（Redis）| ✅ 第 1 阶段 |
| 数据库服务（MySQL）| ✅ 第 1 阶段 |
| Docker 宿主机 | 第 2 阶段 |
| 统一访问入口（反向代理）| 第 3 阶段 |
| 第一个 Compose 应用 | 第 4 阶段 |
| 基础备份策略 | 第 5 阶段 |
| 可观测性（指标 + 仪表盘）| 第 6 阶段 |

**完成这 6 个阶段后，可以开始：**

- 部署更多业务应用（Gitea、MinIO、自定义项目）
- 按需扩展 LXC 实例
- 探索 k3s 等更进阶方向

---

## 九、常见卡点提示

| 问题 | 排查方向 |
|------|----------|
| docker-01 Docker 数据占满系统盘 | 确认 `data-root` 已指向 `/data/docker` |
| Compose 应用启动后无法访问数据库 | 检查 mysql-01 的 `bind-address` 和用户 `host` 权限 |
| 反向代理 502 | 检查 Compose 应用容器是否正常运行，端口是否正确 |
| 备份文件为空 | 检查 MySQL root 密码配置、`.my.cnf` 文件权限 |
| Prometheus 采集不到数据 | 检查 exporter 是否安装并运行，防火墙端口是否开放 |
