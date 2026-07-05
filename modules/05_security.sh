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
    [[ "${UBINIT_SECURITY_UFW:-true}" == "true" ]] && \
        ufw status 2>/dev/null | grep -q "Status: active"
}

# 配置 UFW 防火墙
_security_setup_ufw() {
    [[ "${UBINIT_SECURITY_UFW:-true}" != "true" ]] && return 0

    log_info "配置 UFW 防火墙..."
    apt_ensure_installed ufw

    # 重置规则（非 dry-run 模式）
    if [[ "${UBINIT_DRY_RUN:-false}" != "true" ]]; then
        ufw --force reset &>/dev/null

        # 默认策略
        ufw default "${UBINIT_SECURITY_UFW_DEFAULT_INCOMING:-deny}"   incoming
        ufw default "${UBINIT_SECURITY_UFW_DEFAULT_OUTGOING:-allow}"  outgoing

        # 允许配置的端口
        local port
        for port in ${UBINIT_SECURITY_UFW_ALLOW_PORTS:-22 80 443}; do
            port="$(util_trim "${port}")"
            if util_is_valid_port "${port}"; then
                ufw allow "${port}/tcp" comment "UbuntuInit" &>/dev/null
                log_debug "UFW 允许端口: ${port}/tcp"
            fi
        done

        ufw --force enable
        ufw status verbose
    fi

    log_success "UFW 防火墙已启用"
}

# 配置 Fail2ban
_security_setup_fail2ban() {
    [[ "${UBINIT_SECURITY_FAIL2BAN:-true}" != "true" ]] && return 0

    log_info "配置 Fail2ban..."
    apt_install fail2ban

    local bantime="${UBINIT_SECURITY_FAIL2BAN_BANTIME:-3600}"
    local maxretry="${UBINIT_SECURITY_FAIL2BAN_MAXRETRY:-5}"
    local ssh_port="${UBINIT_SSH_PORT:-22}"

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

    service_enable_start fail2ban
    log_success "Fail2ban 已启动（封禁时长: ${bantime}s，最大重试: ${maxretry}次）"
}

# sysctl 安全优化
_security_setup_sysctl() {
    [[ "${UBINIT_SECURITY_SYSCTL:-true}" != "true" ]] && return 0

    log_info "应用 sysctl 安全配置..."

    cat > /etc/sysctl.d/99-ubinit-security.conf <<'EOF'
# UbuntuInit 安全加固 sysctl 配置

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

    sysctl --system &>/dev/null
    log_success "sysctl 安全配置已应用"
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
