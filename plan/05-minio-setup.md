# MinIO 安装、配置与数据目录设置

> 容器：`minio-01`（CT ID 203，无特权 LXC）  
> 数据目录：`/data/minio`（通过 PVE mp0 挂载）

---

## 前置条件

- 已按 `02-lxc-infrastructure.md` 创建 LXC 并完成基础初始化
- mp0 已挂载到容器内 `/data/minio`
- 容器已启动，可正常登录

---

## 一、下载并安装 MinIO

```bash
# 下载 MinIO 二进制
wget https://dl.min.io/server/minio/release/linux-amd64/minio -O /usr/local/bin/minio

# 赋予执行权限
chmod +x /usr/local/bin/minio

# 确认版本
minio --version
```

---

## 二、创建 MinIO 专用用户

```bash
# 创建 minio 系统用户
useradd -r -s /sbin/nologin minio-user

# 修正数据目录属主
chown -R minio-user:minio-user /data/minio
chmod 750 /data/minio
ls -ld /data/minio
```

---

## 三、创建配置文件

```bash
mkdir -p /etc/minio

cat > /etc/minio/minio.conf << 'EOF'
# MinIO 数据目录
MINIO_VOLUMES="/data/minio"

# 控制台监听地址
MINIO_OPTS="--console-address :9001"

# Root 访问凭证（修改为强密码）
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=MinIO强密码至少8位

# 站点名称（可选）
# MINIO_SITE_NAME="my-minio"
EOF

chmod 640 /etc/minio/minio.conf
```

---

## 四、创建 systemd 服务

```bash
cat > /etc/systemd/system/minio.service << 'EOF'
[Unit]
Description=MinIO Object Storage
Documentation=https://min.io/docs/minio/linux/
After=network-online.target
Wants=network-online.target

[Service]
User=minio-user
Group=minio-user
EnvironmentFile=/etc/minio/minio.conf
ExecStart=/usr/local/bin/minio server $MINIO_VOLUMES $MINIO_OPTS
Restart=always
RestartSec=5s
LimitNOFILE=65536

# 日志
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minio
systemctl start minio
```

---

## 五、验证服务

```bash
# 查看服务状态
systemctl status minio

# 查看启动日志
journalctl -u minio -f --no-pager | head -30

# 确认端口监听
ss -tlnp | grep -E '9000|9001'
```

预期看到：
- `9000`：MinIO API 端口
- `9001`：MinIO 控制台端口

---

## 六、访问 MinIO 控制台

在局域网浏览器中访问：

```
http://192.168.1.203:9001
```

使用 `MINIO_ROOT_USER` 和 `MINIO_ROOT_PASSWORD` 登录。

---

## 七、创建测试 Bucket 并验证

### 通过控制台
1. 登录控制台
2. 点击 `Create Bucket`
3. 创建 `test` bucket
4. 上传一个测试文件并下载确认

### 通过 mc 命令行工具

```bash
# 下载 mc 工具
wget https://dl.min.io/client/mc/release/linux-amd64/mc -O /usr/local/bin/mc
chmod +x /usr/local/bin/mc

# 配置 mc
mc alias set local http://127.0.0.1:9000 minioadmin MinIO强密码至少8位

# 创建 bucket
mc mb local/test

# 上传测试文件
echo "hello minio" > /tmp/test.txt
mc cp /tmp/test.txt local/test/

# 列出文件
mc ls local/test/

# 下载确认
mc cp local/test/test.txt /tmp/test-download.txt
cat /tmp/test-download.txt
```

---

## 八、为业务应用创建独立用户

```bash
# 通过 mc 创建业务用户
mc admin user add local myapp-user myapp强密码

# 创建业务 bucket
mc mb local/myapp-uploads

# 设置权限策略
mc admin policy create local myapp-policy /dev/stdin << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:*"],
      "Resource": ["arn:aws:s3:::myapp-uploads/*", "arn:aws:s3:::myapp-uploads"]
    }
  ]
}
EOF

mc admin policy attach local myapp-policy --user myapp-user
```

---

## 九、验收检查

```bash
# 1. 服务状态
systemctl status minio

# 2. 数据目录确认
ls -la /data/minio/

# 3. 控制台访问：http://192.168.1.203:9001

# 4. 重启后验证
pct reboot 203
# 等待启动后确认数据和 bucket 仍然存在
```
