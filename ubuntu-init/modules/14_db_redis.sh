#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Redis
# =============================================================================
# 文件     : modules/14_db_redis.sh
# 说明     : 安装并配置 Redis，支持密码、最大内存、淘汰策略
# 配置变量 : UBINIT_REDIS_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/backup.sh  lib/network.sh
# =============================================================================

module_info() {
    echo "name:        redis"
    echo "description: Redis 缓存数据库"
}

module_check() {
    command -v redis-cli &>/dev/null && service_is_active redis-server
}

module_install() {
    log_section "Redis 安装"

    if [[ "${UBINIT_REDIS_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_REDIS_ENABLE=false）"
        return 0
    fi

    local port="${UBINIT_REDIS_PORT:-6379}"
    local password="${UBINIT_REDIS_PASSWORD:-}"
    local maxmemory="${UBINIT_REDIS_MAXMEMORY:-256mb}"
    local maxmemory_policy="${UBINIT_REDIS_MAXMEMORY_POLICY:-allkeys-lru}"
    local conf="/etc/redis/redis.conf"

    apt_install redis-server redis-tools

    # 备份原始配置
    backup_file "${conf}" "redis"

    log_info "配置 Redis（端口: ${port}）..."

    # 使用 sed 精确修改配置项
    # 端口
    sed -i "s/^port .*/port ${port}/" "${conf}"

    # 绑定地址（保持 127.0.0.1，安全优先）
    sed -i "s/^bind .*/bind 127.0.0.1 -::1/" "${conf}"

    # 密码
    if [[ -n "${password}" ]]; then
        if grep -q "^requirepass" "${conf}"; then
            sed -i "s/^requirepass .*/requirepass ${password}/" "${conf}"
        else
            echo "requirepass ${password}" >> "${conf}"
        fi
    else
        sed -i 's/^requirepass/# requirepass/' "${conf}"
    fi

    # 最大内存
    if grep -q "^maxmemory " "${conf}"; then
        sed -i "s/^maxmemory .*/maxmemory ${maxmemory}/" "${conf}"
    else
        echo "maxmemory ${maxmemory}" >> "${conf}"
    fi

    # 淘汰策略
    if grep -q "^maxmemory-policy" "${conf}"; then
        sed -i "s/^maxmemory-policy .*/maxmemory-policy ${maxmemory_policy}/" "${conf}"
    else
        echo "maxmemory-policy ${maxmemory_policy}" >> "${conf}"
    fi

    # 持久化 + systemd 监控
    sed -i "s/^supervised .*/supervised systemd/" "${conf}" 2>/dev/null || \
        echo "supervised systemd" >> "${conf}"

    # 启动服务
    service_enable_start redis-server

    # 等待端口就绪
    net_wait_port "${port}" 15

    # 验证连接
    local ping_args=("-p" "${port}")
    [[ -n "${password}" ]] && ping_args+=("-a" "${password}")
    local result
    result="$(redis-cli "${ping_args[@]}" ping 2>/dev/null)"
    if [[ "${result}" == "PONG" ]]; then
        log_success "Redis 安装完成  端口: ${port}  maxmemory: ${maxmemory}"
    else
        log_warning "Redis 启动但 PING 未得到 PONG 响应（检查密码或端口）"
    fi

    return 0
}

module_uninstall() {
    service_stop redis-server 2>/dev/null || true
    apt_purge redis-server redis-tools 2>/dev/null || true
    rm -rf /etc/redis /var/lib/redis /var/log/redis
    log_success "Redis 已卸载"
}
