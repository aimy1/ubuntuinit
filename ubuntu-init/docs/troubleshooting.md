# 故障排查指南

---

## 常见问题

### 1. 脚本执行权限错误

**现象：** `bash: permission denied` 或 `not found`

**解决：**
```bash
chmod +x install.sh
sudo bash install.sh
```

---

### 2. APT 锁被占用

**现象：** `Could not get lock /var/lib/dpkg/lock-frontend`

**解决：**
```bash
# 查看占用进程
sudo lsof /var/lib/dpkg/lock-frontend

# 等待进程结束后重试，或（谨慎）强制清除
sudo rm /var/lib/dpkg/lock-frontend
sudo dpkg --configure -a
sudo apt-get install -f
```

UbuntuInit 内置 APT 锁等待（默认 120 秒），一般无需手动干预。

---

### 3. 网络检测失败

**现象：** `无法连接互联网，请检查网络配置`

**解决方案 A：** 配置代理
```bash
export http_proxy="http://proxy-host:port"
export https_proxy="http://proxy-host:port"
sudo -E bash install.sh
```

**解决方案 B：** 跳过网络检测
```bash
UBINIT_SKIP_NET_CHECK=true sudo bash install.sh
```

---

### 4. SSH 端口修改后连接中断

**现象：** 修改 SSH 端口后当前会话断开

**预防措施：**
1. 修改 `UBINIT_SSH_PORT` 前，先将新端口加入防火墙：
   ```bash
   UBINIT_SECURITY_UFW_ALLOW_PORTS="22 2222 80 443"
   ```
2. 使用 `tmux` 或 `screen` 保持会话

**恢复：**
- UbuntuInit 会在修改端口后等待 30 秒验证新端口可达
- 若端口不可达，会**自动回滚**到原始 sshd_config
- 若已经断开，使用 VNC/带外管理端口连接后手动恢复

---

### 5. Docker 安装失败

**现象：** GPG 密钥下载失败，或 APT 源 404

**解决：**
```bash
# 手动清理后重试
sudo rm -f /etc/apt/keyrings/docker.asc
sudo rm -f /etc/apt/sources.list.d/docker.list
sudo apt-get update

# 重新运行 Docker 模块
sudo bash install.sh --modules "08_docker"
```

**国内环境：** 配置镜像
```bash
UBINIT_DOCKER_REGISTRY_MIRROR_SOURCE=aliyun
```

---

### 6. MariaDB/MySQL 密码设置失败

**现象：** 安全初始化执行报错

**手动执行：**
```bash
# MariaDB
sudo mysql -u root
ALTER USER 'root'@'localhost' IDENTIFIED BY 'your-password';
FLUSH PRIVILEGES;
exit;

# MySQL
sudo mysql -u root
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'your-password';
FLUSH PRIVILEGES;
exit;
```

---

### 7. BBR 启用失败

**现象：** `内核不支持 BBR，跳过`

**原因：** 内核版本 < 4.9 不支持 BBR

**解决：**
```bash
# 检查内核版本（需 >= 4.9）
uname -r

# 若版本过旧，更新 HWE 内核
sudo apt install linux-generic-hwe-20.04
sudo reboot

# 重启后再次运行优化模块
sudo bash install.sh --modules "07_optimize"
```

---

### 8. 查看安装日志

```bash
# 查找最新日志
ls -lt /var/log/ubuntu-init*.log | head -5

# 实时查看
tail -f /var/log/ubuntu-init-*.log

# 过滤错误
grep -E 'ERROR|WARN' /var/log/ubuntu-init-*.log
```

---

### 9. 手动回滚配置

```bash
# 查看备份列表
ls -la /var/backup/ubuntu-init/

# 恢复 SSH 配置
sudo cp /var/backup/ubuntu-init/ssh/etc/ssh/sshd_config.*.bak /etc/ssh/sshd_config
sudo systemctl restart ssh

# 恢复 APT sources.list
sudo cp /var/backup/ubuntu-init/*/etc/apt/sources.list.*.bak /etc/apt/sources.list
sudo apt-get update
```

---

### 10. ShellCheck 报告问题

```bash
# 安装 ShellCheck
sudo apt install shellcheck

# 检查所有脚本
bash tests/shellcheck.sh

# 检查单个文件
shellcheck -x -s bash install.sh
```

---

## 获取帮助

```bash
# 查看帮助信息
sudo bash install.sh --help

# 查看支持的模块
sudo bash install.sh --list-modules

# Dry-run 预览
sudo bash install.sh --dry-run

# 详细调试输出
UBINIT_VERBOSE=true sudo bash install.sh
```

---

## 提交 Bug 报告

请提供以下信息：

```bash
# 系统信息
uname -a
cat /etc/os-release

# 最新安装日志（脱敏后）
cat /var/log/ubuntu-init-*.log | tail -100
```
