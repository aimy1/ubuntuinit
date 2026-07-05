#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 系统预检
# =============================================================================
# 文件     : modules/00_preflight.sh
# 说明     : 安装前置条件检测，任意关键项失败则终止流程
# 依赖     : lib/logger.sh  lib/detect.sh  lib/ui.sh
# =============================================================================

# 模块元信息
module_info() {
    echo "name:        preflight"
    echo "description: 系统环境预检（权限/版本/网络/资源）"
}

# 预检每次必须执行，不做幂等跳过
module_check() {
    return 1
}

# 执行系统预检
module_install() {
    log_section "系统环境预检"

    # 1. 执行全量系统检测
    detect_all || {
        log_error "系统检测失败，无法继续"
        return 1
    }

    # 2. Root 权限
    detect_assert_root || return 1

    # 3. Ubuntu 系统
    detect_assert_ubuntu || return 1

    # 4. 架构检测（支持 amd64/arm64，其他架构警告但继续）
    case "${DETECT_ARCH}" in
        amd64|arm64)
            log_debug "架构检测通过: ${DETECT_ARCH}"
            ;;
        *)
            log_warning "未经测试的架构: ${DETECT_ARCH}（仅官方支持 amd64/arm64）"
            ;;
    esac

    # 5. 网络连通（可跳过）
    if [[ "${UBINIT_SKIP_NET_CHECK:-false}" != "true" ]]; then
        detect_assert_internet || return 1
        detect_assert_apt_free || return 1
    else
        log_warning "已跳过网络和 APT 锁检测（UBINIT_SKIP_NET_CHECK=true）"
    fi

    # 6. 最小内存 512MB
    detect_assert_min_memory 512 || return 1

    # 7. 最小磁盘 2GB
    detect_assert_min_disk 2 || return 1

    # 8. 打印系统摘要
    detect_print_summary

    # 9. 交互模式下请求用户确认
    if [[ "${UBINIT_NON_INTERACTIVE:-false}" != "true" ]]; then
        if ! ui_confirm "系统检测通过，确认开始安装？" "yes"; then
            log_info "用户取消安装"
            return 1
        fi
    fi

    log_success "系统预检全部通过"
    return 0
}

# 预检模块无需卸载
module_uninstall() {
    log_info "预检模块无需卸载"
    return 0
}
