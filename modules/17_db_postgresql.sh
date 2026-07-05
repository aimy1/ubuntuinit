#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: PostgreSQL
# =============================================================================
# 文件     : modules/17_db_postgresql.sh
# 说明     : 安装 PostgreSQL（官方 PGDG 源），配置端口和 postgres 密码
# 配置变量 : UBINIT_POSTGRESQL_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        postgresql"
    echo "description: PostgreSQL 关系型数据库（PGDG 官方源）"
}

module_check() {
    command -v psql &>/dev/null && service_is_active postgresql
}

module_install() {
    log_section "PostgreSQL 安装"

    if [[ "${UBINIT_POSTGRESQL_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_POSTGRESQL_ENABLE=false）"
        return 0
    fi

    local version="${UBINIT_POSTGRESQL_VERSION:-16}"
    local port="${UBINIT_POSTGRESQL_PORT:-5432}"
    local pg_password="${UBINIT_POSTGRESQL_PASSWORD:-}"
    local pg_db="${UBINIT_POSTGRESQL_DB:-}"

    # 自动生成密码
    if [[ -z "${pg_password}" ]]; then
        pg_password="$(util_random_password 20)"
        log_warning "PostgreSQL postgres 密码已自动生成（请立即记录！）: ${pg_password}"
    fi

    # 确定架构和代号
    local arch
    case "${DETECT_ARCH:-$(uname -m)}" in
        amd64|x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac
    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

    # 添加 PGDG GPG 密钥
    log_info "添加 PostgreSQL PGDG 密钥..."
    util_ensure_dir /etc/apt/keyrings
    apt_add_key \
        "https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
        "/etc/apt/keyrings/postgresql.asc"

    # 添加 PGDG APT 源
    apt_add_source "pgdg.list" \
        "deb [arch=${arch} signed-by=/etc/apt/keyrings/postgresql.asc] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main"

    apt_update
    apt_install "postgresql-${version}" "postgresql-client-${version}"

    service_enable_start postgresql

    # 修改端口（若非默认）
    if [[ "${port}" != "5432" ]]; then
        local pg_conf="/etc/postgresql/${version}/main/postgresql.conf"
        if [[ -f "${pg_conf}" ]]; then
            backup_file "${pg_conf}" "postgresql"
            sed -i "s/^#*port = .*/port = ${port}/" "${pg_conf}"
            service_restart postgresql
        fi
    fi

    # 设置 postgres 超级用户密码
    su -c "psql -c \"ALTER USER postgres PASSWORD '${pg_password}';\"" postgres 2>/dev/null || \
        log_warning "设置 postgres 密码失败，请手动执行"

    # 创建数据库（若配置了且不为 postgres）
    if [[ -n "${pg_db}" && "${pg_db}" != "postgres" ]]; then
        su -c "createdb '${pg_db}'" postgres 2>/dev/null || \
            log_warning "数据库 ${pg_db} 创建失败（可能已存在）"
        log_info "数据库已创建: ${pg_db}"
    fi

    local ver
    ver="$(psql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+'  | head -1)"
    log_success "PostgreSQL ${ver} 安装完成  端口: ${port}"
    return 0
}

module_uninstall() {
    local version="${UBINIT_POSTGRESQL_VERSION:-16}"
    service_stop postgresql 2>/dev/null || true
    apt_purge "postgresql-${version}" "postgresql-client-${version}" \
        postgresql-common 2>/dev/null || true
    rm -rf /etc/postgresql /var/lib/postgresql /var/log/postgresql
    rm -f /etc/apt/sources.list.d/pgdg.list
    rm -f /etc/apt/keyrings/postgresql.asc
    log_success "PostgreSQL 已卸载"
}
