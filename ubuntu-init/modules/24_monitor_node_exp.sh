#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Prometheus Node Exporter
# =============================================================================
# 文件     : modules/24_monitor_node_exp.sh
# 说明     : 从 GitHub 下载 node_exporter 二进制，注册 systemd 服务
# 配置变量 : UBINIT_NODE_EXPORTER_ENABLE  UBINIT_NODE_EXPORTER_PORT  UBINIT_NODE_EXPORTER_VERSION
# 依赖     : lib/logger.sh  lib/service.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        node_exporter"
    echo "description: Prometheus Node Exporter（系统指标采集）"
}

module_check() {
    command -v node_exporter &>/dev/null || service_is_active node_exporter
}

# 从 GitHub API 获取最新版本号
_node_exporter_latest_version() {
    local ver
    ver="$(net_fetch \
        'https://api.github.com/repos/prometheus/node_exporter/releases/latest' 10 \
        2>/dev/null | grep '"tag_name"' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    echo "${ver#v}"   # 去掉前缀 v
}

module_install() {
    log_section "Prometheus Node Exporter 安装"

    if [[ "${UBINIT_NODE_EXPORTER_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_NODE_EXPORTER_ENABLE=false）"
        return 0
    fi

    local port="${UBINIT_NODE_EXPORTER_PORT:-9100}"
    local version="${UBINIT_NODE_EXPORTER_VERSION:-latest}"

    # 确定架构
    local arch
    case "${DETECT_ARCH:-$(uname -m)}" in
        amd64|x86_64)  arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac

    # 解析版本号
    if [[ "${version}" == "latest" ]]; then
        log_info "查询 node_exporter 最新版本..."
        version="$(_node_exporter_latest_version)"
        if [[ -z "${version}" ]]; then
            log_warning "无法获取最新版本，使用 1.8.2"
            version="1.8.2"
        fi
    fi

    local tarball="node_exporter-${version}.linux-${arch}.tar.gz"
    local url="https://github.com/prometheus/node_exporter/releases/download/v${version}/${tarball}"

    log_info "下载 node_exporter v${version} (${arch})..."
    net_download "${url}" "/tmp/${tarball}" 120 || {
        log_error "node_exporter 下载失败: ${url}"
        return 1
    }

    # 解压并安装二进制
    tar -xzf "/tmp/${tarball}" -C /tmp/
    mv -f "/tmp/node_exporter-${version}.linux-${arch}/node_exporter" /usr/local/bin/
    chmod +x /usr/local/bin/node_exporter

    # 清理临时文件
    rm -rf "/tmp/${tarball}" "/tmp/node_exporter-${version}.linux-${arch}"

    # 创建专用系统用户
    if ! id node_exporter &>/dev/null; then
        useradd -rs /bin/false node_exporter
    fi

    # 安装 systemd unit
    service_install_unit "node_exporter" "[Unit]
Description=Prometheus Node Exporter
Documentation=https://github.com/prometheus/node_exporter
After=network.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter \\
    --web.listen-address=:${port} \\
    --collector.systemd \\
    --collector.processes
Restart=on-failure
RestartSec=5s
SyslogIdentifier=node_exporter

[Install]
WantedBy=multi-user.target"

    service_enable_start node_exporter
    net_wait_port "${port}" 15

    local local_ip
    local_ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
    log_success "Node Exporter v${version} 安装完成"
    log_info "Metrics 地址: http://${local_ip}:${port}/metrics"
    return 0
}

module_uninstall() {
    service_stop node_exporter 2>/dev/null || true
    service_uninstall_unit node_exporter 2>/dev/null || true
    rm -f /usr/local/bin/node_exporter
    userdel node_exporter 2>/dev/null || true
    log_success "Node Exporter 已卸载"
}
