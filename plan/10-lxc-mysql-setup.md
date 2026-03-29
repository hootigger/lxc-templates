# 10 — MySQL / MariaDB LXC 安装与配置手册

> 容器名：`mysql-01`  
> 数据目录：`/data/mysql`（通过 PVE `mp0` 挂载）  
> 系统模板：Debian 12

---

## 1. PVE 容器创建参数

| 参数 | 值 |
|---|---|
| CT ID | 201 |
| Hostname | `mysql-01` |
| 无特权容器 | **是** |
| 嵌套 | **否** |
| rootfs 大小 | 16 GiB |
| mp0 存储 | 选择业务数据存储池 |
| mp0 大小 | 30 GiB（可按实际需求扩大） |
| mp0 路径（容器内） | `/data/mysql` |
| mp0 备份 | **勾选** |
| vCPU | 2 |
| 内存 | 2048 MiB |
| Swap | 512 MiB |
| 网络 | 固定 IP，如 `192.168.1.201/24` |
| DNS | 局域网 DNS 或 `223.5.5.5` |

---

## 2. 容器初始化

容器创建并启动后，登入容器执行以下命令：

```bash
# 更新系统软件包
apt update && apt upgrade -y

# 配置时区
timedatectl set-timezone Asia/Shanghai

# 安装常用工具
apt install -y curl wget vim net-tools

# 确认数据目录挂载正常
ls -ld /data/mysql
# 预期输出：drwxr-xr-x ... /data/mysql
```

---

## 3. 安装 MariaDB

```bash
apt install -y mariadb-server

# 查看服务状态
systemctl status mariadb

# 设置开机自启
systemctl enable mariadb
```

---

## 4. 配置数据目录为 `/data/mysql`

MariaDB 默认数据目录为 `/var/lib/mysql`，需将其迁移到 `/data/mysql`。

### 4.1 停止 MariaDB 服务

```bash
systemctl stop mariadb
```

### 4.2 确认默认数据目录内容

```bash
ls -la /var/lib/mysql
```

### 4.3 将数据复制到新目录

```bash
# 确保目标目录存在且权限正确
ls -ld /data/mysql

# 使用 rsync 保留属主和权限进行复制
rsync -av /var/lib/mysql/ /data/mysql/

# 验证复制内容
ls -la /data/mysql
```

### 4.4 修改 MariaDB 配置指向新数据目录

编辑 `/etc/mysql/mariadb.conf.d/50-server.cnf`：

```bash
vim /etc/mysql/mariadb.conf.d/50-server.cnf
```

找到并修改以下行：

```ini
[mysqld]
datadir = /data/mysql
```

### 4.5 处理 AppArmor（如有）

检查是否启用了 AppArmor：

```bash
aa-status 2>/dev/null || echo "AppArmor not active"
```

若 AppArmor 处于活跃状态，编辑 `/etc/apparmor.d/usr.sbin.mysqld`，在相应位置添加：

```
/data/mysql/ r,
/data/mysql/** rwk,
```

然后重新加载：

```bash
apparmor_parser -r /etc/apparmor.d/usr.sbin.mysqld
```

### 4.6 修改目录属主

```bash
chown -R mysql:mysql /data/mysql
chmod 750 /data/mysql
```

### 4.7 启动 MariaDB 并验证

```bash
systemctl start mariadb
systemctl status mariadb

# 确认数据目录已生效
mysql -e "SHOW VARIABLES LIKE 'datadir';"
# 预期输出：/data/mysql/
```

---

## 5. 初始安全配置

```bash
# 运行安全初始化脚本
mysql_secure_installation
```

按提示操作：
- 为 root 用户设置密码
- 删除匿名用户
- 禁止 root 远程登录
- 删除测试数据库
- 刷新权限

---

## 6. 创建业务账号

```bash
mysql -u root -p

-- 创建业务用数据库
CREATE DATABASE app_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建业务账号（仅允许内网访问）
CREATE USER 'appuser'@'192.168.1.%' IDENTIFIED BY '你的强密码';
GRANT ALL PRIVILEGES ON app_db.* TO 'appuser'@'192.168.1.%';

-- 刷新权限
FLUSH PRIVILEGES;
EXIT;
```

---

## 7. 配置远程访问

编辑 `/etc/mysql/mariadb.conf.d/50-server.cnf`，将 `bind-address` 修改为允许内网访问：

```ini
bind-address = 0.0.0.0
```

> **安全提示**：`0.0.0.0` 表示监听所有接口，配合账号级别的 IP 限制（`@'192.168.1.%'`）来控制访问范围。

重启服务：

```bash
systemctl restart mariadb
```

---

## 8. 配置推荐（性能与稳定性）

在 `/etc/mysql/mariadb.conf.d/50-server.cnf` 中添加或调整以下参数：

```ini
[mysqld]
# 数据目录
datadir = /data/mysql

# 字符集
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# InnoDB 缓冲池（建议为容器内存的 50~70%）
innodb_buffer_pool_size = 1G

# 日志文件
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 2

# 最大连接数
max_connections = 200
```

---

## 9. 备份配置

### 9.1 简单定期备份脚本

首先创建 MySQL 选项文件（避免密码出现在命令行或进程列表中）：

```bash
# 创建只有 root 可读的认证配置文件
cat > /root/.my.cnf <<'EOF'
[mysqldump]
user=root
password=你的root密码
EOF
chmod 600 /root/.my.cnf
```

创建 `/usr/local/bin/mysql-backup.sh`：

```bash
#!/bin/bash
BACKUP_DIR="/data/mysql-backup"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# 备份所有数据库（认证信息从 ~/.my.cnf 读取，不暴露在命令行）
mysqldump --defaults-file=/root/.my.cnf --all-databases --single-transaction \
  > "$BACKUP_DIR/all-databases_${DATE}.sql"

# 保留最近 7 天
find "$BACKUP_DIR" -name "*.sql" -mtime +7 -delete

echo "备份完成：$BACKUP_DIR/all-databases_${DATE}.sql"
```

```bash
chmod +x /usr/local/bin/mysql-backup.sh
```

### 9.2 配置定时任务

```bash
crontab -e
```

添加：

```cron
# 每天凌晨 3 点执行备份
0 3 * * * /usr/local/bin/mysql-backup.sh >> /var/log/mysql-backup.log 2>&1
```

---

## 10. 验收清单

- [ ] MariaDB 服务正常运行：`systemctl status mariadb`
- [ ] 数据目录确认为 `/data/mysql`：`mysql -e "SHOW VARIABLES LIKE 'datadir';"`
- [ ] root 密码已设置，安全初始化已完成
- [ ] 业务账号已创建，仅允许内网 IP 访问
- [ ] 远程连接可用（从同网段其他机器测试）
- [ ] 备份脚本可执行，定时任务已配置
- [ ] 容器重启后服务自动恢复：`systemctl enable mariadb`
- [ ] PVE 层 LXC 备份策略已配置

---

## 11. 常见问题

### 启动失败：数据目录权限错误

```bash
# 检查目录属主
ls -la /data/mysql

# 修正属主
chown -R mysql:mysql /data/mysql
chmod 750 /data/mysql

# 重启服务
systemctl restart mariadb
journalctl -u mariadb -n 50
```

### 无法远程连接

```bash
# 确认监听地址
ss -tlnp | grep 3306

# 确认账号权限
mysql -u root -p -e "SELECT user, host FROM mysql.user;"
```
