#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Apache HTTP Server
# =============================================================================
# 文件     : modules/20_web_apache.sh
# 说明     : 安装 Apache2，启用常用模块，检测与 Nginx 的端口冲突
# 配置变量 : UBINIT_APACHE_ENABLE
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/network.sh
# =============================================================================

module_info() {
    echo "name:        apache"
    echo "description: Apache HTTP Server"
}

module_check() {
    command -v apache2 &>/dev/null && service_is_active apache2
}

module_install() {
    log_section "Apache 安装"

    if [[ "${UBINIT_APACHE_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_APACHE_ENABLE=false）"
        return 0
    fi

    # 端口冲突警告（Nginx 或 Caddy 占用 80）
    if net_port_listening 80; then
        if service_is_active nginx 2>/dev/null; then
            log_warning "⚠ 检测到 Nginx 正在使用 80 端口，Apache 启动后可能冲突"
            log_warning "  建议先停止 Nginx 或修改 Apache 监听端口"
        elif service_is_active caddy 2>/dev/null; then
            log_warning "⚠ 检测到 Caddy 正在使用 80 端口"
        fi
    fi

    apt_install apache2 apache2-utils libapache2-mod-security2

    # 启用常用模块
    local mods=(rewrite ssl headers deflate expires proxy proxy_http proxy_balancer lbmethod_byrequests)
    local mod
    for mod in "${mods[@]}"; do
        a2enmod "${mod}" 2>/dev/null || log_debug "模块 ${mod} 启用失败（可能不支持）"
    done

    # 安全配置
    cat > /etc/apache2/conf-available/ubinit-security.conf <<'EOF'
# UbuntuInit Apache 安全配置
ServerTokens Prod
ServerSignature Off
TraceEnable Off
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
EOF
    a2enconf ubinit-security 2>/dev/null || true

    service_enable_start apache2

    local ver
    ver="$(apache2 -v 2>/dev/null | grep version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    log_success "Apache ${ver} 安装完成"
    return 0
}

module_uninstall() {
    service_stop apache2 2>/dev/null || true
    apt_purge apache2 apache2-utils apache2-bin libapache2-mod-security2 2>/dev/null || true
    rm -rf /etc/apache2
    log_success "Apache 已卸载"
}
