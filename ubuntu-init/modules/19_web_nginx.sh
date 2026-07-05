#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Nginx
# =============================================================================
# 文件     : modules/19_web_nginx.sh
# 说明     : 安装 Nginx（apt 或 nginx.org 官方源），启用服务
# 配置变量 : UBINIT_NGINX_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        nginx"
    echo "description: Nginx Web 服务器"
}

module_check() {
    command -v nginx &>/dev/null && service_is_active nginx
}

module_install() {
    log_section "Nginx 安装"

    if [[ "${UBINIT_NGINX_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_NGINX_ENABLE=false）"
        return 0
    fi

    local source="${UBINIT_NGINX_SOURCE:-apt}"

    case "${source}" in
        official)
            log_info "从 nginx.org 官方源安装..."

            local arch
            case "${DETECT_ARCH:-$(uname -m)}" in
                amd64|x86_64)  arch="amd64" ;;
                arm64|aarch64) arch="arm64" ;;
                *) arch="amd64" ;;
            esac
            local codename
            codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

            util_ensure_dir /etc/apt/keyrings
            apt_add_key \
                "https://nginx.org/keys/nginx_signing.key" \
                "/etc/apt/keyrings/nginx.asc"

            apt_add_source "nginx-official.list" \
                "deb [arch=${arch} signed-by=/etc/apt/keyrings/nginx.asc] http://nginx.org/packages/ubuntu ${codename} nginx"

            apt_update
            apt_install nginx
            ;;
        apt|*)
            log_info "从 Ubuntu 官方仓库安装 Nginx..."
            apt_install nginx
            ;;
    esac

    # 启用并启动
    service_enable_start nginx

    # 基础安全配置（写入 conf.d）
    cat > /etc/nginx/conf.d/ubinit-security.conf <<'EOF'
# UbuntuInit — Nginx 安全头
server_tokens off;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
EOF

    nginx -t 2>&1 | while IFS= read -r line; do log_debug "nginx-t: ${line}"; done

    local ver
    ver="$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    log_success "Nginx ${ver} 安装完成（源: ${source}）"
    return 0
}

module_uninstall() {
    service_stop nginx 2>/dev/null || true
    apt_purge nginx nginx-common nginx-full nginx-core 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/nginx-official.list
    rm -f /etc/apt/keyrings/nginx.asc
    rm -rf /etc/nginx
    log_success "Nginx 已卸载"
}
