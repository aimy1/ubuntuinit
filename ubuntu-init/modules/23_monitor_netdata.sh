#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Netdata 监控
# =============================================================================
# 文件     : modules/23_monitor_netdata.sh
# 说明     : 通过官方 kickstart 脚本安装 Netdata 实时监控
# 配置变量 : UBINIT_NETDATA_ENABLE  UBINIT_NETDATA_PORT
# 依赖     : lib/logger.sh  lib/service.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        netdata"
    echo "description: Netdata 实时系统监控（Web UI）"
}

module_check() {
    command -v netdatacli &>/dev/null || service_is_active netdata
}

module_install() {
    log_section "Netdata 监控安装"

    if [[ "${UBINIT_NETDATA_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_NETDATA_ENABLE=false）"
        return 0
    fi

    local port="${UBINIT_NETDATA_PORT:-19999}"

    log_info "下载 Netdata 安装脚本..."
    net_download \
        "https://get.netdata.cloud/kickstart.sh" \
        "/tmp/netdata-kickstart.sh" 120 || {
        log_error "Netdata 安装脚本下载失败"
        return 1
    }

    log_info "执行 Netdata 安装（此步骤可能需要数分钟）..."
    bash /tmp/netdata-kickstart.sh \
        --non-interactive \
        --stable-channel \
        --disable-telemetry \
        2>&1 | while IFS= read -r line; do
            log_debug "netdata: ${line}"
        done

    rm -f /tmp/netdata-kickstart.sh

    # 修改端口（若非默认 19999）
    if [[ "${port}" != "19999" ]]; then
        local netdata_conf="/etc/netdata/netdata.conf"
        if [[ -f "${netdata_conf}" ]]; then
            if grep -q "port" "${netdata_conf}"; then
                sed -i "s/.*port.*/    port = ${port}/" "${netdata_conf}"
            else
                printf '\n[web]\n    port = %s\n' "${port}" >> "${netdata_conf}"
            fi
        fi
    fi

    service_enable_start netdata
    net_wait_port "${port}" 30

    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    log_success "Netdata 安装完成"
    log_info "访问地址: http://${local_ip}:${port}"
    return 0
}

module_uninstall() {
    # 优先使用 kickstart 的卸载功能
    if [[ -f /tmp/netdata-kickstart.sh ]]; then
        bash /tmp/netdata-kickstart.sh --uninstall 2>/dev/null || true
    fi

    service_stop netdata 2>/dev/null || true
    apt_purge netdata 2>/dev/null || true
    rm -rf /etc/netdata /var/lib/netdata /var/cache/netdata /var/log/netdata
    log_success "Netdata 已卸载"
}
