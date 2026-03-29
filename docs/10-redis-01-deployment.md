# Redis 部署手册（redis-01）

本文档描述在 Proxmox VE 无特权 LXC 容器中部署 Redis 的完整流程，数据目录统一使用 `/data/redis`。

---

## 一、LXC 创建参数

| 参数 | 推荐值 |
|------|--------|
| CT ID | `201` |
| hostname | `redis-01` |
| 模板 | Debian 12 |
| 无特权 | **是** |
| 嵌套 | **否** |
| CPU | 1 vCPU |
| 内存 | 1024 MB |
| rootfs 大小 | 8 GB |
| mp0 大小 | 4–8 GB |
| mp0 路径（容器内） | `/data/redis` |
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
ls -ld /data/redis

# 更新系统并安装 Redis
apt update && apt upgrade -y
apt install -y redis-server curl vim bash-completion

# 启用 SSH 开机自启（可选）
systemctl enable ssh
```

---

## 三、数据目录权限设置

```bash
# 确认 redis 系统用户存在
id redis

# 将数据目录属主改为 redis 用户
chown -R redis:redis /data/redis
chmod 750 /data/redis

# 验证
ls -ld /data/redis
```

---

## 四、Redis 配置

编辑配置文件：

```bash
vim /etc/redis/redis.conf
```

关键配置项（修改或确认以下内容）：

```conf
# 监听地址（内网使用可改为固定内网 IP 或 0.0.0.0）
bind 0.0.0.0

# 保护模式（开启后需密码才能远程连接）
protected-mode yes

# 端口
port 6379

# 数据目录（统一使用 /data/redis）
dir /data/redis

# 密码（替换为强密码）
requirepass <your-strong-password>

# AOF 持久化（推荐开启）
appendonly yes
appendfilename "appendonly.aof"

# RDB 快照策略
save 900 1
save 300 10
save 60 10000
```

---

## 五、启动并设置开机自启

```bash
systemctl restart redis-server
systemctl enable redis-server
systemctl status redis-server --no-pager
```

---

## 六、验收检查

### 6.1 端口监听

```bash
ss -lntp | grep 6379
```

### 6.2 数据目录文件

```bash
ls -lah /data/redis
```

预期看到 AOF 文件或 dump.rdb。

### 6.3 本地连通性

```bash
redis-cli -a '<your-password>' ping
# 预期返回：PONG

redis-cli -a '<your-password>' set test:key hello
redis-cli -a '<your-password>' get test:key
# 预期返回：hello
```

### 6.4 内网远程连通性

从另一台机器测试：

```bash
redis-cli -h <redis-01-ip> -p 6379 -a '<your-password>' ping
```

### 6.5 重启后持久化验证

```bash
# 重启 Redis 服务
systemctl restart redis-server

# 确认之前写入的数据仍在
redis-cli -a '<your-password>' get test:key
# 预期返回：hello

# 检查数据目录
ls -lah /data/redis
```

### 6.6 容器重启验证

从 PVE 重启容器后，确认：
- Redis 服务自动启动
- `/data/redis` 数据完整
- 测试 key 仍然存在

---

## 七、常见问题排查

```bash
# 查看 Redis 日志
journalctl -u redis-server -n 100 --no-pager

# 检查目录权限
ls -ld /data/redis
id redis
```

### 启动失败常见原因

| 现象 | 可能原因 | 解决方法 |
|------|----------|----------|
| Permission denied | 目录属主不对 | `chown -R redis:redis /data/redis` |
| Address already in use | 端口被占用 | `ss -lntp | grep 6379` 排查 |
| NOAUTH 错误 | 连接时未提供密码 | 添加 `-a '<password>'` 参数 |

---

## 八、安全建议

- 仅在内网使用，不直接暴露公网
- 必须设置强密码
- 如需外部访问，通过反向代理或 VPN 统一管理
- 定期检查 PVE 备份任务是否正常运行
