# MySQL 安装、配置与数据目录设置

> 容器：`mysql-01`（CT ID 201，无特权 LXC）  
> 数据目录：`/data/mysql`（通过 PVE mp0 挂载）

---

## 前置条件

- 已按 `02-lxc-infrastructure.md` 创建 LXC 并完成基础初始化
- mp0 已挂载到容器内 `/data/mysql`
- 容器已启动，可正常登录

---

## 一、安装 MariaDB（推荐）

```bash
# 安装 MariaDB Server
apt install -y mariadb-server

# 确认版本
mariadb --version
```

> 也可安装 MySQL Server，命令改为 `apt install -y mysql-server`。

---

## 二、配置数据目录为 `/data/mysql`

### 2.1 停止 MariaDB 服务

```bash
systemctl stop mariadb
```

### 2.2 修正数据目录属主

```bash
# 确认 mysql 用户的 UID/GID
id mysql

# 修正 /data/mysql 目录属主
chown -R mysql:mysql /data/mysql
chmod 750 /data/mysql
ls -ld /data/mysql
```

### 2.3 修改 MariaDB 配置文件

```bash
vim /etc/mysql/mariadb.conf.d/50-server.cnf
```

找到并修改 `datadir`：

```ini
[mysqld]
datadir = /data/mysql
```

### 2.4 处理 AppArmor（Debian/Ubuntu）

```bash
# 编辑 AppArmor 配置，允许新数据目录
vim /etc/apparmor.d/usr.sbin.mysqld
```

在 `/var/lib/mysql` 相关行附近添加：

```
/data/mysql/ r,
/data/mysql/** rwk,
```

重载 AppArmor：

```bash
systemctl reload apparmor
```

### 2.5 初始化新数据目录

```bash
# 初始化 MariaDB 数据目录
mysql_install_db --user=mysql --basedir=/usr --datadir=/data/mysql
```

---

## 三、启动并安全初始化

```bash
# 启动 MariaDB
systemctl start mariadb
systemctl enable mariadb

# 运行安全初始化向导
mysql_secure_installation
```

安全初始化建议：
- 设置 root 密码
- 移除匿名用户
- 禁止 root 远程登录
- 删除测试数据库

---

## 四、验证数据目录

```bash
# 确认数据目录已生效
mysql -u root -p -e "SHOW VARIABLES LIKE 'datadir';"
```

预期输出：

```
+---------------+-------------+
| Variable_name | Value       |
+---------------+-------------+
| datadir       | /data/mysql/|
+---------------+-------------+
```

---

## 五、创建业务用户与数据库

```bash
mysql -u root -p
```

```sql
-- 创建业务数据库
CREATE DATABASE myapp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- 创建业务用户（限内网访问）
CREATE USER 'myapp'@'192.168.1.%' IDENTIFIED BY '强密码';
GRANT ALL PRIVILEGES ON myapp.* TO 'myapp'@'192.168.1.%';
FLUSH PRIVILEGES;
```

---

## 六、优化配置建议

编辑 `/etc/mysql/mariadb.conf.d/50-server.cnf`：

```ini
[mysqld]
# 数据目录
datadir = /data/mysql

# 网络（允许内网访问）
bind-address = 0.0.0.0
port = 3306

# 字符集
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# InnoDB 缓冲池（建议设为内存的 50-70%）
innodb_buffer_pool_size = 2G

# 慢查询日志
slow_query_log = 1
slow_query_log_file = /data/mysql/mysql-slow.log
long_query_time = 2

# 最大连接数
max_connections = 200
```

重启使配置生效：

```bash
systemctl restart mariadb
```

---

## 七、配置备份脚本

```bash
# 创建备份目录（宿主机上或容器内均可）
mkdir -p /data/mysql/backups

# 创建简单备份脚本
cat > /usr/local/bin/mysql-backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/data/mysql/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mysqldump -u root -p"你的root密码" --all-databases | gzip > "$BACKUP_DIR/all-$DATE.sql.gz"
# 保留最近 7 天备份
find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
EOF

chmod +x /usr/local/bin/mysql-backup.sh

# 添加定时任务（每天凌晨 2 点备份）
echo "0 2 * * * root /usr/local/bin/mysql-backup.sh" >> /etc/cron.d/mysql-backup
```

---

## 八、验收检查

```bash
# 1. 服务状态
systemctl status mariadb

# 2. 数据目录确认
mysql -u root -p -e "SHOW VARIABLES LIKE 'datadir';"

# 3. 内网连通性（在其他主机上测试）
mysql -h 192.168.1.201 -u myapp -p myapp -e "SELECT 1;"

# 4. 重启后验证
pct reboot 201
# 等待启动后再次确认服务状态
```
