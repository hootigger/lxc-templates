# 基础设施部署总览

> 目标平台：Proxmox VE 9  
> 部署策略：LXC 承担有状态基础设施，VM 承担 Docker 宿主机  
> 工作流：Docker Compose 为主，k3s 为后续演进方向

---

## 架构总览

```
PVE 9 宿主机
├── LXC 基础设施层
│   ├── mysql-01     (MySQL / MariaDB)
│   ├── redis-01     (Redis)
│   ├── minio-01     (MinIO 对象存储)
│   ├── gitea-01     (Gitea 代码仓库)
│   └── monitor-01   (Prometheus + Grafana)
└── VM 应用层
    └── docker-01    (Docker Engine + Compose 项目)
```

---

## 数据目录约定

所有服务统一使用 `data` 前缀的目录规范：

| 服务      | 容器内数据目录     | 说明                    |
|-----------|-------------------|-------------------------|
| MySQL     | `/data/mysql`     | 数据库数据目录           |
| Redis     | `/data/redis`     | 持久化数据目录           |
| MinIO     | `/data/minio`     | 对象存储数据目录         |
| Gitea     | `/data/gitea`     | 仓库与配置目录           |
| Monitor   | `/data/prometheus`| Prometheus 数据目录      |
| Monitor   | `/data/grafana`   | Grafana 数据目录         |
| Docker VM | `/data`           | 所有 Compose 项目挂载根  |

> **原则**：所有持久化数据目录统一挂载到容器内 `/data/<service>` 下，
> 通过 PVE 挂载点（mp0、mp1 等）管理，方便备份、迁移和扩容。

---

## 实例命名与 CT ID 规划

| CT ID | 类型 | hostname    | 用途           |
|-------|------|-------------|----------------|
| 201   | LXC  | mysql-01    | MySQL 数据库   |
| 202   | LXC  | redis-01    | Redis 缓存     |
| 203   | LXC  | minio-01    | 对象存储       |
| 204   | LXC  | gitea-01    | 代码仓库       |
| 205   | LXC  | monitor-01  | 监控           |
| 301   | VM   | docker-01   | Docker 宿主机  |

---

## IP 地址规划示例

| hostname    | IP 地址示例       | 说明              |
|-------------|-------------------|-------------------|
| mysql-01    | 192.168.1.201     | 固定 IP           |
| redis-01    | 192.168.1.202     | 固定 IP           |
| minio-01    | 192.168.1.203     | 固定 IP           |
| gitea-01    | 192.168.1.204     | 固定 IP           |
| monitor-01  | 192.168.1.205     | 固定 IP           |
| docker-01   | 192.168.1.101     | 固定 IP           |

> 根据实际网段调整，保持每个服务固定 IP，便于内网 DNS 和服务互联。

---

## LXC 通用创建原则

- **无特权容器**：所有 LXC 均选"无特权（Unprivileged）"
- **嵌套**：基础设施 LXC 一律**不开启**嵌套（Nesting）
- **数据目录**：通过 PVE 挂载点（mp0）独立挂载，不与 rootfs 混用
- **备份**：mp0 挂载点勾选"备份"选项
- **开机自启**：所有容器启用开机自启（Start at boot）
- **时区**：统一设置为 `Asia/Shanghai`

---

## 部署顺序建议

```
第 1 步  宿主机基线检查与规划确认
第 2 步  创建 redis-01    （最轻，验证 LXC 流程）
第 3 步  创建 mysql-01    （核心基础设施）
第 4 步  创建 minio-01    （对象存储）
第 5 步  创建 gitea-01    （代码仓库）
第 6 步  创建 docker-01   （VM，Docker 宿主）
第 7 步  部署反向代理与首个 Compose 项目
第 8 步  创建 monitor-01  （监控，可后置）
```

---

## 文档索引

| 文件                          | 内容                              |
|-------------------------------|-----------------------------------|
| `01-pve-resource-planning.md` | 各服务资源规格建议                 |
| `02-lxc-infrastructure.md`    | LXC 通用创建流程与数据目录配置    |
| `03-mysql-setup.md`           | MySQL 安装、配置与数据目录设置    |
| `04-redis-setup.md`           | Redis 安装、配置与数据目录设置    |
| `05-minio-setup.md`           | MinIO 安装、配置与数据目录设置    |
| `06-gitea-setup.md`           | Gitea 安装、配置与数据目录设置    |
| `07-docker-vm.md`             | Docker VM 初始化与 Compose 规范   |
| `08-implementation-checklist.md` | 完整实施 Checklist              |
