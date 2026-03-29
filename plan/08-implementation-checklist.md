# PVE 9 基础环境实施 Checklist

> 目标：在 PVE 9 上完成 LXC 基础设施 + Docker VM 的完整落地  
> 原则：先稳定、后扩展；先基础设施、后业务应用；每步可验证、可回滚  
> 数据目录约定：所有持久化数据统一使用 `/data/<service>` 前缀

---

## 阶段 0：宿主机基线确认

### 0.1 系统状态

- [ ] PVE 9 升级完成，Web 管理界面可正常访问
- [ ] 宿主机时间、时区、NTP 同步正常（`timedatectl status`）
- [ ] 软件源已配置（无订阅或社区源均可），`apt update` 无报错
- [ ] 系统更新已完成（`apt upgrade -y`）
- [ ] SSH 可正常登录宿主机
- [ ] 防火墙策略未误伤管理入口（PVE Web 8006 端口正常）

### 0.2 资源状态

- [ ] 记录当前 CPU / 内存 / 磁盘使用情况
- [ ] 确认宿主机根盘剩余空间是否充足（建议 > 20 GB）
- [ ] 确认是否已有独立数据盘（用于 LXC 数据挂载点和 Docker 数据）
- [ ] 记录已有 LXC / VM 的 CT ID、IP，避免后续冲突

### 0.3 规划确认

- [ ] 确认 IP 地址规划（参考 `00-overview.md` 中的 IP 表）
- [ ] 确认存储规划（系统盘 vs 数据盘分离）
- [ ] 确认各 LXC 的 CT ID 规划

---

## 阶段 1：创建并配置 redis-01

> **先从 Redis 开始**——最轻，适合验证 LXC 创建和数据目录挂载流程

### 1.1 创建 LXC

- [ ] 在 PVE Web UI 创建 LXC
  - CT ID：202 | hostname：redis-01
  - 无特权容器：**勾选**
  - 嵌套（Nesting）：**不勾**
  - 模板：Debian 12
  - rootfs：8 GB
  - CPU：1 核
  - 内存：2048 MB
  - 网络：固定 IP（如 192.168.1.202）
  - **创建后先不要启动**

### 1.2 添加数据挂载点

- [ ] 在容器 Resources 中添加 Mount Point（mp0）
  - 存储：数据存储池
  - 大小：8 GB
  - 路径：`/data/redis`
  - 备份：**勾选**

### 1.3 启动并初始化

- [ ] 启动容器（`pct start 202`）
- [ ] 进入容器（`pct enter 202`）
- [ ] `apt update && apt upgrade -y`
- [ ] `timedatectl set-timezone Asia/Shanghai`
- [ ] 确认 `/data/redis` 已挂载（`df -h | grep data`）
- [ ] 设置开机自启（`pct set 202 --onboot 1`）

### 1.4 安装 Redis

- [ ] `apt install -y redis-server`
- [ ] 停止 Redis 服务
- [ ] `chown -R redis:redis /data/redis`
- [ ] 修改 `/etc/redis/redis.conf`
  - `dir /data/redis`
  - `logfile /data/redis/redis.log`
  - `requirepass 你的密码`
  - `appendonly yes`
  - `maxmemory 1536mb`
  - `maxmemory-policy allkeys-lru`
- [ ] `systemctl start redis-server && systemctl enable redis-server`

### 1.5 验收

- [ ] `redis-cli -a 密码 ping` 返回 `PONG`
- [ ] `redis-cli -a 密码 config get dir` 返回 `/data/redis`
- [ ] `ls -la /data/redis/` 看到 `dump.rdb` 和 `appendonly.aof`
- [ ] 重启容器后服务自动恢复（`pct reboot 202`）
- [ ] 从其他主机内网连通测试

---

## 阶段 2：创建并配置 mysql-01

### 2.1 创建 LXC

- [ ] 在 PVE Web UI 创建 LXC
  - CT ID：201 | hostname：mysql-01
  - 无特权容器：**勾选**
  - 嵌套（Nesting）：**不勾**
  - 模板：Debian 12
  - rootfs：16 GB
  - CPU：2 核
  - 内存：4096 MB
  - 网络：固定 IP（如 192.168.1.201）
  - **创建后先不要启动**

