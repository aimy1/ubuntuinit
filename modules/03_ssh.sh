#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: SSH 安全配置
# =============================================================================
# 文件     : modules/03_ssh.sh
# 说明     : 修改 SSH 端口、认证策略，自动备份，验证失败自动回滚
# 配置变量 : UBINIT_SSH_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/backup.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        ssh"
    echo "description: SSH 端口/认证/安全加固，失败自动回滚"
}

module_check() {
    local port="${UBINIT_SSH_PORT:-22}"
    grep -q "^Port ${port}" /etc/ssh/sshd_config 2>/dev/null
}

# 获取实际 SSH 服务名（Ubuntu 上可能是 ssh 或 sshd）
_ssh_service_name() {
    systemctl list-unit-files ssh.service &>/dev/null && echo "ssh" || echo "sshd"
}

module_install() {
    log_section "SSH 安全配置"

    if [[ "${UBINIT_SSH_ENABLE:-true}" != "true" ]]; then
        log_info "跳过（UBINIT_SSH_ENABLE=false）"
        return 0
    fi

    local sshd_config="/etc/ssh/sshd_config"

    # 确保 SSH 服务已安装
    apt_ensure_installed openssh-server openssh-client

    # 备份原始配置
    backup_file "${sshd_config}" "ssh" || {
        log_error "备份 sshd_config 失败"
        return 1
    }

    local port="${UBINIT_SSH_PORT:-22}"
    local permit_root="${UBINIT_SSH_PERMIT_ROOT_LOGIN:-prohibit-password}"
    local password_auth="${UBINIT_SSH_PASSWORD_AUTH:-no}"
    local pubkey_auth="${UBINIT_SSH_PUBKEY_AUTH:-yes}"
    local max_tries="${UBINIT_SSH_MAX_AUTH_TRIES:-3}"
    local alive_interval="${UBINIT_SSH_CLIENT_ALIVE_INTERVAL:-300}"

    log_info "配置 SSH 参数..."

    # 修改配置文件各选项
    util_set_config "${sshd_config}" "Port"                    " ${port}"                ' '
    util_set_config "${sshd_config}" "PermitRootLogin"         " ${permit_root}"         ' '
    util_set_config "${sshd_config}" "PasswordAuthentication"  " ${password_auth}"       ' '
    util_set_config "${sshd_config}" "PubkeyAuthentication"    " ${pubkey_auth}"         ' '
    util_set_config "${sshd_config}" "MaxAuthTries"            " ${max_tries}"           ' '
    util_set_config "${sshd_config}" "ClientAliveInterval"     " ${alive_interval}"      ' '
    util_set_config "${sshd_config}" "ClientAliveCountMax"     " 3"                      ' '
    util_set_config "${sshd_config}" "UseDNS"                  " no"                     ' '
    util_set_config "${sshd_config}" "X11Forwarding"           " no"                     ' '
    util_set_config "${sshd_config}" "PrintMotd"               " no"                     ' '

    # 语法验证
    log_info "验证 SSH 配置语法..."
    if ! sshd -t 2>&1; then
        log_error "SSH 配置语法错误，正在自动回滚..."
        module_rollback
        return 1
    fi

    # 重启服务
    local svc
    svc="$(_ssh_service_name)"
    service_restart "${svc}" || {
        log_error "SSH 服务重启失败，正在回滚..."
        module_rollback
        return 1
    }

    # 等待新端口就绪
    log_info "等待 SSH 端口 ${port} 就绪..."
    if ! net_wait_port "${port}" 30; then
        log_error "SSH 端口 ${port} 未就绪，正在回滚..."
        module_rollback
        return 1
    fi

    # 若端口变更，更新 UFW 规则
    if [[ "${port}" != "22" ]] && util_cmd_exists ufw; then
        ufw allow "${port}/tcp" comment "UbuntuInit SSH" 2>/dev/null || true
        ufw delete allow 22/tcp 2>/dev/null || true
    fi

    log_success "SSH 配置完成"
    [[ "${port}" != "22" ]] && \
        log_warning "⚠  SSH 端口已变更为 ${port}，请更新防火墙规则并测试连接后再断开当前会话！"

    return 0
}

# 回滚：从最新备份恢复并重启 SSH
module_rollback() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    local latest
    latest="$(find "${backup_dir}/ssh" -name "sshd_config.*.bak" 2>/dev/null | sort -r | head -1)"

    if [[ -n "${latest}" ]]; then
        backup_restore_file "${latest}" /etc/ssh/sshd_config && \
            service_restart "$(_ssh_service_name)" && \
            log_success "SSH 配置已回滚"
    else
        log_warning "未找到 SSH 备份，无法回滚"
    fi
}

module_uninstall() {
    module_rollback
}
