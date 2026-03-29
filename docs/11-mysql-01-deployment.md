# MySQL 部署手册（mysql-01）

本文档描述在 Proxmox VE 无特权 LXC 容器中部署 **MySQL**（使用官方 MySQL Community Server）的完整流程，数据目录统一使用 `/data/mysql`。

> **说明：本文档使用直接安装 MySQL Community Server，而非 MariaDB。**
> 如果你的场景对 MySQL 兼容性有严格要求，或希望使用官方 MySQL 生态（如 MySQL Shell、MySQL Router），请使用本文档。
> 如果你对两者无特殊需求，MySQL Community Server 和 MariaDB 在功能上高度兼容，本文档的配置流程同样适用。

---

## 一、LXC 创建参数

| 参数 | 推荐值 |
|------|--------|
| CT ID | `202` |
| hostname | `mysql-01` |
| 模板 | Debian 12 |
| 无特权 | **是** |
| 嵌套 | **否** |
| CPU | 2 vCPU |
| 内存 | 4096 MB |
| rootfs 大小 | 8–16 GB |
| mp0 大小 | 30 GB（起步） |
| mp0 路径（容器内） | `/data/mysql` |
| mp0 备份 | **勾选** |
| 开机自启 | **是** |

---

## 二、基础初始化

进入容器后执行：

```bash
# 验证挂载点和主机名
hostname
ip a
df -h
ls -ld /data/mysql

# 更新系统并安装依赖工具
apt update && apt upgrade -y
apt install -y curl gnupg lsb-release vim bash-completion
```

---

## 三、安装 MySQL Community Server

Debian 12 的官方仓库默认提供 MariaDB，若要安装 MySQL Community Server，需使用 MySQL 官方 APT 仓库。

### 3.1 添加 MySQL 官方 APT 仓库

```bash
# 下载 MySQL APT 配置包
curl -fsSL https://dev.mysql.com/get/mysql-apt-config_0.8.30-1_all.deb -o /tmp/mysql-apt-config.deb

# 安装配置包（选择 MySQL 8.0 或 8.4 LTS）
dpkg -i /tmp/mysql-apt-config.deb

# 更新软件包列表
apt update
```

> 安装配置包时会弹出交互菜单，选择 **MySQL 8.0** 或 **MySQL 8.4 LTS**，然后选择 OK 确认。

### 3.2 安装 MySQL Server

```bash
apt install -y mysql-server
```

安装过程中可能提示设置 root 密码，建议在此步骤设置强密码。

---

## 四、数据目录迁移到 `/data/mysql`

MySQL 默认数据目录为 `/var/lib/mysql`，需迁移到 `/data/mysql`。

### 4.1 停止 MySQL 服务

```bash
systemctl stop mysql
```

### 4.2 迁移数据

```bash
# 确认数据目录存在
ls -ld /data/mysql

# 将默认数据目录内容迁移到 /data/mysql
rsync -av /var/lib/mysql/ /data/mysql/

# 验证迁移结果
ls -lah /data/mysql
```

### 4.3 修正目录权限

```bash
# 将数据目录属主改为 mysql 用户
chown -R mysql:mysql /data/mysql
chmod 750 /data/mysql

# 验证
ls -ld /data/mysql
```

### 4.4 修改 MySQL 配置文件

编辑 `/etc/mysql/mysql.conf.d/mysqld.cnf`（或 `/etc/mysql/my.cnf`）：

```bash
vim /etc/mysql/mysql.conf.d/mysqld.cnf
```

修改或添加以下内容：

```ini
[mysqld]
# 数据目录（统一使用 /data/mysql）
datadir = /data/mysql

# 监听地址（内网访问使用内网 IP 或 0.0.0.0）
bind-address = 0.0.0.0

# 字符集
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# 时区
default-time-zone = '+08:00'

# 日志
general_log = 0
slow_query_log = 1
slow_query_log_file = /data/mysql/mysql-slow.log
long_query_time = 2
```

### 4.5 更新 AppArmor 配置（如适用）

如果系统启用了 AppArmor，需允许 MySQL 访问新数据目录：

```bash
# 检查 AppArmor 状态
aa-status 2>/dev/null | grep mysql || echo "AppArmor not active or mysql not confined"

# 如果 mysql 受 AppArmor 约束，编辑配置
vim /etc/apparmor.d/usr.sbin.mysqld
# 添加或修改：
#   /data/mysql/ r,
#   /data/mysql/** rwk,

# 重载 AppArmor 配置
systemctl reload apparmor
```

---

## 五、启动并验证

```bash
# 启动 MySQL
systemctl start mysql
systemctl status mysql --no-pager

# 设置开机自启
systemctl enable mysql
```

---

## 六、初始化安全配置

```bash
# 运行安全初始化向导
mysql_secure_installation
```

建议操作：
- 设置 root 密码（若安装时未设置）
- 删除匿名用户
- 禁止 root 远程登录
- 删除测试数据库
- 刷新权限

---

## 七、创建业务账号

```bash
# 登录 MySQL
mysql -u root -p

# 创建业务数据库
CREATE DATABASE app_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

# 创建业务账号（替换 app_user 和密码）
CREATE USER 'app_user'@'%' IDENTIFIED BY '<your-strong-password>';

# 授权
GRANT ALL PRIVILEGES ON app_db.* TO 'app_user'@'%';
FLUSH PRIVILEGES;

# 退出
EXIT;
```

---

## 八、验收检查

### 8.1 服务状态

```bash
systemctl status mysql --no-pager
```

### 8.2 数据目录验证

```bash
ls -lah /data/mysql
# 预期看到 ibdata1、mysql/ 等 InnoDB 系统文件和系统库
```

### 8.3 本地连通性

```bash
mysql -u root -p -e "SHOW DATABASES;"
mysql -u root -p -e "SELECT @@datadir;"
# 预期返回：/data/mysql/
```

### 8.4 内网远程连通性

从另一台机器测试：

```bash
mysql -h <mysql-01-ip> -u app_user -p app_db -e "SHOW TABLES;"
```

### 8.5 容器重启验证

从 PVE 重启容器后，确认：
- MySQL 服务自动启动
- `/data/mysql` 数据完整
- 业务账号可正常连接

---

## 九、常见问题排查

```bash
# 查看 MySQL 日志
journalctl -u mysql -n 100 --no-pager
tail -n 50 /var/log/mysql/error.log

# 检查目录权限
ls -ld /data/mysql
id mysql

# 检查进程
ps aux | grep mysql
ss -lntp | grep 3306
```

### 启动失败常见原因

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| Permission denied | 目录属主不对 | `chown -R mysql:mysql /data/mysql` |
| InnoDB: Unable to lock | 数据目录未正确迁移 | 检查 `datadir` 配置与实际目录是否一致 |
| AppArmor denial | AppArmor 限制 | 更新 AppArmor 配置，见第四节 |
| Access denied for root | root 密码不对 | 参考 MySQL 重置 root 密码流程 |

---

## 十、安全建议

- Root 账号仅允许本地登录（`localhost`）
- 业务服务使用最小权限专用账号
- 不直接暴露 3306 端口到公网
- 如需远程管理，通过 VPN 或 SSH 隧道访问
- 定期检查 PVE 备份任务是否正常运行
- 建议定期通过 `mysqldump` 做逻辑备份作为额外保险
