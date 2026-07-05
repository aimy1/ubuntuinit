# 模块开发指南

本文档说明如何为 UbuntuInit 编写自定义模块。

---

## 模块接口规范

每个模块是一个独立的 Bash 文件，必须实现以下 **4 个函数**：

```bash
module_info()       # 模块元信息
module_check()      # 幂等检测（是否已安装）
module_install()    # 安装/配置逻辑
module_uninstall()  # 卸载/清理逻辑
```

可选函数：

```bash
module_rollback()   # 失败时的回滚逻辑（不定义则跳过）
```

---

## 完整模板

```bash
#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: <你的模块名>
# =============================================================================
# 文件     : modules/XX_your_module.sh
# 说明     : <一句话描述>
# 配置变量 : UBINIT_YOUR_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh
# =============================================================================

module_info() {
    echo "name:        your_module"
    echo "description: 你的模块描述"
}

# 幂等检测：若返回 0 则跳过 module_install()
# 返回: 0=已安装  1=未安装
module_check() {
    command -v your_command &>/dev/null
    # 或: service_is_active your_service
    # 或: [[ -f /etc/your_config ]]
}

module_install() {
    log_section "你的模块标题"

    # 1. 读取配置变量（有默认值）
    local enable="${UBINIT_YOUR_ENABLE:-false}"
    if [[ "${enable}" != "true" ]]; then
        log_info "跳过（UBINIT_YOUR_ENABLE=false）"
        return 0
    fi

    # 2. dry-run 支持（写操作前检查）
    if [[ "${UBINIT_DRY_RUN:-false}" == "true" ]]; then
        log_debug "[DRY-RUN] 将安装 your-package"
        return 0
    fi

    # 3. 执行安装（使用 lib 函数）
    apt_install your-package          # 安装包
    backup_file /etc/your/config      # 备份配置
    service_enable_start your-service # 启动服务

    log_success "你的模块安装完成"
    return 0
}

module_uninstall() {
    service_stop your-service 2>/dev/null || true
    apt_purge your-package
    rm -rf /etc/your
    log_success "你的模块已卸载"
}

# 可选：安装失败后的回滚逻辑
module_rollback() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    local latest
    latest="$(find "${backup_dir}" -name "your_config.*.bak" 2>/dev/null | sort -r | head -1)"
    [[ -n "${latest}" ]] && backup_restore_file "${latest}" /etc/your/config
}
```

---

## 文件命名规范

```
modules/XX_category_name.sh
```

- `XX`：两位数字序号（继续在 `28_` 之后编号）
- `category`：功能分类前缀（可选）
- `name`：模块名（小写下划线）

**示例：**
```
modules/29_db_clickhouse.sh
modules/30_monitor_prometheus.sh
modules/31_web_varnish.sh
```

---

## 可用的 lib 函数

### 日志 (`lib/logger.sh`)

```bash
log_info    "普通信息"
log_success "操作成功"
log_warning "警告信息"
log_error   "错误信息"
log_debug   "调试信息（VERBOSE=true 时显示）"
log_section "── 章节标题 ──"
log_step 1 5 "第 1 步，共 5 步"
```

### APT 包管理 (`lib/apt.sh`)

```bash
apt_install nginx redis-server        # 安装（自动等待 APT 锁）
apt_ensure_installed curl wget        # 幂等安装（跳过已安装）
apt_remove nginx                      # 卸载（保留配置）
apt_purge nginx                       # 彻底卸载（含配置）
apt_is_installed nginx                # 检测是否已安装（返回 0/1）
apt_update                            # apt-get update
apt_add_key "url" "/path/key.asc"    # 添加 GPG 密钥
apt_add_source "file.list" "deb ..." # 添加 APT 源
```

### Systemd 服务 (`lib/service.sh`)

```bash
service_start nginx
service_stop nginx
service_restart nginx
service_reload nginx                  # 重载配置（不支持则 restart）
service_enable nginx                  # 开机自启
service_enable_start nginx            # 开机自启 + 立即启动
service_is_active nginx               # 检测是否运行（返回 0/1）
service_daemon_reload                 # systemctl daemon-reload
service_install_unit "name" "..."     # 写入 .service 文件
service_show_log nginx 20             # 查看最近 20 行日志
```

### 网络 (`lib/network.sh`)

```bash
net_check_internet 5                  # 检测网络（超时 5s）
net_download "url" "/path" 60         # 下载文件（超时 60s）
net_fetch "url" 10                    # 获取 URL 内容到 stdout
net_port_listening 8080               # 检测端口是否监听
net_wait_port 8080 30                 # 等待端口开放（最多 30s）
```

### 备份 (`lib/backup.sh`)

```bash
backup_file "/etc/ssh/sshd_config" "ssh"   # 备份单个文件
backup_files "label" file1 file2            # 批量备份
backup_snapshot "nginx" /etc/nginx /var/www # tar 快照
backup_restore_file "/path/to/file.bak"     # 从备份恢复
```

### 工具 (`lib/utils.sh`)

```bash
util_ensure_dir "/path" "0755" "user:group"  # 确保目录存在
util_write_file "/path" "content"            # 原子写入文件
util_append_line "/path" "line content"      # 幂等追加行
util_set_config "/etc/conf" "Key" " value"   # 设置配置键值
util_cmd_exists curl                         # 检测命令是否存在
util_run_retry 3 5 curl http://...           # 带重试的命令
util_random_password 20                      # 生成随机密码
```

---

## 配置变量规范

在 `config/default.conf` 中为你的模块添加配置变量：

```bash
# ══════════════════════════════════════════
# 你的模块 (modules/29_your_module.sh)
# ══════════════════════════════════════════
UBINIT_YOUR_ENABLE=false         # 是否启用
UBINIT_YOUR_PORT=8080            # 端口
UBINIT_YOUR_VERSION="latest"     # 版本
UBINIT_YOUR_OPTION=""            # 其他选项
```

**命名规范：**
- 前缀：`UBINIT_` + 模块名大写 + `_`
- 全部大写，下划线分隔
- 布尔值：`true` / `false`（字符串）

---

## 开发流程

```bash
# 1. 创建模块文件
cp modules/06_network_tools.sh modules/29_my_module.sh

# 2. 实现 4 个接口函数

# 3. 在 config/default.conf 添加配置变量

# 4. ShellCheck 检查
shellcheck -x modules/29_my_module.sh

# 5. Dry-run 测试
sudo bash install.sh --modules "29_my_module" --dry-run

# 6. 实际测试
sudo bash install.sh --modules "29_my_module"

# 7. 测试卸载
sudo bash uninstall.sh --modules "29_my_module"
```

---

## 质量检查清单

在提交模块前，请确保：

- [ ] 实现了全部 4 个必须函数
- [ ] 所有配置从 `UBINIT_*` 变量读取（无硬编码）
- [ ] 写操作前检查 `UBINIT_DRY_RUN`
- [ ] 使用 lib 函数而非直接调用 `apt-get`/`systemctl`
- [ ] `module_check()` 正确实现幂等逻辑
- [ ] 修改系统配置前调用 `backup_file`
- [ ] 通过 `shellcheck -x` 无错误
- [ ] 添加了 `module_uninstall()` 清理逻辑
- [ ] 在 `config/default.conf` 添加了配置变量说明
