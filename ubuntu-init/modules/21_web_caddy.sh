#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Caddy
# =============================================================================
# 文件     : modules/21_web_caddy.sh
# 说明     : 安装 Caddy（Cloudsmith 官方 deb 包），自动 HTTPS
# 配置变量 : UBINIT_CADDY_ENABLE
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh
# =============================================================================

module_info() {
    echo "name:        caddy"
    echo "description: Caddy Web 服务器（自动 HTTPS）"
}

module_check() {
    command -v caddy &>/dev/null && service_is_active caddy
}

module_install() {
    log_section "Caddy 安装"

    if [[ "${UBINIT_CADDY_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_CADDY_ENABLE=false）"
        return 0
    fi

    apt_ensure_installed debian-keyring debian-archive-keyring apt-transport-https curl

    util_ensure_dir /etc/apt/keyrings
    apt_add_key \
        "https://dl.cloudsmith.io/public/caddy/stable/gpg.key" \
        "/etc/apt/keyrings/caddy.asc"

    apt_add_source "caddy-stable.list" \
        "deb [signed-by=/etc/apt/keyrings/caddy.asc] https://dl.cloudsmith.io/public/caddy/stable/deb/any-version any-version main"

    apt_update
    apt_install caddy

    # 写入默认 Caddyfile（欢迎页）
    if [[ ! -f /etc/caddy/Caddyfile ]] || ! grep -q "ubinit" /etc/caddy/Caddyfile 2>/dev/null; then
        cat > /etc/caddy/Caddyfile <<'EOF'
# UbuntuInit 默认 Caddyfile
:80 {
    respond "Welcome to Caddy (UbuntuInit)" 200
    log {
        output file /var/log/caddy/access.log
    }
}
EOF
    fi

    util_ensure_dir /var/log/caddy "0755" "caddy:caddy" 2>/dev/null || \
        util_ensure_dir /var/log/caddy

    service_enable_start caddy

    local ver
    ver="$(caddy version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
    log_success "Caddy ${ver} 安装完成（支持自动 HTTPS）"
    return 0
}

module_uninstall() {
    service_stop caddy 2>/dev/null || true
    apt_purge caddy 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/caddy-stable.list
    rm -f /etc/apt/keyrings/caddy.asc
    rm -rf /etc/caddy /var/log/caddy
    log_success "Caddy 已卸载"
}
