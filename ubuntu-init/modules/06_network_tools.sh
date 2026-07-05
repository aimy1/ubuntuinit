#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 网络工具安装
# =============================================================================
# 文件     : modules/06_network_tools.sh
# 说明     : 批量安装运维常用网络工具包
# 配置变量 : UBINIT_NETTOOLS_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        nettools"
    echo "description: 安装运维常用工具包（curl/git/vim/btop/tmux等）"
}

module_check() {
    # 检测代表性工具是否均已安装
    util_cmds_exist curl wget git vim
}

module_install() {
    log_section "网络工具安装"

    if [[ "${UBINIT_NETTOOLS_ENABLE:-true}" != "true" ]]; then
        log_info "跳过（UBINIT_NETTOOLS_ENABLE=false）"
        return 0
    fi

    # 将空格分隔的包名列表转为数组
    local -a pkgs=()
    read -r -a pkgs <<< "${UBINIT_NETTOOLS_PACKAGES:-curl wget git vim nano btop htop tmux screen tree jq iftop iperf3 nmap tcpdump traceroute mtr net-tools dnsutils lsof unzip zip}"

    log_info "待安装工具包（共 ${#pkgs[@]} 个）: ${pkgs[*]}"

    # 更新包列表
    apt_update

    # 逐个检测，跳过已安装，批量安装未安装的
    local -a to_install=()
    local pkg
    for pkg in "${pkgs[@]}"; do
        if apt_is_installed "${pkg}"; then
            log_debug "已安装: ${pkg}"
        else
            to_install+=("${pkg}")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_success "所有工具包已安装，无需操作"
        return 0
    fi

    log_info "新安装: ${to_install[*]}"
    apt_install "${to_install[@]}" || {
        log_error "部分工具包安装失败"
        return 1
    }

    # 打印关键工具版本
    echo ""
    log_info "已安装工具版本:"
    local tool ver
    for tool in curl git vim; do
        if util_cmd_exists "${tool}"; then
            ver="$(util_cmd_version "${tool}")"
            log_info "  ${tool}: ${ver}"
        fi
    done

    log_success "网络工具包安装完成"
    return 0
}

module_uninstall() {
    log_warning "卸载网络工具包（谨慎操作）..."
    local -a pkgs=()
    read -r -a pkgs <<< "${UBINIT_NETTOOLS_PACKAGES:-}"
    [[ ${#pkgs[@]} -gt 0 ]] && apt_purge "${pkgs[@]}" 2>/dev/null || true
    log_info "网络工具包已卸载"
}
