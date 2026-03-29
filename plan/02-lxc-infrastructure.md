# LXC 基础设施通用创建流程

> 适用于所有基础设施 LXC（mysql-01、redis-01、minio-01、gitea-01、monitor-01）

---

## 一、在 PVE Web UI 中创建 LXC

### 1.1 常规（General）

| 字段                 | 填写建议                  |
|----------------------|--------------------------|
| Node                 | 当前宿主节点              |
| CT ID                | 按规划填写（如 201）      |
| Hostname             | 服务名（如 `mysql-01`）   |
| Unprivileged container | **勾选**（无特权）      |
| Password / SSH keys  | 设置 root 密码或 SSH 公钥 |

### 1.2 模板（Template）

- 推荐选择 **Debian 12**（bookworm）或 **Ubuntu 22.04**
- 请在 PVE 模板库中提前下载好 CT 模板

### 1.3 磁盘（Disks）

| 字段    | 说明                                       |
|---------|--------------------------------------------|
| Storage | 选择系统存储（如 local-lvm）               |
| Size    | 按 `01-pve-resource-planning.md` 中 rootfs 大小填写 |

### 1.4 CPU / 内存

按 `01-pve-resource-planning.md` 中各服务规格填写。

### 1.5 网络（Network）

| 字段     | 填写建议                                  |
|----------|------------------------------------------|
| Bridge   | `vmbr0`（或你的局域网网桥）              |
| IPv4     | Static，填写规划的固定 IP（含子网掩码）   |
| Gateway  | 局域网网关地址                            |

### 1.6 DNS

| 字段        | 填写建议               |
|-------------|------------------------|
| DNS domain  | 可留空或填内网域名     |
| DNS servers | 局域网 DNS 或 `114.114.114.114` |

### 1.7 确认创建

- **Start after created**：创建后可先不勾，手动添加数据挂载点后再启动

---

## 二、添加数据挂载点（mp0）

> 在容器启动前，先通过 PVE Web UI 添加数据挂载点。

### 2.1 进入容器配置

`Datacenter -> 节点 -> 容器 -> Resources -> Add -> Mount Point`

### 2.2 挂载点配置

| 字段        | 填写建议                                           |
|-------------|---------------------------------------------------|
| Storage     | 数据存储池（如 local-lvm 或独立数据存储）         |
| Disk size   | 按规划填写（如 50 GB）                             |
| Path        | 容器内挂载路径，统一使用 `/data/<service>`        |
| Backup      | **勾选**（纳入 PVE 备份）                         |
| Read-only   | 不勾                                               |
| ACLs        | 默认                                               |
| Skip replication | 默认不勾                                     |

### 2.3 各服务数据目录速查

| 服务       | 挂载点 | 容器内路径         |
|------------|--------|-------------------|
| mysql-01   | mp0    | `/data/mysql`     |
| redis-01   | mp0    | `/data/redis`     |
| minio-01   | mp0    | `/data/minio`     |
| gitea-01   | mp0    | `/data/gitea`     |
| monitor-01 | mp0    | `/data/prometheus`|
| monitor-01 | mp1    | `/data/grafana`   |

---

## 三、启动容器并完成基础初始化

### 3.1 启动容器

```bash
# 在 PVE 宿主机上启动容器（以 mysql-01 CT ID=201 为例）
pct start 201
```

### 3.2 进入容器

```bash
pct enter 201
```

### 3.3 基础初始化（容器内执行）

```bash
# 更新系统
apt update && apt upgrade -y

# 设置时区
timedatectl set-timezone Asia/Shanghai

# 安装常用工具
apt install -y curl wget vim net-tools

# 确认时区
date
```

### 3.4 数据目录权限检查

```bash
# 确认挂载点已正确挂载
df -h | grep data

# 检查目录权限
ls -ld /data/<service>
```

---

## 四、开机自启设置

```bash
# 在 PVE 宿主机上设置容器开机自启
pct set 201 --onboot 1
```

或在 PVE Web UI 中：`容器 -> Options -> Start at boot -> Enabled`

---

## 五、常见问题处理

### 5.1 数据目录权限不足（无特权 LXC）

无特权 LXC 存在 UID/GID 映射，服务进程可能无法写入 `/data/<service>`。

**处理步骤**：

```bash
# 1. 确认服务用户的 UID/GID（容器内）
id mysql      # 或 id redis

# 2. 修正数据目录属主（容器内）
chown -R mysql:mysql /data/mysql    # MySQL
chown -R redis:redis /data/redis    # Redis
chown -R minio-user:minio-user /data/minio  # MinIO

# 3. 确认权限
ls -ld /data/<service>
```

### 5.2 确认挂载点正确

```bash
# 在 PVE 宿主机上查看容器配置
pct config 201
```

输出中应看到类似：
```
mp0: local-lvm:vm-201-disk-1,mp=/data/mysql,size=50G,backup=1
```

---

## 六、各服务安装指引

创建 LXC 并完成基础初始化后，参考以下文档进行服务安装：

- MySQL：`03-mysql-setup.md`
- Redis：`04-redis-setup.md`
- MinIO：`05-minio-setup.md`
- Gitea：`06-gitea-setup.md`
