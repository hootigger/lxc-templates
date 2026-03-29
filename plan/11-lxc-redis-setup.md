# 11 — Redis LXC 安装与配置手册

> 容器名：`redis-01`  
> 数据目录：`/data/redis`（通过 PVE `mp0` 挂载）  
> 系统模板：Debian 12

---

## 1. PVE 容器创建参数

| 参数 | 值 |
|---|---|
| CT ID | 202 |
| Hostname | `redis-01` |
| 无特权容器 | **是** |
| 嵌套 | **否** |
| rootfs 大小 | 8 GiB |
| mp0 存储 | 选择业务数据存储池 |
| mp0 大小 | 8 GiB（可按持久化需求调整） |
| mp0 路径（容器内） | `/data/redis` |
| mp0 备份 | **勾选** |
| vCPU | 1 |
| 内存 | 1024 MiB |
| Swap | 256 MiB |
| 网络 | 固定 IP，如 `192.168.1.202/24` |
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
ls -ld /data/redis
# 预期输出：drwxr-xr-x ... /data/redis
```

---

## 3. 安装 Redis

```bash
apt install -y redis-server

# 查看服务状态
systemctl status redis-server

# 设置开机自启
systemctl enable redis-server
```

---

## 4. 配置数据目录为 `/data/redis`

Redis 默认数据目录为 `/var/lib/redis`，需将其指向 `/data/redis`。

### 4.1 停止 Redis 服务

```bash
systemctl stop redis-server
```

### 4.2 配置目录权限

```bash
# 确认挂载目录存在
ls -ld /data/redis

# 赋予 redis 用户所有权
chown -R redis:redis /data/redis
chmod 750 /data/redis
```

### 4.3 修改 Redis 配置

编辑 `/etc/redis/redis.conf`：

```bash
vim /etc/redis/redis.conf
```

找到并修改以下配置项：

```conf
# 数据目录（统一规范：/data/redis）
dir /data/redis

# 绑定地址：监听所有接口（配合访问控制）
bind 0.0.0.0

# 关闭保护模式（已通过密码和绑定 IP 控制访问）
protected-mode no

# 设置访问密码（强密码，8位以上含大小写数字符号）
requirepass 你的强密码

# 持久化配置（推荐 RDB + AOF 双重保障）
# RDB 快照策略
save 900 1
save 300 10
save 60 10000

# AOF 持久化
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec

# 日志配置
loglevel notice
logfile /var/log/redis/redis-server.log

# 最大内存（建议设置为容器内存的 60~70%，留系统余量）
maxmemory 600mb
maxmemory-policy allkeys-lru
```

### 4.4 启动 Redis 并验证

```bash
systemctl start redis-server
systemctl status redis-server

# 确认数据目录
redis-cli -a '你的强密码' CONFIG GET dir
# 预期输出：dir -> /data/redis

# 查看持久化配置
redis-cli -a '你的强密码' CONFIG GET appendonly
# 预期输出：appendonly -> yes
```

---

## 5. 内核参数优化

Redis 在 overcommit memory 警告下性能不稳，建议在**宿主机（PVE）**执行：

```bash
# 在 PVE 宿主机上执行
echo "vm.overcommit_memory = 1" >> /etc/sysctl.conf
sysctl -p
```

> **注意**：这是宿主机级别参数，在 LXC 容器内修改无效，需登录 PVE 宿主机操作。

---

## 6. 连接测试

### 6.1 容器内测试

```bash
# 使用密码连接
redis-cli -a '你的强密码'

# 测试基本操作
127.0.0.1:6379> PING
# PONG
127.0.0.1:6379> SET test "hello"
# OK
127.0.0.1:6379> GET test
# "hello"
127.0.0.1:6379> DEL test
127.0.0.1:6379> EXIT
```

### 6.2 从内网其他主机连接测试

```bash
# 在 docker-01 或其他内网机器上测试
redis-cli -h 192.168.1.202 -p 6379 -a '你的强密码' PING
# 预期输出：PONG
```

---

## 7. 持久化验证

验证 RDB 和 AOF 文件是否正确生成：

```bash
# 进入 Redis CLI
redis-cli -a '你的强密码'

# 手动触发快照
127.0.0.1:6379> BGSAVE
# Background saving started

# 退出后查看文件
exit
ls -la /data/redis/
# 预期：dump.rdb 和 appendonly.aof 均存在
```

---

## 8. 重启持久化验证

```bash
# 写入测试数据
redis-cli -a '你的强密码' SET persist_test "data_survives_restart"

# 重启容器（在 PVE 中重启，或）
systemctl restart redis-server

# 验证数据是否保留
redis-cli -a '你的强密码' GET persist_test
# 预期输出："data_survives_restart"
```

---

## 9. 备份配置

### 9.1 简单定期备份脚本

创建 `/usr/local/bin/redis-backup.sh`：

```bash
#!/bin/bash
BACKUP_DIR="/data/redis-backup"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR"

# 从配置文件读取密码，避免密码出现在命令行或进程列表
REDIS_PASS=$(grep -Po '(?<=^requirepass ).*' /etc/redis/redis.conf | tr -d '[:space:]')

# 触发 RDB 快照
REDISCLI_AUTH="$REDIS_PASS" redis-cli BGSAVE
sleep 3

# 复制 RDB 文件
cp /data/redis/dump.rdb "$BACKUP_DIR/dump_${DATE}.rdb"

# 复制 AOF 文件（如存在）
[ -f /data/redis/appendonly.aof ] && \
  cp /data/redis/appendonly.aof "$BACKUP_DIR/appendonly_${DATE}.aof"

# 保留最近 7 天
find "$BACKUP_DIR" -name "*.rdb" -mtime +7 -delete
find "$BACKUP_DIR" -name "*.aof" -mtime +7 -delete

echo "Redis 备份完成：$BACKUP_DIR"
```

```bash
chmod +x /usr/local/bin/redis-backup.sh
```

### 9.2 配置定时任务

```bash
crontab -e
```

添加：

```cron
# 每天凌晨 3 点 30 分执行备份
30 3 * * * /usr/local/bin/redis-backup.sh >> /var/log/redis-backup.log 2>&1
```

---

## 10. 验收清单

- [ ] Redis 服务正常运行：`systemctl status redis-server`
- [ ] 数据目录确认为 `/data/redis`：`redis-cli -a '密码' CONFIG GET dir`
- [ ] 访问密码已设置且生效
- [ ] AOF 持久化已启用：`redis-cli -a '密码' CONFIG GET appendonly`
- [ ] RDB 快照策略已配置
- [ ] 从内网其他主机可正常连接（PING 返回 PONG）
- [ ] 重启后数据保留验证通过
- [ ] 备份脚本可执行，定时任务已配置
- [ ] 容器重启后服务自动恢复：`systemctl enable redis-server`
- [ ] PVE 层 LXC 备份策略已配置

---

## 11. 常见问题

### 启动失败：数据目录权限错误

```bash
# 检查目录属主
ls -la /data/redis

# 修正属主
chown -R redis:redis /data/redis
chmod 750 /data/redis

# 查看详细错误日志
journalctl -u redis-server -n 50
```

### 无法远程连接

```bash
# 确认监听地址
ss -tlnp | grep 6379

# 确认配置中 bind 地址
grep "^bind" /etc/redis/redis.conf
```

### 内存不足警告

```bash
# 查看当前内存使用
redis-cli -a '你的强密码' INFO memory

# 调整 maxmemory 配置后重启
systemctl restart redis-server
```
