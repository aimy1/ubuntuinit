#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: MariaDB
# =============================================================================
# 文件     : modules/15_db_mariadb.sh
# 说明     : 安装 MariaDB，执行安全初始化，设置 root 密码
# 配置变量 : UBINIT_MARIADB_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        mariadb"
    echo "description: MariaDB 关系型数据库"
}

module_check() {
    command -v mysql &>/dev/null && service_is_active mariadb
}

# 执行安全初始化（等效 mysql_secure_installation）
_mariadb_secure() {
    local password="$1"

    log_info "执行 MariaDB 安全初始化..."

    mysql -u root <<SQL 2>/dev/null
ALTER USER 'root'@'localhost' IDENTIFIED BY '${password}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
}

module_install() {
    log_section "MariaDB 安装"

    if [[ "${UBINIT_MARIADB_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_MARIADB_ENABLE=false）"
        return 0
    fi

    local port="${UBINIT_MARIADB_PORT:-3306}"
    local password="${UBINIT_MARIADB_ROOT_PASSWORD:-}"

    apt_install mariadb-server mariadb-client

    service_enable_start mariadb

    # 安全配置
    if [[ "${UBINIT_MARIADB_SECURE:-true}" == "true" ]]; then
        # 自动生成密码（若未配置）
        if [[ -z "${password}" ]]; then
            password="$(util_random_password 20)"
            log_warning "MariaDB root 密码已自动生成（请立即记录！）: ${password}"
        fi

        _mariadb_secure "${password}" || \
            log_warning "安全初始化执行部分失败，请手动检查"
    fi

    # 修改端口（若非默认）
    if [[ "${port}" != "3306" ]]; then
        cat > /etc/mysql/conf.d/ubinit.cnf <<EOF
[mysqld]
port = ${port}
EOF
        service_restart mariadb
    fi

    local ver
    ver="$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    log_success "MariaDB ${ver} 安装完成  端口: ${port}"
    return 0
}

module_uninstall() {
    service_stop mariadb 2>/dev/null || true
    apt_purge mariadb-server mariadb-client mariadb-common 2>/dev/null || true
    rm -rf /etc/mysql /var/lib/mysql
    log_success "MariaDB 已卸载（数据目录已清除）"
}
