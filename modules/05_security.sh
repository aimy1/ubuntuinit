#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 安全加固
# =============================================================================
# 文件     : modules/05_security.sh
# 说明     : UFW 防火墙、Fail2ban、sysctl 安全、ulimit、自动更新
# 配置变量 : UBINIT_SECURITY_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        security"
    echo "description: UFW + Fail2ban + sysctl + ulimit + 自动安全更新"
}

module_check() {
    # 检查 UFW 是否已启用
    if [[ "${UBINIT_SECURITY_UFW:-true}" == "true" ]]; then
        if ! ufw status 2>/dev/null | grep -q "Status: active"; then
            return 1
        fi
    fi

    # 检查 Fail2ban 是否已安装并运行
    if [[ "${UBINIT_SECURITY_FAIL2BAN:-true}" == "true" ]]; then
        if ! systemctl is-active --quiet fail2ban 2>/dev/null; then
            return 1
        fi
    fi

    return 0
}

# 配置 UFW 防火墙
_security_setup_ufw() {
    [[ "${UBINIT_SECURITY_UFW:-true}" != "true" ]] && return 0

    log_info "配置 UFW 防火墙..."
    apt_ensure_installed ufw

    # 检查 UFW 当前状态
    local ufw_status
    ufw_status="$(ufw status 2>/dev/null || echo "inactive")"
    local was_active=false
    if echo "${ufw_status}" | grep -q "Status: active"; then
        was_active=true
        log_info "UFW 当前已启用"
    fi

    # 重置规则（非 dry-run 模式）
    if [[ "${UBINIT_DRY_RUN:-false}" != "true" ]]; then
        # 备份当前规则
        if [[ "${was_active}" == "true" ]]; then
            log_info "备份当前 UFW 规则..."
            ufw status numbered > "${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}/ufw_rules.bak" 2>/dev/null || true
        fi

        # 重置规则
        log_info "重置 UFW 规则..."
        ufw --force reset &>/dev/null || {
            log_error "UFW 重置失败"
            return 1
        }

        # 默认策略
        local default_in="${UBINIT_SECURITY_UFW_DEFAULT_INCOMING:-deny}"
        local default_out="${UBINIT_SECURITY_UFW_DEFAULT_OUTGOING:-allow}"
        ufw default "${default_in}" incoming || {
            log_error "设置 UFW 默认入站策略失败"
            return 1
        }
        ufw default "${default_out}" outgoing || {
            log_error "设置 UFW 默认出站策略失败"
            return 1
        }

        # 允许配置的端口
        local port
        for port in ${UBINIT_SECURITY_UFW_ALLOW_PORTS:-22 80 443}; do
            port="$(util_trim "${port}")"
            if util_is_valid_port "${port}"; then
                ufw allow "${port}/tcp" comment "UbuntuInit" &>/dev/null || {
                    log_warning "UFW 允许端口 ${port}/tcp 失败"
                }
                log_debug "UFW 允许端口: ${port}/tcp"
            else
                log_warning "无效的端口号: ${port}"
            fi
        done

        # 启用 UFW
        log_info "启用 UFW..."
        ufw --force enable || {
            log_error "UFW 启用失败"
            return 1
        }

        # 验证状态
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            log_success "UFW 防火墙已启用"
            ufw status verbose 2>/dev/null | head -20
        else
            log_error "UFW 启用后状态异常"
            return 1
        fi
    fi

    return 0
}

# 配置 Fail2ban
_security_setup_fail2ban() {
    [[ "${UBINIT_SECURITY_FAIL2BAN:-true}" != "true" ]] && return 0

    log_info "配置 Fail2ban..."
    apt_install fail2ban || {
        log_error "Fail2ban 安装失败"
        return 1
    }

    local bantime="${UBINIT_SECURITY_FAIL2BAN_BANTIME:-3600}"
    local maxretry="${UBINIT_SECURITY_FAIL2BAN_MAXRETRY:-5}"
    local ssh_port="${UBINIT_SSH_PORT:-22}"

    # 验证参数
    if ! [[ "${bantime}" =~ ^[0-9]+$ ]]; then
        log_warning "无效的 bantime: ${bantime}，使用默认值 3600"
        bantime=3600
    fi
    if ! [[ "${maxretry}" =~ ^[0-9]+$ ]]; then
        log_warning "无效的 maxretry: ${maxretry}，使用默认值 5"
        maxretry=5
    fi

    # 备份现有配置
    if [[ -f /etc/fail2ban/jail.local ]]; then
        log_info "备份现有 Fail2ban 配置..."
        backup_file /etc/fail2ban/jail.local security
    fi

    # 写入配置
    cat > /etc/fail2ban/jail.local <<EOF
# UbuntuInit 生成 — $(date '+%Y-%m-%d %H:%M:%S')
[DEFAULT]
bantime   = ${bantime}
findtime  = 600
maxretry  = ${maxretry}
backend   = systemd

[sshd]
enabled   = true
port      = ${ssh_port}
filter    = sshd
maxretry  = ${maxretry}
EOF

    # 启用并启动服务
    if ! service_enable_start fail2ban; then
        log_error "Fail2ban 启动失败"
        return 1
    fi

    # 验证服务状态
    sleep 2
    if systemctl is-active --quiet fail2ban; then
        log_success "Fail2ban 已启动（封禁时长: ${bantime}s，最大重试: ${maxretry}次）"
    else
        log_warning "Fail2ban 服务状态异常"
    fi

    return 0
}

