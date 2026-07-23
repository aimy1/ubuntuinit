# UbuntuInit

<div align="center">

```
 ██╗   ██╗██████╗ ██╗   ██╗███╗   ██╗████████╗██╗   ██╗    ██╗███╗   ██╗██╗████████╗
 ██║   ██║██╔══██╗██║   ██║████╗  ██║╚══██╔══╝██║   ██║    ██║████╗  ██║██║╚══██╔══╝
 ██║   ██║██████╔╝██║   ██║██╔██╗ ██║   ██║   ██║   ██║    ██║██╔██╗ ██║██║   ██║   
 ██║   ██║██╔══██╗██║   ██║██║╚██╗██║   ██║   ██║   ██║    ██║██║╚██╗██║██║   ██║   
 ╚██████╔╝██████╔╝╚██████╔╝██║ ╚████║   ██║   ╚██████╔╝    ██║██║ ╚████║██║   ██║   
  ╚═════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═══╝   ╚═╝    ╚═════╝     ╚═╝╚═╝  ╚═══╝╚═╝   ╚═╝  
```

**Ubuntu Server 专业一键初始化框架**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-20.04%20%7C%2022.04%20%7C%2024.04-orange.svg)](https://ubuntu.com)
[![Arch](https://img.shields.io/badge/Arch-amd64%20%7C%20arm64-green.svg)]()
[![ShellCheck](https://img.shields.io/badge/ShellCheck-passing-brightgreen.svg)]()

</div>

---

## 📋 项目简介

UbuntuInit 是一个**模块化、可扩展的 Ubuntu Server 初始化框架**，面向运维工程师和 DevOps 团队。

不同于简单的 Shell 脚本，UbuntuInit 遵循开源项目质量标准：

- 🎯 **方向键交互 TUI**：无需记忆命令，全程鼠标替代键盘
- 🧩 **模块化架构**：29 个独立模块，按需选择
- 🔄 **幂等执行**：多次运行结果一致，安全无副作用
- 📝 **完整日志**：双路输出（终端彩色 + 文件存档）
- 🛡️ **自动回滚**：配置修改失败自动恢复
- 🤖 **无人值守**：支持全静默批量部署
- 🧪 **质量保证**：遵循 ShellCheck 最佳实践

---

## 🖥️ 支持环境

| 项目 | 支持范围 |
|------|----------|
| **操作系统** | Ubuntu Server 20.04 / 22.04 / 24.04 / 26.04 LTS |
| **架构** | `amd64` (x86_64) · `arm64` (aarch64) |
| **运行环境** | 物理机 · KVM · VMware · Docker · 云服务器 |
| **云平台** | AWS · GCP · Azure · 阿里云 · 腾讯云 |

---

## ⚡ 快速开始

### 方式一：极速一键安装（最简推荐）

只需在终端中复制并执行以下任一命令，即可通过网络自动完成代码拉取并自动配置 `ubinit` / `ugames` 全局指令：

```bash
# 使用 curl 管道直接执行
curl -fsSL https://raw.githubusercontent.com/aimy1/ubuntuinit/main/setup.sh | sudo bash

# 或者使用 wget 管道执行
wget -qO- https://raw.githubusercontent.com/aimy1/ubuntuinit/main/setup.sh | sudo bash
```

### 方式二：手动克隆本地安装

```bash
# 1. 克隆仓库到本地
git clone https://github.com/aimy1/ubuntuinit.git
cd ubuntuinit

# 2. 运行一键配置脚本部署全局命令
sudo bash setup.sh
```

### 方式三：极速单次启动（免安装指令）

如果你不需要将 `ubinit` 注册为系统命令，而只想执行一次初始化，只需：

```bash
sudo bash install.sh
```

### ⚙️ 配置文件与命令行高级操作

```bash
# 复制并编辑自定义配置
cp config/custom.conf.example config/custom.conf
vim config/custom.conf

# 1. 无人值守非交互模式
sudo bash install.sh --config config/custom.conf --non-interactive

# 2. 仅执行指定模块 (如系统与 Docker)
sudo bash install.sh --modules "system,docker"

# 3. Dry-run 预演模拟执行
sudo bash install.sh --dry-run
```

---

## 📦 模块列表

### 🏗️ 基础系统

| 模块 | 说明 | 默认 |
|------|------|:----:|
| `00_preflight` | 系统预检（权限/版本/资源/网络） | ✅ 必选 |
| `01_system` | APT更新、时区、NTP、Locale、Hostname | ✅ |
| `02_mirror` | APT 镜像源替换（国内加速） | ⚙️ 可选 |
| `03_ssh` | SSH 端口/认证/安全加固 | ✅ |
| `04_user` | 创建管理员用户、sudo、公钥导入 | ⚙️ |

### 🛡️ 安全与性能

| 模块 | 说明 | 默认 |
|------|------|:----:|
| `05_security` | UFW + Fail2ban + sysctl + ulimit | ✅ |
| `06_network_tools` | curl/git/vim/btop/tmux 等工具包 | ✅ |
| `07_optimize` | BBR + TCP调优 + Swap + IO调度器 | ✅ |

### 🐳 容器

| 模块 | 说明 | 默认 |
|------|------|:----:|
| `08_docker` | Docker CE + Compose Plugin + Buildx | ⚙️ |

### 💻 开发环境

| 模块 | 说明 | 方式 |
|------|------|------|
| `09_dev_python` | Python 3 | apt / pyenv |
| `10_dev_node` | Node.js | nvm / nodesource / apt |
| `11_dev_java` | Java JDK | apt / SDKMAN |
| `12_dev_go` | Go 语言 | 官方 tar.gz |
| `13_dev_rust` | Rust 工具链 | rustup |

### 🗄️ 数据库

| 模块 | 说明 |
|------|------|
| `14_db_redis` | Redis（密码/maxmemory） |
| `15_db_mariadb` | MariaDB（安全初始化） |
| `16_db_mysql` | MySQL（MariaDB 互斥） |
| `17_db_postgresql` | PostgreSQL（PGDG 官方源） |
| `18_db_mongodb` | MongoDB（认证可选） |

### 🌐 Web 服务器

| 模块 | 说明 |
|------|------|
| `19_web_nginx` | Nginx（apt/官方源） |
| `20_web_apache` | Apache HTTP Server |
| `21_web_caddy` | Caddy（自动 HTTPS） |
| `22_web_openresty` | OpenResty（Nginx+LuaJIT） |

### 📊 监控

| 模块 | 说明 |
|------|------|
| `23_monitor_netdata` | Netdata 实时监控 |
| `24_monitor_node_exp` | Prometheus Node Exporter |
| `25_monitor_grafana` | Grafana Alloy |

### 🔧 系统管理

| 模块 | 说明 |
|------|------|
| `26_shell` | Zsh/Oh-My-Zsh/Starship/Fastfetch |
| `27_log_mgmt` | journald + logrotate |
| `28_directories` | 标准运维目录结构 |

---

## 📁 项目结构

```
ubuntu-init/
├── install.sh              # 主入口脚本
├── uninstall.sh            # 卸载脚本
├── demo_ui.sh              # TUI 演示脚本
│
├── config/
│   ├── default.conf        # 默认配置（所有选项含注释）
│   └── custom.conf.example # 用户自定义配置模板
│
├── lib/                    # 公共函数库
│   ├── logger.sh           # 日志系统（5级别 + 进度条）
│   ├── ui.sh               # TUI 交互库（方向键菜单）
│   ├── utils.sh            # 通用工具函数
│   ├── detect.sh           # 系统检测（OS/虚拟化/云/资源）
│   ├── apt.sh              # APT 包管理封装
│   ├── service.sh          # Systemd 服务管理
│   ├── network.sh          # 网络工具（下载/连通/端口）
│   ├── backup.sh           # 备份与回滚
│   └── report.sh           # 安装报告生成
│
├── modules/                # 业务模块（29个）
│   ├── 00_preflight.sh
│   ├── 01_system.sh
│   └── ...
│
├── docs/
│   ├── configuration.md    # 配置参考
│   ├── modules.md          # 模块开发指南
│   └── troubleshooting.md  # 故障排查
│
├── tests/
│   └── shellcheck.sh       # 代码质量检查
│
├── assets/
│   └── banner.txt          # ASCII Banner
│
├── .shellcheckrc           # ShellCheck 规则
├── .editorconfig           # 编辑器格式规范
└── README.md
```

---

## ⚙️ 配置说明

所有配置均在 `config/custom.conf` 中设置。完整配置项请参考 [`config/default.conf`](config/default.conf)。

```bash
# 常用配置示例

# 系统
UBINIT_SYSTEM_TIMEZONE="Asia/Shanghai"
UBINIT_SYSTEM_NTP_SERVERS="ntp.aliyun.com ntp1.aliyun.com"
UBINIT_SYSTEM_LOCALE="zh_CN.UTF-8"
UBINIT_SYSTEM_HOSTNAME="my-server"

# 软件源
UBINIT_MIRROR_ENABLE=true
UBINIT_MIRROR_APT="aliyun"         # aliyun/tencent/huawei/ustc/tsinghua

# SSH
UBINIT_SSH_PORT=2222
UBINIT_SSH_PERMIT_ROOT_LOGIN="no"
UBINIT_SSH_PASSWORD_AUTH="no"

# 用户
UBINIT_USER_CREATE=true
UBINIT_USER_NAME="deploy"
UBINIT_USER_SUDO=true

# Docker
UBINIT_DOCKER_ENABLE=true
UBINIT_DOCKER_REGISTRY_MIRROR_SOURCE="aliyun"

# 数据库
UBINIT_REDIS_ENABLE=true
UBINIT_REDIS_PASSWORD="your-strong-password"
UBINIT_MARIADB_ENABLE=true
```

---

## 🎮 TUI 交互说明

| 组件 | 按键 | 功能 |
|------|------|------|
| **单选菜单** | `↑` `↓` | 移动光标 |
| | `Enter` | 确认选择 |
| | `q` | 退出/返回 |
| **复选列表** | `↑` `↓` | 移动光标 |
| | `Space` | 勾选/取消 |
| | `A` | 全选 |
| | `N` | 全清 |
| | `Enter` | 确认提交 |
| **确认框** | `←` `→` | 切换 是/否 |
| | `Enter` | 确认 |

---

## 🔄 卸载

```bash
sudo bash uninstall.sh
```

卸载脚本会反序执行已安装模块的 `module_uninstall()` 函数，并从备份中恢复修改的配置文件。

---

## 🧪 代码质量

```bash
# 运行 ShellCheck 检查所有脚本
bash tests/shellcheck.sh

# 或手动检查单个文件
shellcheck -x install.sh lib/*.sh modules/*.sh
```

---

## 📄 许可证

MIT License © 2024 UbuntuInit Contributors

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request。

1. Fork 本仓库
2. 新建模块文件（参考 `docs/modules.md`）
3. 通过 ShellCheck 检查
4. 提交 PR

---

<div align="center">

**Made with ❤️ for Linux SRE & DevOps Engineers**
# by: aisaniya
</div>
