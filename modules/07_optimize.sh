#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 系统性能优化
# =============================================================================
# 文件     : modules/07_optimize.sh
# 说明     : BBR、TCP 调优、Swap、IO 调度器、CPU Governor
# 配置变量 : UBINIT_OPTIMIZE_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        optimize"
    echo "description: BBR + TCP调优 + Swap + IO调度 + CPU Governor"
}

module_check() {
    # BBR 已启用视为已配置
    sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"
}

# 启用 BBR 拥塞控制
_optimize_bbr() {
    [[ "${UBINIT_OPTIMIZE_BBR:-true}" != "true" ]] && return 0

    log_info "配置 BBR 拥塞控制..."

    # 检测内核支持
    if ! modinfo tcp_bbr &>/dev/null; then
        log_warning "内核不支持 BBR，跳过"
        return 0
    fi

    echo "tcp_bbr" > /etc/modules-load.d/ubinit-bbr.conf
    modprobe tcp_bbr 2>/dev/null || true

    cat > /etc/sysctl.d/99-ubinit-bbr.conf <<'EOF'
# BBR 拥塞控制
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF

    sysctl --system &>/dev/null

    if sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
        log_success "BBR 已启用"
    else
        log_warning "BBR 启用后未能验证，将在重启后生效"
    fi
}

# TCP 网络调优
_optimize_tcp() {
    [[ "${UBINIT_OPTIMIZE_TCP:-true}" != "true" ]] && return 0

    log_info "应用 TCP 网络优化参数..."

    cat > /etc/sysctl.d/99-ubinit-tcp.conf <<'EOF'
# UbuntuInit TCP 性能优化

# 套接字队列最大长度
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535

# Socket 缓冲区
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864

# TIME_WAIT 优化
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30

# KeepAlive 优化
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 5

# SYN 队列
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_synack_retries = 2

# 本地端口范围
net.ipv4.ip_local_port_range = 10000 65000

# 文件描述符
fs.file-max = 1048576
fs.nr_open = 1048576
EOF

    sysctl --system &>/dev/null
    log_success "TCP 优化参数已应用"
}

# 配置 Swap
_optimize_swap() {
    [[ "${UBINIT_OPTIMIZE_SWAP:-true}" != "true" ]] && return 0

    # 已有 swap 则跳过
    if swapon --show 2>/dev/null | grep -q "^/"; then
        log_info "Swap 已存在，跳过"
        return 0
    fi

    log_info "配置 Swap..."

    # 计算 swap 大小
    local swap_size="${UBINIT_OPTIMIZE_SWAP_SIZE:-}"
    if [[ -z "${swap_size}" ]]; then
        # 自动计算：内存 1x，上限 8GB
        local mem_mb="${DETECT_MEM_TOTAL_MB:-1024}"
        local swap_mb=$(( mem_mb > 8192 ? 8192 : mem_mb ))
        swap_size="${swap_mb}M"
    fi

    local swapfile="/swapfile"

    # 创建 swapfile
    if util_cmd_exists fallocate; then
        fallocate -l "${swap_size}" "${swapfile}" || {
            log_warning "fallocate 失败，使用 dd 创建 swap..."
            local swap_mb
            swap_mb="$(util_parse_size_mb "${swap_size}")"
            dd if=/dev/zero of="${swapfile}" bs=1M count="${swap_mb}" status=none
        }
    else
        local swap_mb
        swap_mb="$(util_parse_size_mb "${swap_size}")"
        dd if=/dev/zero of="${swapfile}" bs=1M count="${swap_mb}" status=none
    fi

    chmod 600 "${swapfile}"
    mkswap "${swapfile}"
    swapon "${swapfile}"

    # 写入 fstab（避免重复）
    if ! grep -q "swapfile" /etc/fstab; then
        echo "/swapfile  none  swap  sw  0  0" >> /etc/fstab
    fi

    # 优化 swappiness
    echo "vm.swappiness=10" > /etc/sysctl.d/99-ubinit-swap.conf
    echo "vm.vfs_cache_pressure=50" >> /etc/sysctl.d/99-ubinit-swap.conf
    sysctl --system &>/dev/null

    log_success "Swap 已配置: ${swap_size}（swappiness=10）"
}

# 配置 IO 调度器
_optimize_io() {
    [[ "${UBINIT_OPTIMIZE_IO_SCHEDULER:-true}" != "true" ]] && return 0

    log_info "配置 IO 调度器..."

    cat > /etc/udev/rules.d/60-ubinit-scheduler.rules <<'EOF'
# UbuntuInit IO 调度器规则
# SSD/NVMe 使用 mq-deadline
ACTION=="add|change", KERNEL=="sd[a-z]*|nvme[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
# HDD 使用 bfq（更好的公平调度）
ACTION=="add|change", KERNEL=="sd[a-z]*", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

    udevadm control --reload-rules 2>/dev/null || true
    log_success "IO 调度器规则已配置（SSD: mq-deadline, HDD: bfq）"
}

# 配置 CPU Governor
_optimize_cpu() {
    local governor="${UBINIT_OPTIMIZE_CPU_GOVERNOR:-schedutil}"
    [[ -z "${governor}" ]] && return 0

    log_info "配置 CPU Governor: ${governor}..."

    # 安装 cpufrequtils（可选）
    apt_install cpufrequtils 2>/dev/null || true

    if util_cmd_exists cpufreq-set; then
        local cores cpu
        cores="$(nproc)"
        for (( cpu=0; cpu<cores; cpu++ )); do
            cpufreq-set -c "${cpu}" -g "${governor}" 2>/dev/null || true
        done
    fi

    # 持久化设置
    echo "GOVERNOR=\"${governor}\"" > /etc/default/cpufrequtils

    log_success "CPU Governor 已设置: ${governor}"
}

module_install() {
    log_section "系统性能优化"

    _optimize_bbr
    _optimize_tcp
    _optimize_swap
    _optimize_io
    _optimize_cpu

    log_success "系统性能优化完成"
    return 0
}

module_uninstall() {
    log_info "清除性能优化配置..."

    # 关闭并删除 swap
    if [[ -f /swapfile ]]; then
        swapoff /swapfile 2>/dev/null || true
        rm -f /swapfile
        sed -i '/swapfile/d' /etc/fstab
    fi

    # 删除 sysctl 配置
    rm -f /etc/sysctl.d/99-ubinit-bbr.conf
    rm -f /etc/sysctl.d/99-ubinit-tcp.conf
    rm -f /etc/sysctl.d/99-ubinit-swap.conf
    rm -f /etc/udev/rules.d/60-ubinit-scheduler.rules
    rm -f /etc/modules-load.d/ubinit-bbr.conf

    sysctl --system &>/dev/null || true
    log_success "性能优化配置已清除"
}