# sysctl 安全优化
_security_setup_sysctl() {
    [[ "${UBINIT_SECURITY_SYSCTL:-true}" != "true" ]] && return 0

    log_info "应用 sysctl 安全配置..."

    # 检查是否已存在配置
    if [[ -f /etc/sysctl.d/99-ubinit-security.conf ]]; then
        log_info "sysctl 安全配置已存在，跳过"
        return 0
    fi

    # 备份现有配置（如果存在）
    if [[ -f /etc/sysctl.conf ]]; then
        log_debug "备份现有 sysctl.conf..."
        backup_file /etc/sysctl.conf security
    fi

    cat > /etc/sysctl.d/99-ubinit-security.conf <<'EOF'
# UbuntuInit 安全加固 sysctl 配置
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

# ── 网络安全 ────────────────────────────────────────────────
# 启用 SYN Cookie 保护（防 SYN 洪水）
net.ipv4.tcp_syncookies = 1

# 启用反向路径过滤（防 IP 欺骗）
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# 忽略广播 ICMP（防 Smurf 攻击）
net.ipv4.icmp_echo_ignore_broadcasts = 1

# 禁止 ICMP 重定向
net.ipv4.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# 禁止源路由
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# 记录虚假来源数据包
net.ipv4.conf.all.log_martians = 1

# ── 内核安全 ────────────────────────────────────────────────
# 内存地址空间随机化（ASLR）
kernel.randomize_va_space = 2

# 禁止 core dump 含 setuid 程序
fs.suid_dumpable = 0

# 限制 dmesg 读取（非 root）
kernel.dmesg_restrict = 1

# 限制 ptrace 范围
kernel.yama.ptrace_scope = 1
EOF

    # 应用配置
    if ! sysctl --system &>/dev/null; then
        log_error "应用 sysctl 配置失败"
        return 1
    fi

    # 验证关键配置是否生效
    local syncookies
    syncookies="$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null || echo '')"
    if [[ "${syncookies}" == "1" ]]; then
        log_success "sysctl 安全配置已应用"
    else
        log_warning "sysctl 配置应用后验证失败"
    fi

    return 0
}

# ulimit 配置
_security_setup_ulimit() {
    [[ "${UBINIT_SECURITY_ULIMIT:-true}" != "true" ]] && return 0

    log_info "配置 ulimit 限制..."

    cat > /etc/security/limits.d/99-ubinit.conf <<'EOF'
# UbuntuInit ulimit 配置
# 最大文件描述符
*    soft    nofile    65535
*    hard    nofile    65535
root soft    nofile    65535
root hard    nofile    65535

# 最大进程数
*    soft    nproc     65535
*    hard    nproc     65535

# 禁止 core dump（可选）
# *  soft core 0
# *  hard core 0
EOF

    # pam_limits 确保被加载
    grep -q "pam_limits" /etc/pam.d/common-session 2>/dev/null || \
        echo "session required pam_limits.so" >> /etc/pam.d/common-session

    log_success "ulimit 配置完成（nofile: 65535，nproc: 65535）"
}

# 自动安全更新
_security_setup_auto_update() {
    [[ "${UBINIT_SECURITY_AUTO_UPDATE:-true}" != "true" ]] && return 0

    log_info "配置自动安全更新..."
    apt_install unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}";
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF

    service_enable_start unattended-upgrades
    log_success "自动安全更新已配置"
}

module_install() {
    log_section "安全加固"

    _security_setup_ufw
    _security_setup_fail2ban
    _security_setup_sysctl
    _security_setup_ulimit
    _security_setup_auto_update

    log_success "安全加固配置完成"
    return 0
}

module_uninstall() {
    log_info "禁用 UFW 和 Fail2ban..."
    ufw disable 2>/dev/null || true
    service_stop fail2ban 2>/dev/null || true
    apt_purge fail2ban ufw 2>/dev/null || true
    rm -f /etc/sysctl.d/99-ubinit-security.conf
    rm -f /etc/security/limits.d/99-ubinit.conf
    sysctl --system &>/dev/null || true
    log_success "安全配置已清除"
}
