# 09 — LXC 基础设施服务资源配置汇总

> 适用于 PVE 9，所有服务均以**无特权 LXC**方式部署。  
> 数据目录统一遵循 `/data/<服务名>` 规范。

---

## 数据目录约定

| 服务 | 容器内数据路径 | 说明 |
|---|---|---|
| MySQL / MariaDB | `/data/mysql` | 数据库数据文件 |
| Redis | `/data/redis` | RDB / AOF 持久化文件 |
| MinIO | `/data/minio` | 对象存储数据目录 |
| Gitea | `/data/gitea` | 仓库及配置数据 |
| Prometheus | `/data/prometheus` | 指标时序数据 |
| Grafana | `/data/grafana` | 仪表盘及配置数据 |
| Loki | `/data/loki` | 日志存储数据 |

所有挂载点均通过 PVE `mp0`（及后续 `mp1`）进行管理，避免直接 bind-mount 宿主机目录。

---

## 各服务推荐资源配置

### 1. mysql-01（MySQL / MariaDB）

| 配置项 | 推荐值 | 说明 |
|---|---|---|
| CT ID | 201 | 可按规划调整 |
| Hostname | `mysql-01` | |
| 模板 | Debian 12 | 稳定优先 |
| 无特权 | 是 | |
| 嵌套 | 否 | |
| rootfs | 16 GiB | 系统 + 软件包 |
| mp0 大小 | 30 GiB 起 | 业务数据量决定上限 |
| mp0 路径 | `/data/mysql` | 统一规范 |
| vCPU | 2 | 可按需调整 |
| 内存 | 2048 MiB | 中小体量，可按需增至 4096 |
| Swap | 512 MiB | |
| 固定 IP | 按规划分配 | 示例：`192.168.1.201/24` |

**安装软件包**：`mariadb-server`

---

### 2. redis-01（Redis）

| 配置项 | 推荐值 | 说明 |
|---|---|---|
| CT ID | 202 | |
| Hostname | `redis-01` | |
| 模板 | Debian 12 | |
| 无特权 | 是 | |
| 嵌套 | 否 | |
| rootfs | 8 GiB | |
| mp0 大小 | 8 GiB | 持久化数据，视缓存量调整 |
| mp0 路径 | `/data/redis` | 统一规范 |
| vCPU | 1 | |
| 内存 | 1024 MiB | 可按缓存需求增至 2048 |
| Swap | 256 MiB | |
| 固定 IP | 按规划分配 | 示例：`192.168.1.202/24` |

**安装软件包**：`redis-server`

---

### 3. minio-01（MinIO 对象存储）

| 配置项 | 推荐值 | 说明 |
|---|---|---|
| CT ID | 203 | |
| Hostname | `minio-01` | |
| 模板 | Debian 12 | |
| 无特权 | 是 | |
| 嵌套 | 否 | |
| rootfs | 8 GiB | |
| mp0 大小 | 100 GiB 起 | 对象存储，按实际需求规划 |
| mp0 路径 | `/data/minio` | 统一规范 |
| vCPU | 2 | |
| 内存 | 2048 MiB | |
| Swap | 512 MiB | |
| 固定 IP | 按规划分配 | 示例：`192.168.1.203/24` |

**安装方式**：官方二进制

---

### 4. gitea-01（Gitea 代码仓库）

| 配置项 | 推荐值 | 说明 |
|---|---|---|
| CT ID | 204 | |
| Hostname | `gitea-01` | |
| 模板 | Debian 12 | |
| 无特权 | 是 | |
| 嵌套 | 否 | |
| rootfs | 16 GiB | |
| mp0 大小 | 50 GiB | 仓库及附件数据 |
| mp0 路径 | `/data/gitea` | 统一规范 |
| vCPU | 2 | |
| 内存 | 1024 MiB | |
| Swap | 512 MiB | |
| 固定 IP | 按规划分配 | 示例：`192.168.1.204/24` |

**安装方式**：官方二进制或 apt

---

### 5. monitor-01（Prometheus + Grafana）

| 配置项 | 推荐值 | 说明 |
|---|---|---|
| CT ID | 205 | |
| Hostname | `monitor-01` | |
| 模板 | Debian 12 | |
| 无特权 | 是 | |
| 嵌套 | 否 | |
| rootfs | 16 GiB | |
| mp0 大小 | 20 GiB | Prometheus 数据 |
| mp0 路径 | `/data/prometheus` | |
| mp1 大小 | 10 GiB | Grafana 数据（可选独立卷） |
| mp1 路径 | `/data/grafana` | |
| vCPU | 2 | |
| 内存 | 2048 MiB | |
| Swap | 512 MiB | |
| 固定 IP | 按规划分配 | 示例：`192.168.1.205/24` |

---

## 部署优先级

```
优先级 1：redis-01   ← 最轻，用来验证 LXC 流程
优先级 2：mysql-01   ← 核心依赖，早建早稳
优先级 3：minio-01   ← 对象存储
优先级 4：gitea-01   ← 代码/配置版本管理
优先级 5：monitor-01 ← 可稍后，先把基础服务跑起来
```

---

## 通用创建流程（每个 LXC 共用）

1. 在 PVE Web UI 中创建容器
2. 配置 rootfs（系统盘）与 mp0（数据盘）
3. 设置静态 IP
4. 勾选"无特权容器"，**不勾**嵌套
5. 启动容器，登入后执行：
   ```bash
   apt update && apt upgrade -y
   timedatectl set-timezone Asia/Shanghai
   apt install -y curl wget vim
   ```
6. 确认数据目录挂载正常：`ls -ld /data/<服务名>`
7. 安装对应服务（见各服务手册）
8. 配置开机自启：`systemctl enable <服务>`
9. 在 PVE 中配置 LXC 备份策略
