# 配置参考手册

本文档列出 UbuntuInit 所有配置变量，对应文件为 `config/default.conf`。
用户自定义配置写入 `config/custom.conf`（优先级更高）。

---

## 全局开关

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_NON_INTERACTIVE` | `false` | `true` = 无人值守模式，跳过所有交互确认 |
| `UBINIT_DRY_RUN` | `false` | `true` = 只打印将执行的命令，不实际修改 |
| `UBINIT_VERBOSE` | `false` | `true` = 显示 DEBUG 级别日志 |
| `UBINIT_SKIP_NET_CHECK` | `false` | `true` = 跳过网络连通检测 |
| `UBINIT_LOG_FILE` | `/var/log/ubuntu-init-TIMESTAMP.log` | 日志文件路径 |
| `UBINIT_BACKUP_DIR` | `/var/backup/ubuntu-init` | 配置文件备份目录 |
| `UBINIT_MODULES` | `""` | 指定运行的模块（逗号分隔），空=全部 |

---

## 01 系统基础 `UBINIT_SYSTEM_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_SYSTEM_APT_UPDATE` | `true` | 执行 apt-get update |
| `UBINIT_SYSTEM_APT_UPGRADE` | `true` | 执行 apt-get upgrade |
| `UBINIT_SYSTEM_AUTOREMOVE` | `true` | 执行 apt-get autoremove |
| `UBINIT_SYSTEM_AUTOCLEAN` | `true` | 执行 apt-get autoclean |
| `UBINIT_SYSTEM_TIMEZONE` | `Asia/Shanghai` | 时区（`timedatectl list-timezones`） |
| `UBINIT_SYSTEM_NTP_SERVERS` | `ntp.aliyun.com ntp1.aliyun.com` | NTP 服务器（空格分隔） |
| `UBINIT_SYSTEM_LOCALE` | `en_US.UTF-8` | 系统语言 |
| `UBINIT_SYSTEM_HOSTNAME` | `""` | 主机名，留空不修改 |

---

## 02 软件源 `UBINIT_MIRROR_*`

| 变量 | 默认值 | 可选值 |
|------|--------|--------|
| `UBINIT_MIRROR_ENABLE` | `false` | `true` / `false` |
| `UBINIT_MIRROR_APT` | `aliyun` | `aliyun` · `tencent` · `huawei` · `ustc` · `tsinghua` · `official` |
| `UBINIT_MIRROR_SNAP` | `false` | `true` / `false` |

---

## 03 SSH `UBINIT_SSH_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_SSH_ENABLE` | `true` | 是否执行 SSH 配置 |
| `UBINIT_SSH_PORT` | `22` | SSH 监听端口 |
| `UBINIT_SSH_PERMIT_ROOT_LOGIN` | `prohibit-password` | `yes` · `no` · `prohibit-password` |
| `UBINIT_SSH_PASSWORD_AUTH` | `no` | `yes` · `no` |
| `UBINIT_SSH_PUBKEY_AUTH` | `yes` | `yes` · `no` |
| `UBINIT_SSH_MAX_AUTH_TRIES` | `3` | 最大认证尝试次数 |
| `UBINIT_SSH_CLIENT_ALIVE_INTERVAL` | `300` | 心跳间隔（秒） |

> ⚠️ **警告**：修改 SSH 端口前，请确保已将新端口加入防火墙白名单，或设置 `UBINIT_SECURITY_UFW_ALLOW_PORTS` 包含新端口。

---

## 04 用户 `UBINIT_USER_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_USER_CREATE` | `false` | 是否创建用户 |
| `UBINIT_USER_NAME` | `ubuntu` | 用户名 |
| `UBINIT_USER_SUDO` | `true` | 是否加入 sudo 组（NOPASSWD） |
| `UBINIT_USER_AUTHORIZED_KEYS` | `""` | SSH 公钥字符串 |
| `UBINIT_USER_AUTHORIZED_KEYS_FILE` | `""` | SSH 公钥文件路径 |

---

## 05 安全 `UBINIT_SECURITY_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_SECURITY_UFW` | `true` | 启用 UFW 防火墙 |
| `UBINIT_SECURITY_UFW_DEFAULT_INCOMING` | `deny` | 默认入站策略 |
| `UBINIT_SECURITY_UFW_DEFAULT_OUTGOING` | `allow` | 默认出站策略 |
| `UBINIT_SECURITY_UFW_ALLOW_PORTS` | `22 80 443` | 允许的入站端口（空格分隔） |
| `UBINIT_SECURITY_FAIL2BAN` | `true` | 安装 Fail2ban |
| `UBINIT_SECURITY_FAIL2BAN_MAXRETRY` | `5` | 触发封禁的失败次数 |
| `UBINIT_SECURITY_FAIL2BAN_BANTIME` | `3600` | 封禁时长（秒） |
| `UBINIT_SECURITY_SYSCTL` | `true` | 应用 sysctl 安全加固 |
| `UBINIT_SECURITY_ULIMIT` | `true` | 配置 ulimit 限制 |
| `UBINIT_SECURITY_AUTO_UPDATE` | `true` | 启用自动安全更新 |

---

## 06 网络工具 `UBINIT_NETTOOLS_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_NETTOOLS_ENABLE` | `true` | 是否安装网络工具 |
| `UBINIT_NETTOOLS_PACKAGES` | `curl wget git vim nano btop htop tmux screen tree jq iftop iperf3 nmap tcpdump traceroute mtr net-tools dnsutils lsof unzip zip` | 要安装的包列表（空格分隔） |

---

## 07 性能优化 `UBINIT_OPTIMIZE_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_OPTIMIZE_BBR` | `true` | 启用 BBR 拥塞控制 |
| `UBINIT_OPTIMIZE_TCP` | `true` | TCP 参数调优 |
| `UBINIT_OPTIMIZE_SWAP` | `true` | 配置 Swap（无 swap 时） |
| `UBINIT_OPTIMIZE_SWAP_SIZE` | `""` | Swap 大小，如 `2G`、`512M`；留空=内存1x |
| `UBINIT_OPTIMIZE_IO_SCHEDULER` | `true` | 配置 IO 调度器（SSD/HDD） |
| `UBINIT_OPTIMIZE_CPU_GOVERNOR` | `schedutil` | CPU 调速策略 |

---

## 08 Docker `UBINIT_DOCKER_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_DOCKER_ENABLE` | `false` | 是否安装 Docker |
| `UBINIT_DOCKER_REGISTRY_MIRROR_SOURCE` | `aliyun` | 镜像加速源 `aliyun` / `tencent` / `official` |
| `UBINIT_DOCKER_REGISTRY_MIRRORS` | `""` | 自定义镜像地址（覆盖 source） |
| `UBINIT_DOCKER_COMPOSE` | `true` | 安装 docker-compose-plugin |
| `UBINIT_DOCKER_BUILDX` | `true` | 安装 docker-buildx-plugin |
| `UBINIT_DOCKER_AUTOSTART` | `true` | 开机自启 |
| `UBINIT_DOCKER_ADD_USER` | `true` | 将 `UBINIT_USER_NAME` 加入 docker 组 |

---

## 09-13 开发语言

### Python `UBINIT_PYTHON_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_PYTHON_ENABLE` | `false` | 是否安装 Python |
| `UBINIT_PYTHON_METHOD` | `apt` | `apt` / `pyenv` |
| `UBINIT_PYTHON_VERSION` | `3.12.0` | pyenv 安装的版本 |
| `UBINIT_PYTHON_PIP` | `true` | 安装 pip |
| `UBINIT_PYTHON_VENV` | `true` | 安装 venv |

### Node.js `UBINIT_NODE_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_NODE_ENABLE` | `false` | 是否安装 Node.js |
| `UBINIT_NODE_METHOD` | `nvm` | `nvm` / `nodesource` / `apt` |
| `UBINIT_NODE_VERSION` | `lts` | 版本号或 `lts` / `current` |
| `UBINIT_NODE_YARN` | `false` | 安装 yarn |
| `UBINIT_NODE_PNPM` | `false` | 安装 pnpm |

### Java `UBINIT_JAVA_*`

| 变量 | 默认值 | 可选值 |
|------|--------|--------|
| `UBINIT_JAVA_ENABLE` | `false` | |
| `UBINIT_JAVA_METHOD` | `apt` | `apt` / `sdkman` |
| `UBINIT_JAVA_VERSION` | `21` | `11` · `17` · `21` · `23` |
| `UBINIT_JAVA_DIST` | `openjdk` | `openjdk` · `temurin` |

### Go `UBINIT_GO_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_GO_ENABLE` | `false` | |
| `UBINIT_GO_VERSION` | `latest` | 版本号或 `latest` |

### Rust `UBINIT_RUST_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_RUST_ENABLE` | `false` | |
| `UBINIT_RUST_USER` | `""` | 安装目标用户，留空=当前用户 |

---

## 14-18 数据库

### Redis `UBINIT_REDIS_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_REDIS_ENABLE` | `false` | |
| `UBINIT_REDIS_PORT` | `6379` | |
| `UBINIT_REDIS_PASSWORD` | `""` | 留空=不设密码 |
| `UBINIT_REDIS_MAXMEMORY` | `256mb` | |
| `UBINIT_REDIS_MAXMEMORY_POLICY` | `allkeys-lru` | |

### MariaDB `UBINIT_MARIADB_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_MARIADB_ENABLE` | `false` | |
| `UBINIT_MARIADB_ROOT_PASSWORD` | `""` | 留空=自动生成 |
| `UBINIT_MARIADB_PORT` | `3306` | |
| `UBINIT_MARIADB_SECURE` | `true` | 执行安全初始化 |

### MySQL `UBINIT_MYSQL_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_MYSQL_ENABLE` | `false` | 与 MariaDB 互斥 |
| `UBINIT_MYSQL_ROOT_PASSWORD` | `""` | 留空=自动生成 |
| `UBINIT_MYSQL_PORT` | `3306` | |

### PostgreSQL `UBINIT_POSTGRESQL_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_POSTGRESQL_ENABLE` | `false` | |
| `UBINIT_POSTGRESQL_VERSION` | `16` | |
| `UBINIT_POSTGRESQL_PORT` | `5432` | |
| `UBINIT_POSTGRESQL_PASSWORD` | `""` | postgres 用户密码，留空=自动生成 |
| `UBINIT_POSTGRESQL_DB` | `""` | 初始数据库名 |

### MongoDB `UBINIT_MONGODB_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_MONGODB_ENABLE` | `false` | |
| `UBINIT_MONGODB_VERSION` | `7.0` | |
| `UBINIT_MONGODB_PORT` | `27017` | |
| `UBINIT_MONGODB_AUTH` | `false` | 是否启用认证 |
| `UBINIT_MONGODB_USER` | `admin` | 管理员用户名 |
| `UBINIT_MONGODB_PASSWORD` | `""` | 留空=自动生成 |

---

## 19-22 Web 服务器

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_NGINX_ENABLE` | `false` | |
| `UBINIT_NGINX_SOURCE` | `apt` | `apt` / `official`（nginx.org） |
| `UBINIT_APACHE_ENABLE` | `false` | |
| `UBINIT_CADDY_ENABLE` | `false` | |
| `UBINIT_OPENRESTY_ENABLE` | `false` | |

