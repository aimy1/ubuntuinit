#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — Systemd 服务管理封装库
# =============================================================================
# 文件     : lib/service.sh
# 说明     : 封装 systemctl 操作，统一日志与 dry-run 支持
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

# =============================================================================
# 1. 状态检测
# =============================================================================

# 检查服务是否存在（unit 文件已加载）
# 参数: $1=服务名（含或不含 .service）
# 返回: 0=存在  1=不存在
service_exists() {
    local svc="$1"
    systemctl list-unit-files "${svc}" 2>/dev/null | grep -q "${svc}"
}

# 检查服务是否处于 active 状态
# 参数: $1=服务名
service_is_active() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# 检查服务是否设置为开机自启（enabled）
# 参数: $1=服务名
service_is_enabled() {
    systemctl is-enabled --quiet "$1" 2>/dev/null
}

# 获取服务当前状态字符串
# 参数: $1=服务名
# 输出: active | inactive | failed | unknown
service_status() {
    systemctl is-active "$1" 2>/dev/null || echo "unknown"
}

# =============================================================================
# 2. 生命周期控制
# =============================================================================

# 启动服务
# 参数: $1=服务名
service_start() {
    local svc="$1"
    log_info "启动服务: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl start ${svc}"; return 0
    }

    if systemctl start "${svc}" 2>&1; then
        log_success "服务已启动: ${svc}"
        return 0
    else
        log_error "服务启动失败: ${svc}"
        service_show_log "${svc}" 20
        return 1
    fi
}

# 停止服务
# 参数: $1=服务名
service_stop() {
    local svc="$1"
    log_info "停止服务: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl stop ${svc}"; return 0
    }

    systemctl stop "${svc}" 2>&1 || {
        log_warning "服务停止失败（可能未运行）: ${svc}"
    }
}

# 重启服务
# 参数: $1=服务名
service_restart() {
    local svc="$1"
    log_info "重启服务: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl restart ${svc}"; return 0
    }

    if systemctl restart "${svc}" 2>&1; then
        log_success "服务已重启: ${svc}"
        return 0
    else
        log_error "服务重启失败: ${svc}"
        service_show_log "${svc}" 20
        return 1
    fi
}

# 重新加载配置（不重启进程）
# 参数: $1=服务名
service_reload() {
    local svc="$1"
    log_info "重载配置: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl reload ${svc}"; return 0
    }

    # 尝试 reload，不支持时回退到 restart
    if systemctl reload "${svc}" 2>/dev/null; then
        log_success "配置已重载: ${svc}"
    else
        log_warning "服务不支持 reload，改用 restart: ${svc}"
        service_restart "${svc}"
    fi
}

# =============================================================================
# 3. 开机自启管理
# =============================================================================

# 启用开机自启
# 参数: $1=服务名
service_enable() {
    local svc="$1"
    log_info "启用开机自启: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl enable ${svc}"; return 0
    }

    systemctl enable "${svc}" 2>&1 | while IFS= read -r line; do
        log_debug "systemctl: ${line}"
    done
    log_success "开机自启已启用: ${svc}"
}

# 禁用开机自启
# 参数: $1=服务名
service_disable() {
    local svc="$1"
    log_info "禁用开机自启: ${svc}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] systemctl disable ${svc}"; return 0
    }

    systemctl disable "${svc}" 2>&1 | while IFS= read -r line; do
        log_debug "systemctl: ${line}"
    done
    log_success "开机自启已禁用: ${svc}"
}

# 启用 + 立即启动（最常用操作）
# 参数: $1=服务名
service_enable_start() {
    local svc="$1"
    service_enable "${svc}" && service_start "${svc}"
}

# =============================================================================
# 4. Daemon 重载
# =============================================================================

# 重载 systemd daemon（添加新 unit 文件后必须调用）
service_daemon_reload() {
    log_debug "重载 systemd daemon..."

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && return 0

    systemctl daemon-reload 2>&1 | while IFS= read -r line; do
        log_debug "daemon-reload: ${line}"
    done
}

# =============================================================================
# 5. 自定义 Unit 文件
# =============================================================================

# 写入 systemd unit 文件（.service）
# 参数: $1=unit 名（不含 .service）  $2=unit 文件内容
service_install_unit() {
    local name="$1"
    local content="$2"
    local unit_path="/etc/systemd/system/${name}.service"

    log_info "安装 systemd unit: ${name}.service"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] 写入 ${unit_path}"
        return 0
    }

    util_write_file "${unit_path}" "${content}" || return 1
    chmod 644 "${unit_path}"
    service_daemon_reload
    log_success "Unit 已安装: ${unit_path}"
}

# 删除 systemd unit 文件
# 参数: $1=unit 名（不含 .service）
service_uninstall_unit() {
    local name="$1"
    local unit_path="/etc/systemd/system/${name}.service"

    log_info "删除 systemd unit: ${name}.service"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] 删除 ${unit_path}"
        return 0
    }

    service_stop "${name}" 2>/dev/null || true
    service_disable "${name}" 2>/dev/null || true

    [[ -f "${unit_path}" ]] && rm -f "${unit_path}"
    service_daemon_reload
    log_success "Unit 已删除: ${name}"
}

# =============================================================================
# 6. 日志查看
# =============================================================================

# 输出服务最近 N 行日志（供排错使用）
# 参数: $1=服务名  $2=行数（默认 30）
service_show_log() {
    local svc="$1"
    local lines="${2:-30}"

    echo ""
    log_warning "── ${svc} 最近日志 (${lines} 行) ──────────────"
    journalctl -u "${svc}" --no-pager -n "${lines}" 2>/dev/null || true
    echo ""
}

# =============================================================================
# 7. 等待服务就绪
# =============================================================================

# 等待服务变为 active（带超时）
# 参数: $1=服务名  $2=超时秒数（默认 30）  $3=检测间隔（默认 1）
service_wait_active() {
    local svc="$1"
    local timeout="${2:-30}"
    local interval="${3:-1}"
    local elapsed=0

    log_debug "等待服务启动: ${svc}（最多 ${timeout}s）"

    while (( elapsed < timeout )); do
        service_is_active "${svc}" && return 0
        sleep "${interval}"
        (( elapsed += interval ))
    done

    log_error "服务未在 ${timeout}s 内启动: ${svc}"
    return 1
}
