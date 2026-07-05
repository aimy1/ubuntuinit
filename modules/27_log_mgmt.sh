#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 日志管理
# =============================================================================
# 文件     : modules/27_log_mgmt.sh
# 说明     : 配置 systemd-journald 持久化日志，优化 logrotate 策略
# 配置变量 : UBINIT_LOG_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/backup.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        log_mgmt"
    echo "description: systemd-journald 日志大小限制 + logrotate 策略"
}

module_check() {
    grep -q "SystemMaxUse" /etc/systemd/journald.conf 2>/dev/null
}

# 配置 journald
_log_setup_journald() {
    [[ "${UBINIT_LOG_JOURNALD:-true}" != "true" ]] && return 0

    local max_size="${UBINIT_LOG_JOURNALD_MAX_SIZE:-1G}"
    local max_days="${UBINIT_LOG_JOURNALD_MAX_DAYS:-30}"
    local conf="/etc/systemd/journald.conf"

    log_info "配置 systemd-journald（最大: ${max_size}，保留: ${max_days}天）..."
    backup_file "${conf}" "log_mgmt"

    cat > "${conf}" <<EOF
# UbuntuInit 生成 — $(date '+%Y-%m-%d %H:%M:%S')
[Journal]
# 持久化到磁盘（默认 volatile 只存内存）
Storage=persistent
# 压缩日志
Compress=yes
# 最大磁盘占用
SystemMaxUse=${max_size}
# 单个日志文件最大大小
SystemMaxFileSize=128M
# 最大保留时间
MaxRetentionSec=${max_days}day
# 限速（防止日志暴涨）
RateLimitInterval=30s
RateLimitBurst=10000
# 转发到 syslog（关闭以减少重复）
ForwardToSyslog=no
EOF

    service_restart systemd-journald 2>/dev/null || true

    # 立即清理超出大小的旧日志
    journalctl --vacuum-size="${max_size}" 2>/dev/null || true
    log_success "journald 配置完成"
}

# 配置 logrotate
_log_setup_logrotate() {
    [[ "${UBINIT_LOG_LOGROTATE:-true}" != "true" ]] && return 0

    log_info "配置 logrotate..."
    apt_ensure_installed logrotate

    cat > /etc/logrotate.d/ubinit <<'EOF'
# UbuntuInit 日志轮转规则

# UbuntuInit 安装日志
/var/log/ubuntu-init*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    dateext
}

# 应用程序通用规则（可按需添加具体路径）
/var/log/app/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 www-data www-data
    sharedscripts
    postrotate
        # systemctl reload nginx 2>/dev/null || true
        /bin/true
    endscript
}
EOF

    # 测试 logrotate 配置语法
    logrotate --debug /etc/logrotate.d/ubinit 2>&1 | \
        while IFS= read -r line; do log_debug "logrotate: ${line}"; done

    log_success "logrotate 规则已写入 /etc/logrotate.d/ubinit"
}

module_install() {
    log_section "日志管理配置"

    _log_setup_journald
    _log_setup_logrotate

    log_success "日志管理配置完成"
    return 0
}

module_uninstall() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    local latest_backup
    latest_backup="$(find "${backup_dir}/log_mgmt" -name "journald.conf.*.bak" 2>/dev/null | sort -r | head -1)"

    if [[ -n "${latest_backup}" ]]; then
        backup_restore_file "${latest_backup}" /etc/systemd/journald.conf
        service_restart systemd-journald 2>/dev/null || true
    fi

    rm -f /etc/logrotate.d/ubinit
    log_success "日志管理配置已清除"
}