### 2.2 添加数据挂载点

- [ ] 添加 mp0
  - 存储：数据存储池
  - 大小：50 GB
  - 路径：`/data/mysql`
  - 备份：**勾选**

### 2.3 启动并初始化

- [ ] 启动容器，完成基础初始化（同 1.3 步骤）
- [ ] 确认 `/data/mysql` 已挂载

### 2.4 安装 MariaDB

- [ ] `apt install -y mariadb-server`
- [ ] 停止 MariaDB
- [ ] `chown -R mysql:mysql /data/mysql && chmod 750 /data/mysql`
- [ ] 修改 `/etc/mysql/mariadb.conf.d/50-server.cnf`
  - `datadir = /data/mysql`
  - `bind-address = 0.0.0.0`
  - `character-set-server = utf8mb4`
  - `innodb_buffer_pool_size = 2G`
- [ ] 处理 AppArmor 配置（允许 `/data/mysql`）
- [ ] `mysql_install_db --user=mysql --basedir=/usr --datadir=/data/mysql`
- [ ] `systemctl start mariadb && systemctl enable mariadb`
- [ ] `mysql_secure_installation`（设置 root 密码、移除匿名用户）

### 2.5 创建业务数据库和用户

- [ ] 创建 Gitea 数据库（为后续 gitea-01 准备）
- [ ] 创建业务应用数据库和用户

### 2.6 验收

- [ ] `mysql -u root -p -e "SHOW VARIABLES LIKE 'datadir';"` 返回 `/data/mysql/`
- [ ] 内网连通测试（从 docker-01 或其他主机）
- [ ] 重启容器后服务自动恢复（`pct reboot 201`）
- [ ] 备份脚本创建并测试运行

---

## 阶段 3：创建并配置 minio-01

### 3.1 创建 LXC

- [ ] 在 PVE Web UI 创建 LXC
  - CT ID：203 | hostname：minio-01
  - 无特权容器：**勾选**
  - 嵌套：**不勾**
  - rootfs：8 GB
  - CPU：2 核
  - 内存：2048 MB
  - 网络：固定 IP（如 192.168.1.203）

### 3.2 添加数据挂载点

- [ ] 添加 mp0
  - 大小：100 GB+
  - 路径：`/data/minio`
  - 备份：**勾选**

### 3.3 安装配置 MinIO

- [ ] 下载 MinIO 二进制到 `/usr/local/bin/minio`
- [ ] `useradd -r -s /sbin/nologin minio-user`
- [ ] `chown -R minio-user:minio-user /data/minio`
- [ ] 创建 `/etc/minio/minio.conf`（设置 ROOT_USER、ROOT_PASSWORD、VOLUMES）
- [ ] 创建 systemd 服务文件
- [ ] `systemctl enable minio && systemctl start minio`

### 3.4 验收

- [ ] 控制台访问：`http://192.168.1.203:9001`
- [ ] 创建 `test` bucket，上传文件，下载验证
- [ ] 数据目录 `/data/minio` 有数据写入
- [ ] 重启容器后数据完整保留

---

## 阶段 4：创建并配置 gitea-01

### 4.1 创建 LXC

- [ ] 在 PVE Web UI 创建 LXC
  - CT ID：204 | hostname：gitea-01
  - 无特权容器：**勾选**
  - 嵌套：**不勾**
  - rootfs：8 GB
  - CPU：2 核
  - 内存：2048 MB
  - 网络：固定 IP（如 192.168.1.204）

### 4.2 添加数据挂载点

- [ ] 添加 mp0
  - 大小：30 GB
  - 路径：`/data/gitea`
  - 备份：**勾选**

### 4.3 安装配置 Gitea

- [ ] `apt install -y git curl`
- [ ] 下载 Gitea 二进制到 `/usr/local/bin/gitea`
- [ ] 创建 `git` 用户
- [ ] 创建目录结构（`/data/gitea/repositories`、`log`、`data` 等）
- [ ] 创建 systemd 服务
- [ ] `systemctl enable gitea && systemctl start gitea`
- [ ] 浏览器完成 Web 安装向导
  - 数据库选 MySQL（连接 192.168.1.201）
  - 仓库根目录设为 `/data/gitea/repositories`