---

## 23-25 监控

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_NETDATA_ENABLE` | `false` | |
| `UBINIT_NETDATA_PORT` | `19999` | |
| `UBINIT_NODE_EXPORTER_ENABLE` | `false` | |
| `UBINIT_NODE_EXPORTER_PORT` | `9100` | |
| `UBINIT_NODE_EXPORTER_VERSION` | `latest` | |
| `UBINIT_GRAFANA_AGENT_ENABLE` | `false` | |

---

## 26 Shell 美化 `UBINIT_SHELL_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_SHELL_BASH_COMPLETION` | `true` | |
| `UBINIT_SHELL_FASTFETCH` | `false` | 系统信息展示工具 |
| `UBINIT_SHELL_ZSH` | `false` | |
| `UBINIT_SHELL_OH_MY_ZSH` | `false` | 依赖 ZSH=true |
| `UBINIT_SHELL_STARSHIP` | `false` | 跨 shell 提示符 |

---

## 27 日志管理 `UBINIT_LOG_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_LOG_JOURNALD` | `true` | 配置 systemd-journald |
| `UBINIT_LOG_JOURNALD_MAX_SIZE` | `1G` | journald 最大磁盘占用 |
| `UBINIT_LOG_JOURNALD_MAX_DAYS` | `30` | 日志保留天数 |
| `UBINIT_LOG_LOGROTATE` | `true` | 配置 logrotate |

---

## 28 目录 `UBINIT_DIRS_*`

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `UBINIT_DIRS_ENABLE` | `true` | |
| `UBINIT_DIRS_LIST` | `/data /docker /backup /scripts /logs` | 目录列表（空格分隔） |
| `UBINIT_DIRS_MODE` | `0755` | 权限掩码 |
| `UBINIT_DIRS_OWNER` | `root:root` | 所有者 |
