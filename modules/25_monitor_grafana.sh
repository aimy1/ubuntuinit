#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Grafana Alloy（原 Grafana Agent）
# =============================================================================
# 文件     : modules/25_monitor_grafana.sh
# 说明     : 安装 Grafana Alloy（遥测数据收集管道）
# 配置变量 : UBINIT_GRAFANA_AGENT_ENABLE
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh
# =============================================================================

module_info() {
    echo "name:        grafana_alloy"
    echo "description: Grafana Alloy（Metrics/Logs/Traces 数据管道）"
}

module_check() {
    command -v alloy &>/dev/null && service_is_active alloy
}

module_install() {
    log_section "Grafana Alloy 安装"

    if [[ "${UBINIT_GRAFANA_AGENT_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_GRAFANA_AGENT_ENABLE=false）"
        return 0
    fi

    apt_ensure_installed gpg curl

    util_ensure_dir /etc/apt/keyrings
    apt_add_key \
        "https://apt.grafana.com/gpg.key" \
        "/etc/apt/keyrings/grafana.asc"

    apt_add_source "grafana.list" \
        "deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main"

    apt_update
    apt_install alloy

    # 写入默认配置（仅收集本机 node_exporter 指标）
    util_ensure_dir /etc/alloy
    if [[ ! -f /etc/alloy/config.alloy ]]; then
        cat > /etc/alloy/config.alloy <<'EOF'
// UbuntuInit 默认 Alloy 配置
// 本地 Prometheus 指标抓取示例

prometheus.scrape "local_node" {
  targets = [{"__address__" = "localhost:9100"}]
  forward_to = [prometheus.remote_write.default.receiver]
}

prometheus.remote_write "default" {
  endpoint {
    // 替换为你的 Prometheus / Grafana Cloud 地址
    url = "http://localhost:9090/api/v1/write"
  }
}
EOF
        log_info "默认 Alloy 配置已写入 /etc/alloy/config.alloy（请按需修改远端地址）"
    fi

    service_enable_start alloy

    local ver
    ver="$(alloy --version 2>/dev/null | head -1)"
    log_success "Grafana Alloy 安装完成: ${ver}"
    return 0
}

module_uninstall() {
    service_stop alloy 2>/dev/null || true
    apt_purge alloy 2>/dev/null || true
    rm -f /etc/apt/sources.list.d/grafana.list
    rm -f /etc/apt/keyrings/grafana.asc
    rm -rf /etc/alloy
    log_success "Grafana Alloy 已卸载"
}
