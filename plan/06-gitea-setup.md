# Gitea 安装、配置与数据目录设置

> 容器：`gitea-01`（CT ID 204，无特权 LXC）  
> 数据目录：`/data/gitea`（通过 PVE mp0 挂载）

---

## 前置条件

- 已按 `02-lxc-infrastructure.md` 创建 LXC 并完成基础初始化
- mp0 已挂载到容器内 `/data/gitea`
- 容器已启动，可正常登录
- MySQL 已部署并可从此容器访问（供 Gitea 使用）

---

## 一、安装依赖

```bash
apt install -y git curl wget sqlite3
```

---

## 二、下载并安装 Gitea

```bash
# 查找最新版本（或手动指定版本号）
GITEA_VERSION="1.22.3"

# 下载 Gitea 二进制
wget "https://dl.gitea.com/gitea/${GITEA_VERSION}/gitea-${GITEA_VERSION}-linux-amd64" \
  -O /usr/local/bin/gitea

# 赋予执行权限
chmod +x /usr/local/bin/gitea

# 确认版本
gitea --version
```

---

## 三、创建 Gitea 专用用户

```bash
# 创建 git 系统用户
useradd -r -m -d /home/git -s /bin/bash git
```

---

## 四、创建目录结构

```bash
# 在 /data/gitea 下创建子目录
mkdir -p /data/gitea/{repositories,custom,data,log,indexers,attachments}

# 创建配置目录
mkdir -p /etc/gitea

# 修正属主
chown -R git:git /data/gitea
chmod -R 750 /data/gitea

# 配置文件初始属主（安装向导需要写入）
touch /etc/gitea/app.ini
chown root:git /etc/gitea/app.ini
chmod 660 /etc/gitea/app.ini

ls -la /data/gitea/
```

---

## 五、创建 systemd 服务

```bash
cat > /etc/systemd/system/gitea.service << 'EOF'
[Unit]
Description=Gitea (Git with a cup of tea)
After=network.target
After=mariadb.service

[Service]
User=git
Group=git
WorkingDirectory=/data/gitea
RuntimeDirectory=gitea
ExecStart=/usr/local/bin/gitea web --config /etc/gitea/app.ini
Restart=always
RestartSec=3s
Environment=USER=git HOME=/home/git GITEA_WORK_DIR=/data/gitea

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable gitea
systemctl start gitea
```

---

## 六、Web 安装向导

在局域网浏览器中访问：

```
http://192.168.1.204:3000
```

按照安装向导填写：

| 字段               | 推荐值                                    |
|--------------------|------------------------------------------|
| 数据库类型         | MySQL（或 SQLite3 简单部署）             |
| 数据库主机         | `192.168.1.201:3306`（mysql-01）        |
| 数据库用户名       | `gitea`                                  |
| 数据库密码         | 自定义强密码                              |
| 数据库名           | `gitea`                                  |
| 仓库根目录         | `/data/gitea/repositories`               |
| 运行用户           | `git`                                    |
| 日志目录           | `/data/gitea/log`                        |
| 应用 URL           | `http://192.168.1.204:3000/`             |
| 管理员账号         | 设置初始管理员用户名和密码               |

### 提前创建 Gitea 数据库（在 mysql-01 上执行）

```bash
mysql -u root -p
```

```sql
CREATE DATABASE gitea CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER 'gitea'@'192.168.1.%' IDENTIFIED BY 'Gitea数据库密码';
GRANT ALL PRIVILEGES ON gitea.* TO 'gitea'@'192.168.1.%';
FLUSH PRIVILEGES;
```

---

## 七、配置文件说明

安装完成后，`/etc/gitea/app.ini` 的关键配置：

```ini
[server]
HTTP_PORT = 3000
ROOT_URL  = http://192.168.1.204:3000/

[repository]
ROOT = /data/gitea/repositories

[log]
ROOT_PATH = /data/gitea/log

[attachment]
PATH = /data/gitea/attachments
```

---

## 八、配置 SSH（可选，推荐）

```bash
# 确认 sshd 已安装并运行
systemctl status ssh

# Gitea SSH 默认使用 git 用户的 ~/.ssh
# 设置 SSH 端口（如需使用非 22 端口，修改 /etc/gitea/app.ini）
# [server]
# SSH_PORT = 22
```

验证 SSH clone：

```bash
git clone git@192.168.1.204:your-username/your-repo.git
```

---

## 九、验收检查

```bash
# 1. 服务状态
systemctl status gitea

# 2. 数据目录确认
ls -la /data/gitea/

# 3. Web 访问：http://192.168.1.204:3000

# 4. 创建测试仓库并推送代码
# 5. SSH clone 验证
# 6. 重启后验证
pct reboot 204
# 等待启动后确认服务正常、仓库数据完整
```
