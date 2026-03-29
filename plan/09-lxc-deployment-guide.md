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
apt update && apt install -y redis-server

# 确认安装版本
redis-server --version
```

### 4.3 配置数据目录

```bash
# 停止 Redis 服务
systemctl stop redis-server

# 检查挂载点
ls -ld /data/redis
df -h /data/redis

# 设置目录权限
chown -R redis:redis /data/redis
chmod 750 /data/redis
```

### 4.4 修改 Redis 配置

编辑 `/etc/redis/redis.conf`，确认以下配置项：

```ini
# 数据目录（必改）
dir /data/redis

# 持久化策略 - RDB + AOF 双重保障
save 900 1
save 300 10
save 60 10000

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# 绑定地址（仅局域网访问）
bind 0.0.0.0

# 密码（强烈建议设置）
requirepass your_strong_password_here

# 日志文件
logfile /var/log/redis/redis-server.log
```

```bash
# 快速修改数据目录
sed -i 's|^dir .*|dir /data/redis|' /etc/redis/redis.conf

# 验证修改
grep '^dir' /etc/redis/redis.conf
```

### 4.5 启动并验证

```bash
systemctl restart redis-server
systemctl enable redis-server
systemctl status redis-server

# 检查监听端口
ss -tlnp | grep 6379

# 连接测试
redis-cli -a your_strong_password_here ping
# 期望输出：PONG

# 写入测试数据
redis-cli -a your_strong_password_here SET test_key "hello"
redis-cli -a your_strong_password_here GET test_key
# 期望输出：hello

# 确认数据文件目录
ls -lh /data/redis/
```

### 4.6 验收清单

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
apt update && apt install -y mariadb-server mariadb-client

# 确认版本
mariadb --version
```

> **说明**：Debian 12 官方源提供的是 MariaDB，完全兼容 MySQL 协议。  
> 若需要原版 MySQL 8，需配置 MySQL 官方 APT 源（见下方说明）。

<details>
<summary>安装原版 MySQL 8（可选）</summary>

```bash
# 添加 MySQL 官方 APT 源
wget https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
dpkg -i mysql-apt-config_0.8.29-1_all.deb
apt update
apt install -y mysql-server

# 配置文件路径：/etc/mysql/mysql.conf.d/mysqld.cnf
# 数据目录修改方式与 MariaDB 相同
```
</details>

### 5.3 配置数据目录

```bash
# 停止 MariaDB
systemctl stop mariadb

# 确认挂载点就绪
ls -ld /data/mysql
df -h /data/mysql

# 将初始数据迁移到 /data/mysql
rsync -av /var/lib/mysql/ /data/mysql/

# 验证迁移
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

# 慢查询日志（方便排查）
slow_query_log       = 1
slow_query_log_file  = /var/log/mysql/slow.log
long_query_time      = 2
```

### 5.5 启动并验证

```bash
systemctl start mariadb
systemctl enable mariadb
systemctl status mariadb

# 如果启动失败，查看日志
journalctl -u mariadb -n 50 --no-pager

# 验证数据目录
mysql -e "SHOW VARIABLES LIKE 'datadir';"
# 期望输出：/data/mysql/

# 安全初始化
mysql_secure_installation
```

`mysql_secure_installation` 建议选项：
- 设置 root 密码：**是**
- 删除匿名用户：**是**
- 禁止 root 远程登录：**是**
- 删除测试数据库：**是**
- 刷新权限：**是**

### 5.6 创建业务账号

```bash
mariadb -u root -p

-- 创建业务账号（替换 myapp / mypassword / mydb）
CREATE USER 'myapp'@'%' IDENTIFIED BY 'mypassword';
CREATE DATABASE IF NOT EXISTS mydb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
GRANT ALL PRIVILEGES ON mydb.* TO 'myapp'@'%';
FLUSH PRIVILEGES;

SELECT user, host FROM mysql.user;
EXIT;
```

### 5.7 备份脚本

```bash
# 创建认证配置文件（避免密码出现在进程列表中）
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

mariadb-dump --defaults-file=/root/.my.cnf \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  > "$BACKUP_DIR/all_databases_$DATE.sql"

gzip "$BACKUP_DIR/all_databases_$DATE.sql"
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete

echo "[$(date)] Backup completed: all_databases_$DATE.sql.gz"
EOF

chmod +x /usr/local/bin/mysql-backup.sh

# 配置定时任务
echo "0 3 * * * root /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1" \
  > /etc/cron.d/mysql-backup
```

