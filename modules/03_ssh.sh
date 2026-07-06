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
    local sshd_config="/etc/ssh/sshd_config"

    # 检查配置文件是否存在
    [[ -f "${sshd_config}" ]] || return 1

    # 检查端口配置
    if grep -q "^Port ${port}$" "${sshd_config}" 2>/dev/null; then
        return 0
    fi

    # 如果端口是 22，检查是否没有显式配置 Port（默认就是 22）
    if [[ "${port}" == "22" ]]; then
        if ! grep -q "^Port " "${sshd_config}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
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
    log_info "检查 SSH 服务..."
    apt_ensure_installed openssh-server openssh-client

    # 验证端口号有效性
    local port="${UBINIT_SSH_PORT:-22}"
    if ! util_is_valid_port "${port}"; then
        log_error "无效的 SSH 端口: ${port}"
        return 1
    fi

    # 备份原始配置
    log_info "备份 SSH 配置..."
    backup_file "${sshd_config}" "ssh" || {
        log_error "备份 sshd_config 失败"
        return 1
    }

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
    log_info "重启 SSH 服务..."
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

    # 验证 SSH 连接可用性
    log_info "验证 SSH 连接..."
    sleep 2
    if ! systemctl is-active --quiet "${svc}"; then
        log_warning "SSH 服务状态异常"
    fi

    # 若端口变更，更新 UFW 规则（先允许新端口，再删旧端口，避免封锁）
    if [[ "${port}" != "22" ]] && util_cmd_exists ufw; then
        log_info "更新防火墙规则（旧端口 22 → 新端口 ${port}）..."
        # Step 1: 先允许新端口连接
        if ufw allow "${port}/tcp" comment "UbuntuInit SSH" 2>/dev/null; then
            log_debug "UFW 已允许端口 ${port}/tcp"
            # Step 2: 确认新端口已就绪后再删除旧端口
            if net_wait_port "${port}" 5; then
                ufw delete allow 22/tcp 2>/dev/null || \
                    log_warning "UFW 删除旧端口 22 失败（可能未启用）"
            else
                log_warning "UFW: 新端口 ${port} 尚未就绪，保留旧端口 22 规则以备用"
            fi
        else
            log_warning "UFW 添加新端口 ${port} 失败，保留旧规则"
        fi
    fi

    log_success "SSH 配置完成"
    [[ "${port}" != "22" ]] && \
        log_warning "⚠  SSH 端口已变更为 ${port}，请确认新端口连接正常后再断开当前会话！"

    return 0
}

# 回滚：从最新备份恢复并重启 SSH
module_rollback() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}/ssh"
    local sshd_config="/etc/ssh/sshd_config"

    log_info "执行 SSH 配置回滚..."

    # 检查备份目录是否存在
    if [[ ! -d "${backup_dir}" ]]; then
        log_warning "备份目录不存在: ${backup_dir}"
        return 1
    fi

    # 查找最新的备份文件
    local latest
    latest="$(find "${backup_dir}" -name "sshd_config.*.bak" 2>/dev/null | sort -r | head -1)"

    if [[ -z "${latest}" ]]; then
        log_warning "未找到 SSH 备份文件，无法回滚"
        return 1
    fi

    log_info "使用备份恢复: ${latest}"

    # 恢复备份文件
    if ! backup_restore_file "${latest}" "${sshd_config}"; then
        log_error "恢复 SSH 配置失败"
        return 1
    fi

    # 重启 SSH 服务
    local svc
    svc="$(_ssh_service_name)"
    if ! service_restart "${svc}"; then
        log_error "重启 SSH 服务失败"
        return 1
    fi

    # 验证服务状态
    sleep 2
    if systemctl is-active --quiet "${svc}"; then
        log_success "SSH 配置已成功回滚"
        return 0
    else
        log_error "SSH 服务重启后状态异常"
        return 1
    fi
}

module_uninstall() {
    module_rollback
}
