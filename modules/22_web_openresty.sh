#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: OpenResty
# =============================================================================
# 文件     : modules/22_web_openresty.sh
# 说明     : 安装 OpenResty（Nginx + LuaJIT），官方 APT 源
# 配置变量 : UBINIT_OPENRESTY_ENABLE
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh
# =============================================================================

module_info() {
    echo "name:        openresty"
    echo "description: OpenResty（Nginx + LuaJIT）"
}

module_check() {
    command -v openresty &>/dev/null && service_is_active openresty
}

module_install() {
    log_section "OpenResty 安装"

    if [[ "${UBINIT_OPENRESTY_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_OPENRESTY_ENABLE=false）"
        return 0
    fi

    # 冲突检测
    if apt_is_installed nginx; then
        log_warning "检测到 nginx 已安装，OpenResty 与 nginx 可能冲突（共用 80/443 端口）"
        log_warning "建议先卸载 nginx: apt purge nginx"
    fi

    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

    util_ensure_dir /etc/apt/keyrings
    apt_add_key \
        "https://openresty.org/package/pubkey.gpg" \
        "/etc/apt/keyrings/openresty.asc"

    apt_add_source "openresty.list" \
        "deb [signed-by=/etc/apt/keyrings/openresty.asc] http://openresty.org/package/ubuntu ${codename} main"

    apt_update
    apt_install openresty

    service_enable_start openresty

    local ver
    ver="$(openresty -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+')"
    log_success "OpenResty ${ver} 安装完成"
    return 0
}

module_uninstall() {
    service_stop openresty 2>/dev/null || true
    apt_purge openresty 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/openresty.list
    rm -f /etc/apt/keyrings/openresty.asc
    log_success "OpenResty 已卸载"
}
