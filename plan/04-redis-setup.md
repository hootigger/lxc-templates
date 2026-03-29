# Redis 安装、配置与数据目录设置

> 容器：`redis-01`（CT ID 202，无特权 LXC）  
> 数据目录：`/data/redis`（通过 PVE mp0 挂载）

---

## 前置条件

- 已按 `02-lxc-infrastructure.md` 创建 LXC 并完成基础初始化
- mp0 已挂载到容器内 `/data/redis`
- 容器已启动，可正常登录

---

## 一、安装 Redis

```bash
# 安装 Redis
apt install -y redis-server

# 确认版本
redis-server --version
```

---

## 二、配置数据目录为 `/data/redis`

### 2.1 停止 Redis 服务

```bash
systemctl stop redis-server
```

### 2.2 修正数据目录属主

```bash
# 确认 redis 用户的 UID/GID
id redis

# 修正 /data/redis 目录属主
chown -R redis:redis /data/redis
chmod 750 /data/redis
ls -ld /data/redis
```

### 2.3 修改 Redis 配置文件

```bash
vim /etc/redis/redis.conf
```

修改以下关键配置：

```conf
# 数据目录（持久化文件存放位置）
dir /data/redis

# 日志文件（放在数据目录中便于管理）
logfile /data/redis/redis.log

# PID 文件
pidfile /var/run/redis/redis-server.pid
```

---

## 三、配置持久化策略

在 `/etc/redis/redis.conf` 中设置：

```conf
# RDB 持久化（快照）
save 900 1      # 900 秒内有 1 次写操作则保存
save 300 10     # 300 秒内有 10 次写操作则保存
save 60 10000   # 60 秒内有 10000 次写操作则保存
dbfilename dump.rdb

# AOF 持久化（追加日志，推荐开启）
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
```

> **建议同时开启 RDB 和 AOF**，提供双重持久化保障。

---

## 四、安全配置

```conf
# 设置访问密码（必须）
requirepass 你的Redis密码

# 绑定地址（允许内网访问）
bind 0.0.0.0

# 保护模式（设置密码后可关闭保护模式）
protected-mode no

# 最大内存限制（根据分配内存设置，留 10-20% 余量）
maxmemory 1536mb

# 内存淘汰策略（缓存场景推荐 allkeys-lru）
maxmemory-policy allkeys-lru

# 禁用危险命令（生产环境建议）
# rename-command FLUSHALL ""
# rename-command FLUSHDB ""
# rename-command CONFIG ""
```

---

## 五、启动并验证

```bash
# 启动 Redis
systemctl start redis-server
systemctl enable redis-server

# 查看服务状态
systemctl status redis-server

# 验证数据目录
ls -la /data/redis/
```

---

## 六、连接测试

```bash
# 本地测试（容器内）
redis-cli -a 你的Redis密码 ping
# 预期输出：PONG

# 写入测试
redis-cli -a 你的Redis密码 set testkey "hello"
redis-cli -a 你的Redis密码 get testkey

# 查看数据目录
redis-cli -a 你的Redis密码 config get dir
# 预期输出：/data/redis
```

---

## 七、内核参数优化（宿主机或容器内）

Redis 常见警告处理：

```bash
# 在容器内执行（无特权容器可能无效，可在宿主机上执行）
# 调整 vm.overcommit_memory
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf
sysctl -p

# 禁用 Transparent Hugepage（在宿主机上执行）
echo never > /sys/kernel/mm/transparent_hugepage/enabled
```

> **注意**：无特权 LXC 中部分内核参数无法修改，可忽略相关警告，不影响功能。

---

## 八、验收检查

```bash
# 1. 服务状态
systemctl status redis-server

# 2. 数据目录确认
redis-cli -a 你的Redis密码 config get dir

# 3. 持久化文件确认
ls -la /data/redis/
# 应看到 dump.rdb 和 appendonly.aof

# 4. 内网连通性测试（在 docker-01 上执行）
redis-cli -h 192.168.1.202 -a 你的Redis密码 ping

# 5. 重启后验证
pct reboot 202
# 等待启动后再次确认服务状态和数据是否保留
```
