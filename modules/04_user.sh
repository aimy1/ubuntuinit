#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 用户管理
# =============================================================================
# 文件     : modules/04_user.sh
# 说明     : 创建管理员用户、加入 sudo 组、导入 SSH 公钥
# 配置变量 : UBINIT_USER_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        user"
    echo "description: 创建管理员用户、sudo 权限、SSH 公钥导入"
}

module_check() {
    local username="${UBINIT_USER_NAME:-ubuntu}"
    [[ "${UBINIT_USER_CREATE:-false}" == "true" ]] && id "${username}" &>/dev/null
}

module_install() {
    log_section "用户管理"

    if [[ "${UBINIT_USER_CREATE:-false}" != "true" ]]; then
        log_info "跳过用户创建（UBINIT_USER_CREATE=false）"
        return 0
    fi

    local username="${UBINIT_USER_NAME:-ubuntu}"

    # 校验用户名
    if ! util_is_valid_username "${username}"; then
        log_error "无效的用户名: ${username}（3-32位，字母数字下划线横线）"
        return 1
    fi

    # 创建用户（已存在则跳过）
    if id "${username}" &>/dev/null; then
        log_info "用户已存在: ${username}"
    else
        log_info "创建用户: ${username}"
        useradd -m -s /bin/bash -c "UbuntuInit Admin" "${username}" || {
            log_error "用户创建失败: ${username}"
            return 1
        }
        log_success "用户已创建: ${username}"
    fi

    # 加入 sudo 组
    if [[ "${UBINIT_USER_SUDO:-true}" == "true" ]]; then
        usermod -aG sudo "${username}"

        # 写入 sudoers.d（NOPASSWD，方便自动化）
        local sudoers_file="/etc/sudoers.d/${username}"
        echo "${username} ALL=(ALL) NOPASSWD:ALL" > "${sudoers_file}"
        chmod 440 "${sudoers_file}"
        log_success "用户 ${username} 已加入 sudo 组（NOPASSWD）"
    fi

    # 获取用户家目录
    local home_dir
    home_dir="$(getent passwd "${username}" | cut -d: -f6)"

    # 导入 SSH 公钥
    local ssh_dir="${home_dir}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"
    local has_key=false

    # 优先从变量导入
    if [[ -n "${UBINIT_USER_AUTHORIZED_KEYS:-}" ]]; then
        util_ensure_dir "${ssh_dir}" "0700" "${username}:${username}"
        echo "${UBINIT_USER_AUTHORIZED_KEYS}" >> "${auth_keys}"
        has_key=true
        log_success "SSH 公钥已从变量导入"
    fi

    # 其次从文件导入
    if [[ -n "${UBINIT_USER_AUTHORIZED_KEYS_FILE:-}" ]] && \
       [[ -f "${UBINIT_USER_AUTHORIZED_KEYS_FILE}" ]]; then
        util_ensure_dir "${ssh_dir}" "0700" "${username}:${username}"
        cat "${UBINIT_USER_AUTHORIZED_KEYS_FILE}" >> "${auth_keys}"
        has_key=true
        log_success "SSH 公钥已从文件导入: ${UBINIT_USER_AUTHORIZED_KEYS_FILE}"
    fi

    # 设置权限
    if [[ "${has_key}" == "true" ]]; then
        chmod 600 "${auth_keys}"
        chown "${username}:${username}" "${auth_keys}"
    fi

    log_success "用户 ${username} 配置完成（home: ${home_dir}）"
    return 0
}

module_uninstall() {
    local username="${UBINIT_USER_NAME:-ubuntu}"

    # 安全保护：禁止删除 root
    if [[ "${username}" == "root" ]]; then
        log_error "禁止删除 root 用户"
        return 1
    fi

    log_warning "删除用户: ${username}"
    userdel -r "${username}" 2>/dev/null || log_warning "用户删除失败（可能不存在）"
    rm -f "/etc/sudoers.d/${username}"
    log_success "用户 ${username} 已删除"
}