### 4.4 验收

- [ ] Web 访问：`http://192.168.1.204:3000`
- [ ] 创建测试仓库，推送代码
- [ ] SSH clone 验证
- [ ] 重启容器后数据完整保留

---

## 阶段 5：创建并初始化 docker-01（VM）

### 5.1 创建 VM

- [ ] 在 PVE Web UI 创建 KVM 虚拟机
  - VM ID：301 | Name：docker-01
  - OS：Debian 12 / Ubuntu 22.04
  - CPU：4 核
  - 内存：8192 MB
  - 系统盘：32 GB

### 5.2 添加数据盘

- [ ] 创建 VM 后，添加第二块磁盘（100 GB+）

### 5.3 系统安装与初始化

- [ ] 安装操作系统
- [ ] 设置固定 IP（192.168.1.101）
- [ ] 格式化并挂载数据盘到 `/data`（写入 `/etc/fstab`）
- [ ] `apt update && apt upgrade -y`
- [ ] `timedatectl set-timezone Asia/Shanghai`

### 5.4 安装 Docker

- [ ] 按官方流程安装 Docker Engine 和 Compose 插件
- [ ] 配置 Docker 数据目录为 `/data/docker`
- [ ] `systemctl enable docker`

### 5.5 Compose 环境准备

- [ ] `mkdir -p /data/compose`
- [ ] 创建 `proxy` Docker 网络（`docker network create proxy`）
- [ ] 部署 Traefik 反向代理

### 5.6 验收

- [ ] `docker version` 正常
- [ ] `docker compose version` 正常
- [ ] `docker info | grep "Docker Root Dir"` 显示 `/data/docker`
- [ ] `docker run --rm hello-world` 成功
- [ ] Traefik 容器正常运行（`docker compose ps`）
- [ ] 重启后 Docker 和 Traefik 自动恢复

---

## 阶段 6：首个 Compose 项目样板

- [ ] 在 `/data/compose/` 下创建第一个项目目录
- [ ] 编写 `docker-compose.yml` 和 `.env`
- [ ] 配置连接 mysql-01（192.168.1.201）
- [ ] 配置连接 redis-01（192.168.1.202）
- [ ] 配置挂载目录在 `./data/` 下
- [ ] 接入 Traefik 反向代理
- [ ] `docker compose up -d` 成功启动
- [ ] 通过域名/IP 访问应用
- [ ] 完成"修改配置 → 重启 → 验证"流程

---

## 阶段 7：整体验收与运维准备

### 7.1 基础设施验收

- [ ] redis-01 可用，持久化正常
- [ ] mysql-01 可用，业务用户可连接
- [ ] minio-01 可用，bucket 正常
- [ ] gitea-01 可用，仓库操作正常

### 7.2 运维清单

- [ ] 整理并记录实例清单（CT ID、hostname、IP、用途）
- [ ] 整理并记录 IP 分配表
- [ ] 整理并记录各服务登录凭证（加密保存）
- [ ] 整理并记录域名/访问地址
- [ ] 确认 PVE 备份策略已配置
- [ ] 完成至少一次备份恢复演练

### 7.3 暂不处理（后续阶段）

- [ ] k3s / Kubernetes 演进（待 Compose 工作流稳定后）
- [ ] 高可用集群（当前以稳定性为主）
- [ ] 完整可观测性全家桶（monitor-01 可后置部署）
- [ ] GitOps / CI 自动化流水线

---

## 快速参考：各阶段预计时间

| 阶段        | 内容                   | 预计时间 |
|-------------|------------------------|----------|
| 阶段 0      | 宿主机基线确认          | 30 分钟  |
| 阶段 1      | redis-01               | 1 小时   |
| 阶段 2      | mysql-01               | 1.5 小时 |
| 阶段 3      | minio-01               | 1 小时   |
| 阶段 4      | gitea-01               | 1.5 小时 |
| 阶段 5      | docker-01 VM           | 2 小时   |
| 阶段 6      | 首个 Compose 项目       | 1 小时   |
| 阶段 7      | 整体验收与运维准备      | 1 小时   |
| **总计**    |                        | **~9 小时** |
