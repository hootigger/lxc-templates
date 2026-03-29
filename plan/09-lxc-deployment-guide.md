# LXC 基础设施部署手册

> 本文档覆盖第一批基础设施 LXC 的**创建参数、安装流程、数据目录配置与验收检查**。  
> 数据目录统一使用 `/data/<service>` 规范。

---

## 目录

1. [数据目录约定](#1-数据目录约定)
2. [资源规格速查表](#2-资源规格速查表)
3. [LXC 通用创建流程](#3-lxc-通用创建流程)
4. [redis-01 部署](#4-redis-01-部署)
5. [mysql-01 部署](#5-mysql-01-部署)
6. [minio-01 部署（参考）](#6-minio-01-部署参考)
7. [gitea-01 部署（参考）](#7-gitea-01-部署参考)
8. [常见问题与排查](#8-常见问题与排查)

---

## 1. 数据目录约定

所有基础设施 LXC 遵循统一约定：

| 约定 | 说明 |
|------|------|
| `rootfs` | 只放系统和软件包，**不放业务数据** |
| `mp0` | PVE 托管的独立数据盘，挂载到容器内 `/data/<service>` |
| 服务数据目录 | 统一使用 `/data/<service>`，不使用系统默认路径 |

### 各服务数据目录

| 服务 | 容器内数据目录 | PVE 挂载点 |
|------|--------------|-----------|
| Redis | `/data/redis` | mp0 |
| MySQL | `/data/mysql` | mp0 |
| MinIO | `/data/minio` | mp0 |
| Gitea | `/data/gitea` | mp0 |
| Prometheus | `/data/prometheus` | mp0 |
| Grafana | `/data/grafana` | mp1（可与 Prometheus 共 mp0） |

> **为什么不直接用 `/var/lib/<service>`？**  
> 使用 `/data/<service>` 能让数据目录与系统目录明确分离，便于独立备份、迁移和容量扩容，  
> 也方便在 PVE 层面直接对数据盘进行快照或扩容而不影响系统盘。

---

## 2. 资源规格速查表

> 以下为 homelab 场景推荐最低起步规格，可根据实际负载调整。

| 容器 | CT ID | vCPU | 内存 | rootfs | mp0（数据盘） | 容器内数据目录 |
|------|-------|------|------|--------|------------|--------------|
| redis-01 | 201 | 1 | 1024 MB | 8 GiB | 8 GiB | `/data/redis` |
| mysql-01 | 202 | 2 | 2048 MB | 8 GiB | 30 GiB | `/data/mysql` |
| minio-01 | 203 | 2 | 2048 MB | 8 GiB | 100 GiB+ | `/data/minio` |
| gitea-01 | 204 | 2 | 1024 MB | 8 GiB | 20 GiB | `/data/gitea` |
| monitor-01 | 205 | 2 | 2048 MB | 8 GiB | 20 GiB | `/data/prometheus` |

### 说明

**Redis（redis-01）**
- 内存：1 GiB 足够起步；若作为主要缓存可按实际数据集大小上调
- 数据盘：8 GiB 覆盖大多数缓存 + AOF 持久化场景
- 纯缓存场景可以不开 RDB，更节省磁盘 IO

**MySQL（mysql-01）**
- 内存：2 GiB 起，`innodb_buffer_pool_size` 建议设置为内存的 50–70%
- 数据盘：30 GiB 起步，按实际库大小规划；日志和数据在同一目录
- CPU：2 核起，高并发场景可上调

**MinIO（minio-01）**
- 数据盘：按实际对象存储需求规划，100 GiB 是参考起步值
- 内存：2 GiB 起步，大流量或大量元数据时上调

**Gitea（gitea-01）**
- 内存：1 GiB 对于小团队 / homelab 足够
- 数据盘：20 GiB 覆盖代码仓库 + 附件

**monitor-01（Prometheus + Grafana）**
- 内存：2 GiB，Prometheus 时序数据库本身较消耗内存
- 数据盘：20 GiB，按采集频率和保留周期调整
- Grafana 数据量小，可与 Prometheus 共用 mp0，分子目录管理

---

## 3. LXC 通用创建流程

### 3.1 PVE 界面创建参数

在 PVE Web 界面「创建 CT」时，推荐以下通用设置：

| 选项 | 推荐值 | 说明 |
|------|--------|------|
| 无特权容器 | **勾选** | 安全隔离更好 |
| 嵌套（Nesting） | **不勾** | 普通基础服务不需要 |
| 模板 | Debian 12 | 稳定、包丰富、LXC 兼容性好 |
| rootfs 存储 | 系统存储池 | 系统与数据分离 |
| mp0 存储 | 业务数据存储池 | 独立数据盘 |
| mp0 路径 | `/data/<service>` | 统一数据目录规范 |
| mp0 备份 | **勾选** | 确保数据随 LXC 备份 |
| 网络 | 静态 IP | 避免 IP 漂移 |
| DNS | 路由器 IP 或内网 DNS | |

### 3.2 创建后通用初始化

每个 LXC 创建完成并启动后，执行以下基础初始化：

```bash
# 更新软件包
apt update && apt upgrade -y

# 安装基础工具
apt install -y curl wget vim htop net-tools lsof

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 验证时间
timedatectl status

# 检查数据挂载点是否正常
ls -ld /data/<service>
df -h /data/<service>
```

### 3.3 SSH 访问配置（可选）

```bash
# 允许 root 登录（homelab 场景，视安全需求决定）
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
systemctl restart ssh
```

---

## 4. redis-01 部署

### 4.1 PVE 创建参数

| 参数 | 值 |
|------|-----|
| CT ID | 201 |
| hostname | redis-01 |
| 无特权 | 是 |
| 嵌套 | 否 |
| 模板 | Debian 12 |
| rootfs 大小 | 8 GiB |
| mp0 大小 | 8 GiB |
| mp0 路径 | `/data/redis` |
| mp0 备份 | 勾选 |
| vCPU | 1 |
| 内存 | 1024 MB |
| IP | 静态，如 `192.168.1.201/24` |

### 4.2 安装 Redis

```bash
# 安装 Redis
apt update && apt install -y redis-server

# 确认安装版本
redis-server --version
```

### 4.3 配置数据目录

```bash
# 检查挂载点是否就绪
ls -ld /data/redis
df -h /data/redis

# 停止 Redis 服务（安装后默认启动，先停止再调整）
systemctl stop redis-server

# 如果 /data/redis 目录为空，迁移默认数据（如有）
# 通常新安装无需迁移，直接设置权限即可
chown -R redis:redis /data/redis
chmod 750 /data/redis
```

### 4.4 修改 Redis 配置

编辑 `/etc/redis/redis.conf`：

```bash
# 修改数据目录
sed -i 's|^dir .*|dir /data/redis|' /etc/redis/redis.conf

# 验证修改
grep '^dir' /etc/redis/redis.conf
```

手动确认 `/etc/redis/redis.conf` 中以下关键配置：

```ini
# 数据目录（必改）
dir /data/redis

# 持久化策略 - 推荐同时开启 RDB + AOF
# RDB 快照
save 900 1
save 300 10
save 60 10000

# AOF 持久化
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# 绑定地址（仅局域网访问）
bind 0.0.0.0

# 端口
port 6379

# 密码（强烈建议设置）
requirepass your_strong_password_here

# 日志文件
logfile /var/log/redis/redis-server.log

# 最大内存（可选，防止 OOM）
# maxmemory 512mb
# maxmemory-policy allkeys-lru
```

### 4.5 启动并验证

```bash
# 重启 Redis 服务
systemctl restart redis-server
systemctl enable redis-server

# 检查服务状态
systemctl status redis-server

# 检查监听端口
ss -tlnp | grep 6379

# 连接测试（需要输入上面设置的密码）
redis-cli -a your_strong_password_here ping
# 期望输出：PONG

# 写入测试数据并验证持久化
redis-cli -a your_strong_password_here SET test_key "hello"
redis-cli -a your_strong_password_here GET test_key
# 期望输出：hello

# 确认数据文件在正确目录
ls -lh /data/redis/
```

### 4.6 重启验证

```bash
# 重启容器后验证数据是否保留
# 在 PVE 中重启 LXC，或在容器内：
reboot

# 重启后进入容器，检查数据是否还在
redis-cli -a your_strong_password_here GET test_key
# 期望输出：hello
```

### 4.7 验收清单

- [ ] `systemctl status redis-server` 显示 active (running)
- [ ] `redis-cli ping` 返回 PONG
- [ ] `dir` 配置指向 `/data/redis`
- [ ] 数据文件存在于 `/data/redis/`
- [ ] 重启容器后数据仍然存在
- [ ] 从其他内网机器可以连通 `redis-01:6379`
- [ ] 密码认证生效

---

## 5. mysql-01 部署

### 5.1 PVE 创建参数

| 参数 | 值 |
|------|-----|
| CT ID | 202 |
| hostname | mysql-01 |
| 无特权 | 是 |
| 嵌套 | 否 |
| 模板 | Debian 12 |
| rootfs 大小 | 8 GiB |
| mp0 大小 | 30 GiB |
| mp0 路径 | `/data/mysql` |
| mp0 备份 | 勾选 |
| vCPU | 2 |
| 内存 | 2048 MB |
| IP | 静态，如 `192.168.1.202/24` |

### 5.2 安装 MySQL

```bash
# 安装 MariaDB（Debian 12 官方源，兼容 MySQL 协议）
apt update && apt install -y mariadb-server mariadb-client

# 确认版本
mariadb --version
```

> **说明**：Debian 12 官方源提供的是 MariaDB。若需要原版 MySQL，需配置 MySQL 官方 APT 源。  
> 对 homelab 而言，MariaDB 完全兼容且维护更活跃，推荐直接使用 MariaDB。

### 5.3 配置数据目录

这是关键步骤，将 MariaDB 数据目录迁移到 `/data/mysql`：

```bash
# 停止 MariaDB
systemctl stop mariadb

# 确认挂载点就绪
ls -ld /data/mysql
df -h /data/mysql

# 将初始化的数据目录迁移到 /data/mysql
# （首次安装后 /var/lib/mysql 已由 mysql_install_db 初始化）
rsync -av /var/lib/mysql/ /data/mysql/

# 确认迁移完成
ls -lh /data/mysql/

# 修正权限
chown -R mysql:mysql /data/mysql
chmod 750 /data/mysql
```

### 5.4 修改 MariaDB 配置

编辑 `/etc/mysql/mariadb.conf.d/50-server.cnf`：

```ini
[mysqld]
# 数据目录（必改）
datadir = /data/mysql

# 网络绑定（允许局域网访问）
bind-address = 0.0.0.0

# 字符集
character-set-server = utf8mb4
collation-server     = utf8mb4_unicode_ci

# InnoDB 缓冲池（内存的 50–70%，此处按 2 GiB 内存配置）
innodb_buffer_pool_size = 1G

# 日志（可选，方便排查）
slow_query_log       = 1
slow_query_log_file  = /var/log/mysql/slow.log
long_query_time      = 2

# 二进制日志（开启后便于备份和主从复制）
log_bin              = /data/mysql/mysql-bin
binlog_expire_logs_seconds = 604800
```

同时更新 AppArmor 配置（如果启用），允许访问新数据目录：

```bash
# 检查是否有 AppArmor 规则限制 MySQL
ls /etc/apparmor.d/ | grep mysql

# 如果存在，编辑对应文件，添加新路径权限
# 例如编辑 /etc/apparmor.d/usr.sbin.mariadbd（如有）
# 添加：/data/mysql/ r, /data/mysql/** rwk,

# 重载 AppArmor（如有修改）
# apparmor_parser -r /etc/apparmor.d/usr.sbin.mariadbd
```

### 5.5 启动并验证

```bash
# 启动 MariaDB
systemctl start mariadb
systemctl enable mariadb

# 检查服务状态
systemctl status mariadb

# 如果启动失败，查看日志
journalctl -u mariadb -n 50 --no-pager

# 验证数据目录
mysql -e "SHOW VARIABLES LIKE 'datadir';"
# 期望输出：/data/mysql/

# 安全初始化（设置 root 密码、删除测试库等）
mysql_secure_installation
```

`mysql_secure_installation` 交互流程建议：
- Set root password: **yes**，设置强密码
- Remove anonymous users: **yes**
- Disallow root login remotely: **yes**（root 只允许本地登录）
- Remove test database: **yes**
- Reload privilege tables: **yes**

### 5.6 创建业务账号

```bash
# 登录 MariaDB
mariadb -u root -p

-- 创建业务用账号（替换 myapp / mypassword / mydb 为实际值）
CREATE USER 'myapp'@'%' IDENTIFIED BY 'mypassword';
CREATE DATABASE IF NOT EXISTS mydb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON mydb.* TO 'myapp'@'%';
FLUSH PRIVILEGES;

-- 验证
SELECT user, host FROM mysql.user;
SHOW GRANTS FOR 'myapp'@'%';
EXIT;
```

### 5.7 备份脚本

在 mysql-01 容器内创建备份脚本：

```bash
cat > /usr/local/bin/mysql-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/data/mysql/backups"
DATE=$(date +%Y%m%d_%H%M%S)
MYSQL_USER="root"
MYSQL_PASSWORD="your_root_password"

mkdir -p "$BACKUP_DIR"

# 备份所有数据库
mariadb-dump -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  > "$BACKUP_DIR/all_databases_$DATE.sql"

# 压缩
gzip "$BACKUP_DIR/all_databases_$DATE.sql"

# 保留最近 7 天备份
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "[$(date)] Backup completed: all_databases_$DATE.sql.gz"
EOF

chmod +x /usr/local/bin/mysql-backup.sh

# 配置定时任务（每天凌晨 3 点执行）
echo "0 3 * * * root /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1" \
  > /etc/cron.d/mysql-backup
```

### 5.8 重启验证

```bash
# 重启 MariaDB 服务
systemctl restart mariadb
systemctl status mariadb

# 验证数据目录配置持久化
mysql -e "SHOW VARIABLES LIKE 'datadir';"

# 验证已创建的库还在
mariadb -u root -p -e "SHOW DATABASES;"
```

### 5.9 验收清单

- [ ] `systemctl status mariadb` 显示 active (running)
- [ ] `SHOW VARIABLES LIKE 'datadir'` 输出 `/data/mysql/`
- [ ] 数据文件存在于 `/data/mysql/`
- [ ] root 密码已设置，匿名用户已删除
- [ ] 业务账号已创建，权限正确
- [ ] 重启容器后服务自动恢复
- [ ] 从其他内网机器可以连通 `mysql-01:3306`（使用业务账号）
- [ ] 备份脚本可执行，能产生备份文件
- [ ] 至少完成一次：创建测试库 → 写入数据 → 重启 → 验证数据保留

---

## 6. minio-01 部署（参考）

### 6.1 PVE 创建参数

| 参数 | 值 |
|------|-----|
| CT ID | 203 |
| hostname | minio-01 |
| 无特权 | 是 |
| 嵌套 | 否 |
| 模板 | Debian 12 |
| rootfs 大小 | 8 GiB |
| mp0 大小 | 100 GiB+ |
| mp0 路径 | `/data/minio` |
| mp0 备份 | 勾选 |
| vCPU | 2 |
| 内存 | 2048 MB |
| IP | 静态，如 `192.168.1.203/24` |

### 6.2 安装 MinIO（二进制方式）

```bash
# 下载 MinIO 二进制
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

# 创建 MinIO 用户
useradd -r -s /bin/false minio-user

# 设置数据目录权限
chown -R minio-user:minio-user /data/minio
chmod 750 /data/minio
```

### 6.3 配置 MinIO systemd 服务

```bash
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/minio/linux/index.html
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_OPTS
Restart=always
RestartSec=5
LimitNOFILE=65536
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/default/minio << 'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=your_strong_password_here
MINIO_OPTS="--address :9000 --console-address :9001 /data/minio"
EOF

systemctl daemon-reload
systemctl enable --now minio
```

### 6.4 验收清单

- [ ] MinIO 控制台可访问：`http://minio-01:9001`
- [ ] 数据目录在 `/data/minio`
- [ ] 创建测试 bucket 并完成上传 / 下载验证
- [ ] 重启后服务自动恢复

---

## 7. gitea-01 部署（参考）

### 7.1 PVE 创建参数

| 参数 | 值 |
|------|-----|
| CT ID | 204 |
| hostname | gitea-01 |
| 无特权 | 是 |
| 嵌套 | 否 |
| 模板 | Debian 12 |
| rootfs 大小 | 8 GiB |
| mp0 大小 | 20 GiB |
| mp0 路径 | `/data/gitea` |
| mp0 备份 | 勾选 |
| vCPU | 2 |
| 内存 | 1024 MB |
| IP | 静态，如 `192.168.1.204/24` |

### 7.2 安装 Gitea（二进制方式）

```bash
# 安装依赖
apt update && apt install -y git sqlite3

# 创建 Gitea 用户
adduser --system --shell /bin/bash --gecos 'Gitea' --group --disabled-password --home /home/git git

# 创建目录结构
mkdir -p /data/gitea/{repositories,custom,data,log}
chown -R git:git /data/gitea
chmod 750 /data/gitea

mkdir -p /etc/gitea
touch /etc/gitea/app.ini
chown -R root:git /etc/gitea
chmod 770 /etc/gitea

# 下载 Gitea 二进制（按需替换版本号）
GITEA_VERSION="1.22.3"
wget "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64" \
  -O /usr/local/bin/gitea
chmod +x /usr/local/bin/gitea
```

### 7.3 配置 Gitea systemd 服务

```bash
cat > /etc/systemd/system/gitea.service << 'EOF'
[Unit]
Description=Gitea
After=syslog.target
After=network.target

[Service]
RestartSec=2s
Type=simple
User=git
Group=git
WorkingDirectory=/data/gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/data/gitea

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now gitea
```

### 7.4 验收清单

- [ ] Web 界面可访问：`http://gitea-01:3000`
- [ ] 完成首次 Web 安装向导（数据目录填 `/data/gitea`）
- [ ] SSH clone 可用
- [ ] 仓库创建正常
- [ ] 重启后服务自动恢复

---

## 8. 常见问题与排查

### 8.1 无特权 LXC 数据目录权限问题

**现象**：服务启动失败，日志报数据目录无法写入。

**原因**：无特权 LXC 存在 UID/GID 映射，容器内的 `mysql`（UID 999）在宿主机视角是不同的 UID。

**排查步骤**：

```bash
# 在容器内查看目录属主
ls -ld /data/<service>

# 查看服务进程用户
ps aux | grep <service>

# 如果权限不对，修正
chown -R <service-user>:<service-group> /data/<service>
chmod 750 /data/<service>
```

**如果在容器内修正无效**，说明挂载卷底层有权限问题，可在宿主机 PVE Shell 中：

```bash
# 查找 LXC 对应的挂载卷路径
# 通常在 /var/lib/lxc/<CTID>/rootfs/ 或存储池对应路径
# 找到对应目录，在宿主机上修正权限
```

### 8.2 Redis 启动后无法写入数据目录

```bash
# 检查 Redis 配置中的 dir
grep '^dir' /etc/redis/redis.conf

# 手动测试写权限
sudo -u redis touch /data/redis/test_write && echo "OK" || echo "FAIL"
rm -f /data/redis/test_write
```

### 8.3 MariaDB 启动失败

```bash
# 查看详细日志
journalctl -u mariadb -n 100 --no-pager

# 常见原因
# 1. /data/mysql 属主不是 mysql:mysql
#    解决：chown -R mysql:mysql /data/mysql

# 2. AppArmor 限制（Debian 12 上不常见但可能出现）
#    解决：检查 /etc/apparmor.d/ 中 MySQL 相关规则

# 3. 配置文件语法错误
#    解决：mysqld --print-defaults 检查配置
```

### 8.4 从其他机器无法连接

**Redis**：
```bash
# 检查 bind 配置
grep '^bind' /etc/redis/redis.conf
# 确保为 bind 0.0.0.0

# 检查防火墙
iptables -L INPUT -n | grep 6379
```

**MySQL**：
```bash
# 检查 bind-address
grep 'bind-address' /etc/mysql/mariadb.conf.d/50-server.cnf
# 确保为 bind-address = 0.0.0.0

# 检查用户远程权限
mariadb -u root -p -e "SELECT user, host FROM mysql.user;"
# 确保业务用户的 host 为 % 或具体 IP

# 检查监听
ss -tlnp | grep 3306
```
