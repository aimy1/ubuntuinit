#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: MongoDB
# =============================================================================
# 文件     : modules/18_db_mongodb.sh
# 说明     : 安装 MongoDB（官方源），可选启用认证
# 配置变量 : UBINIT_MONGODB_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        mongodb"
    echo "description: MongoDB 文档数据库（官方 APT 源）"
}

module_check() {
    command -v mongod &>/dev/null && service_is_active mongod
}

# 将 Ubuntu codename 映射到 MongoDB 支持的最近版本
_mongodb_codename() {
    local codename="$1"
    case "${codename}" in
        noble|oracular|plucky) echo "jammy" ;;  # 24.04/25.x 回退到 jammy
        jammy)  echo "jammy"  ;;
        focal)  echo "focal"  ;;
        bionic) echo "bionic" ;;
        *)      echo "jammy"  ;;
    esac
}

module_install() {
    log_section "MongoDB 安装"

    if [[ "${UBINIT_MONGODB_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_MONGODB_ENABLE=false）"
        return 0
    fi

    # 架构检测（仅支持 amd64/arm64）
    local arch
    case "${DETECT_ARCH:-$(uname -m)}" in
        amd64|x86_64)  arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *)
            log_error "MongoDB 不支持架构: ${DETECT_ARCH:-$(uname -m)}"
            return 1
            ;;
    esac

    local version="${UBINIT_MONGODB_VERSION:-7.0}"
    local port="${UBINIT_MONGODB_PORT:-27017}"
    local auth="${UBINIT_MONGODB_AUTH:-false}"
    local admin_user="${UBINIT_MONGODB_USER:-admin}"
    local admin_pass="${UBINIT_MONGODB_PASSWORD:-}"

    # 提取主版本（如 7.0）
    local major
    major="$(echo "${version}" | grep -oE '^[0-9]+\.[0-9]+')"

    # 确定 codename
    local raw_codename
    raw_codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
    local codename
    codename="$(_mongodb_codename "${raw_codename}")"

    log_info "MongoDB ${major} on Ubuntu ${raw_codename} (使用 ${codename} 源)..."

    # 添加 MongoDB GPG 密钥
    util_ensure_dir /etc/apt/keyrings
    apt_add_key \
        "https://www.mongodb.org/static/pgp/server-${major}.asc" \
        "/etc/apt/keyrings/mongodb-org-${major}.asc"

    # 添加 MongoDB APT 源
    apt_add_source "mongodb-org-${major}.list" \
        "deb [arch=${arch} signed-by=/etc/apt/keyrings/mongodb-org-${major}.asc] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/${major} multiverse"

    apt_update
    apt_install mongodb-org

    # 修改端口（若非默认）
    if [[ "${port}" != "27017" ]]; then
        sed -i "s/^  port: .*/  port: ${port}/" /etc/mongod.conf 2>/dev/null || \
            echo "  port: ${port}" >> /etc/mongod.conf
    fi

    service_enable_start mongod
    net_wait_port "${port}" 20

    # 启用认证（若配置）
    if [[ "${auth}" == "true" ]]; then
        if [[ -z "${admin_pass}" ]]; then
            admin_pass="$(util_random_password 20)"
            log_warning "MongoDB admin 密码已自动生成（请立即记录！）: ${admin_pass}"
        fi

        # 创建管理员用户
        log_info "创建 MongoDB 管理员用户: ${admin_user}..."
        mongosh --port "${port}" --quiet <<MONGOEOF 2>/dev/null || true
use admin
db.createUser({
  user: "${admin_user}",
  pwd: "${admin_pass}",
  roles: [{ role: "root", db: "admin" }]
})
MONGOEOF

        # 启用认证
        if grep -q "security:" /etc/mongod.conf 2>/dev/null; then
            sed -i '/^security:/,/^[^ ]/s/.*authorization:.*/  authorization: enabled/' \
                /etc/mongod.conf
        else
            printf '\nsecurity:\n  authorization: enabled\n' >> /etc/mongod.conf
        fi

        service_restart mongod
        log_info "MongoDB 认证已启用（用户: ${admin_user}）"
    fi

    local ver
    ver="$(mongod --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    log_success "MongoDB ${ver} 安装完成  端口: ${port}"
    return 0
}

module_uninstall() {
    service_stop mongod 2>/dev/null || true
    apt_purge mongodb-org mongodb-org-* 2>/dev/null || true
    local major="${UBINIT_MONGODB_VERSION:-7.0}"
    major="$(echo "${major}" | grep -oE '^[0-9]+\.[0-9]+')"
    rm -f "/etc/apt/sources.list.d/mongodb-org-${major}.list"
    rm -f "/etc/apt/keyrings/mongodb-org-${major}.asc"
    rm -rf /var/lib/mongodb /var/log/mongodb /etc/mongod.conf
    log_success "MongoDB 已卸载"
}
