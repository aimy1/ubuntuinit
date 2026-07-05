#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: MySQL
# =============================================================================
# 文件     : modules/16_db_mysql.sh
# 说明     : 安装 MySQL Server，安全初始化（与 MariaDB 互斥）
# 配置变量 : UBINIT_MYSQL_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        mysql"
    echo "description: MySQL 关系型数据库（与 MariaDB 互斥）"
}

module_check() {
    (command -v mysqld &>/dev/null || dpkg -l mysql-server &>/dev/null 2>&1) && \
        service_is_active mysql
}

# 获取适配当前 Ubuntu 版本的 MySQL 包名
_mysql_package_name() {
    local os_ver
    os_ver="$(. /etc/os-release && echo "${VERSION_ID}")"
    case "${os_ver}" in
        "20.04") echo "mysql-server-8.0" ;;
        *)       echo "mysql-server"     ;;
    esac
}

# 修改 root 密码并执行安全初始化
_mysql_secure() {
    local password="$1"

    log_info "执行 MySQL 安全初始化..."

    # MySQL 8+ 首次启动后 root 无密码（auth_socket）
    mysql -u root <<SQL 2>/dev/null
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${password}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
}

module_install() {
    log_section "MySQL 安装"

    if [[ "${UBINIT_MYSQL_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_MYSQL_ENABLE=false）"
        return 0
    fi

    # 与 MariaDB 冲突检测
    if service_is_active mariadb 2>/dev/null; then
        log_error "检测到 MariaDB 正在运行，MySQL 与 MariaDB 不能同时安装"
        log_info  "提示: 如需 MySQL，请先在配置中禁用 MariaDB 模块"
        return 1
    fi

    local port="${UBINIT_MYSQL_PORT:-3306}"
    local password="${UBINIT_MYSQL_ROOT_PASSWORD:-}"

    # 自动生成密码
    if [[ -z "${password}" ]]; then
        password="$(util_random_password 20)"
        log_warning "MySQL root 密码已自动生成（请立即记录！）: ${password}"
    fi

    # 预设 debconf 参数（避免交互弹窗）
    local pkg_name
    pkg_name="$(_mysql_package_name)"

    echo "mysql-server mysql-server/root_password password ${password}" | debconf-set-selections
    echo "mysql-server mysql-server/root_password_again password ${password}" | debconf-set-selections

    apt_install "${pkg_name}" mysql-client

    service_enable_start mysql

    # 安全初始化
    if [[ "${UBINIT_MYSQL_SECURE:-true}" == "true" ]]; then
        _mysql_secure "${password}" || \
            log_warning "安全初始化部分失败，请手动检查"
    fi

    # 配置端口
    if [[ "${port}" != "3306" ]]; then
        cat > /etc/mysql/conf.d/ubinit.cnf <<EOF
[mysqld]
port = ${port}
EOF
        service_restart mysql
    fi

    local ver
    ver="$(mysql --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    log_success "MySQL ${ver} 安装完成  端口: ${port}"
    return 0
}

module_uninstall() {
    service_stop mysql 2>/dev/null || true
    apt_purge mysql-server mysql-client mysql-common mysql-server-core-* 2>/dev/null || true
    rm -rf /etc/mysql /var/lib/mysql /var/log/mysql
    log_success "MySQL 已卸载"
}