### 5.8 验收清单

- [ ] `systemctl status mariadb` 显示 active (running)
- [ ] `SHOW VARIABLES LIKE 'datadir'` 输出 `/data/mysql/`
- [ ] 数据文件存在于 `/data/mysql/`
- [ ] root 密码已设置，匿名用户已删除
- [ ] 业务账号已创建，权限正确
- [ ] 重启容器后服务自动恢复
- [ ] 从其他内网机器可以连通 `mysql-01:3306`
- [ ] 备份脚本可执行，能产生备份文件
- [ ] 完成一次：创建测试库 → 写入数据 → 重启 → 验证数据保留

---

## 6. minio-01 部署（参考）

### 6.1 PVE 创建参数

| 参数 | 值 |
|------|-----|
| CT ID | 203 |
| hostname | minio-01 |
| 无特权 | 是 |
| 嵌套 | 否 |
| rootfs 大小 | 8 GiB |
| mp0 大小 | 100 GiB+ |
| mp0 路径 | `/data/minio` |
| vCPU | 2 |
| 内存 | 2048 MB |
| IP | 静态，如 `192.168.1.203/24` |

### 6.2 安装 MinIO

```bash
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio
chmod +x /usr/local/bin/minio

useradd -r -s /bin/false minio-user
chown -R minio-user:minio-user /data/minio
chmod 750 /data/minio

cat > /etc/default/minio << 'EOF'
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=your_strong_password_here
MINIO_OPTS="--address :9000 --console-address :9001 /data/minio"
EOF

cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
Wants=network-online.target
After=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/default/minio
ExecStart=/usr/local/bin/minio server $MINIO_OPTS
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now minio
```

### 6.3 验收清单

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
| rootfs 大小 | 8 GiB |
| mp0 大小 | 20 GiB |
| mp0 路径 | `/data/gitea` |
| vCPU | 2 |
| 内存 | 1024 MB |
| IP | 静态，如 `192.168.1.204/24` |

### 7.2 安装 Gitea

```bash
apt update && apt install -y git sqlite3

adduser --system --shell /bin/bash --gecos 'Gitea' --group --disabled-password --home /home/git git

mkdir -p /data/gitea/{repositories,custom,data,log}
chown -R git:git /data/gitea
chmod 750 /data/gitea

mkdir -p /etc/gitea
touch /etc/gitea/app.ini
chown -R root:git /etc/gitea
chmod 770 /etc/gitea

# 下载最新稳定版（按需替换版本号）
GITEA_VERSION="1.22.3"
wget "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64" \
  -O /usr/local/bin/gitea
chmod +x /usr/local/bin/gitea

cat > /etc/systemd/system/gitea.service << 'EOF'
[Unit]
Description=Gitea
After=syslog.target network.target

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

### 7.3 验收清单

- [ ] Web 界面可访问：`http://gitea-01:3000`
- [ ] 完成首次 Web 安装向导（数据目录填 `/data/gitea`）
- [ ] SSH clone 可用
- [ ] 仓库创建正常
- [ ] 重启后服务自动恢复

---

## 8. 常见问题与排查

### 8.1 无特权 LXC 数据目录权限问题

**现象**：服务启动失败，日志报数据目录无法写入。

```bash
# 容器内检查目录属主
ls -ld /data/<service>

# 修正权限
chown -R <service-user>:<service-group> /data/<service>
chmod 750 /data/<service>
```

### 8.2 Redis 启动后无法写入数据目录

```bash
grep '^dir' /etc/redis/redis.conf
sudo -u redis touch /data/redis/test_write && echo "OK" || echo "FAIL"
rm -f /data/redis/test_write
```

### 8.3 MariaDB 启动失败

```bash
journalctl -u mariadb -n 100 --no-pager

# 常见原因
# 1. /data/mysql 属主不是 mysql:mysql
chown -R mysql:mysql /data/mysql

# 2. 配置文件语法错误
mysqld --print-defaults
```

### 8.4 从其他机器无法连接

**Redis**：
```bash
grep '^bind' /etc/redis/redis.conf  # 确保为 0.0.0.0
ss -lntp | grep 6379
```

**MySQL**：
```bash
grep 'bind-address' /etc/mysql/mariadb.conf.d/50-server.cnf  # 确保为 0.0.0.0
ss -tlnp | grep 3306
mariadb -u root -p -e "SELECT user, host FROM mysql.user;"
```
