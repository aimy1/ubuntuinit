#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 安装报告生成库
# =============================================================================
# 文件     : lib/report.sh
# 说明     : 安装完成后采集系统状态，生成终端摘要 + Markdown 报告文件
# 依赖     : lib/logger.sh  lib/utils.sh  lib/detect.sh  lib/network.sh
# =============================================================================

# =============================================================================
# 1. 状态采集工具
# =============================================================================

# 获取软件版本（命令不存在返回 "-"）
# 参数: $1=命令  $2=版本参数（默认 --version）
_report_version() {
    local cmd="$1"
    local flag="${2:---version}"

    if ! command -v "${cmd}" &>/dev/null; then
        echo "-"
        return
    fi

    "${cmd}" "${flag}" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || echo "已安装"
}

# 获取 systemd 服务状态（带颜色符号）
# 参数: $1=服务名
_report_service_status() {
    local svc="$1"

    if ! systemctl list-unit-files "${svc}" &>/dev/null 2>&1; then
        echo "未安装"
        return
    fi

    if systemctl is-active --quiet "${svc}" 2>/dev/null; then
        echo "✓ 运行中"
    else
        echo "✗ 未运行"
    fi
}

# 获取纯文本服务状态（用于 Markdown，无 ANSI 颜色）
_report_service_status_plain() {
    local svc="$1"

    if ! systemctl list-unit-files "${svc}" &>/dev/null 2>&1; then
        echo "未安装"
        return
    fi

    systemctl is-active --quiet "${svc}" 2>/dev/null && echo "运行中" || echo "未运行"
}

# =============================================================================
# 2. 数据采集
# =============================================================================

# 采集所有状态数据（写入关联数组）
_report_collect() {
    # 基础系统
    _R_OS="$(. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-Unknown}" || echo 'Unknown')"
    _R_KERNEL="$(uname -r)"
    _R_ARCH="$(uname -m)"
    _R_HOSTNAME="$(hostname -s 2>/dev/null)"
    _R_UPTIME="$(uptime -p 2>/dev/null | sed 's/^up //' || echo '-')"

    # 硬件
    _R_CPU_CORES="$(nproc 2>/dev/null || echo '?')"
    _R_CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo '-')"
    _R_MEM_TOTAL="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo '?')"
    _R_MEM_USED="$(free -h 2>/dev/null | awk '/^Mem:/{print $3}' || echo '?')"
    _R_MEM_FREE="$(free -h 2>/dev/null | awk '/^Mem:/{print $7}' || echo '?')"
    _R_SWAP_TOTAL="$(free -h 2>/dev/null | awk '/^Swap:/{print $2}' || echo '?')"
    _R_DISK_TOTAL="$(df -h / 2>/dev/null | awk 'NR==2{print $2}' || echo '?')"
    _R_DISK_USED="$(df -h  / 2>/dev/null | awk 'NR==2{print $3}' || echo '?')"
    _R_DISK_FREE="$(df -h  / 2>/dev/null | awk 'NR==2{print $4}' || echo '?')"
    _R_DISK_PCT="$(df -h   / 2>/dev/null | awk 'NR==2{print $5}' || echo '?')"

    # 网络
    _R_IP_LOCAL="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '-')"
    _R_IP_PUBLIC="$(net_public_ip 3 2>/dev/null || echo '-')"

    # 服务版本
    _R_DOCKER_VER="$(_report_version docker)"
    _R_COMPOSE_VER="$(docker compose version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo '-')"
    _R_PYTHON_VER="$(_report_version python3)"
    _R_NODE_VER="$(_report_version node)"
    _R_JAVA_VER="$(_report_version java -version)"
    _R_GO_VER="$(_report_version go version)"
    _R_RUST_VER="$(_report_version rustc)"
    _R_NGINX_VER="$(_report_version nginx -v)"
    _R_REDIS_VER="$(_report_version redis-cli)"

    # 服务状态
    _R_SSH_STATUS="$(_report_service_status ssh)"
    _R_UFW_STATUS="$(ufw status 2>/dev/null | head -1 | awk '{print $2}' || echo '-')"
    _R_DOCKER_STATUS="$(_report_service_status docker)"
    _R_NGINX_STATUS="$(_report_service_status nginx)"
    _R_REDIS_STATUS="$(_report_service_status redis-server)"
    _R_FAIL2BAN_STATUS="$(_report_service_status fail2ban)"

    # BBR
    _R_BBR="$(sysctl net.ipv4.tcp_congestion_control 2>/dev/null | awk '{print $3}' || echo '-')"

    # 时间
    _R_REPORT_TIME="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    _R_INSTALL_DURATION="${UBINIT_INSTALL_DURATION:-未知}"
}

# =============================================================================
# 3. 终端摘要输出
# =============================================================================

# 打印一行报告数据（标签 + 值）
_rprint() {
    local label="$1"
    local value="$2"
    local color="${3:-${LOG_CLR_WHITE:-}}"
    printf "  ${LOG_CLR_MUTED:-}%-22s${LOG_CLR_RESET:-} ${color}%s${LOG_CLR_RESET:-}\n" \
        "${label}" "${value}"
}

# 打印分隔标题行
_rheader() {
    local title="$1"
    echo ""
    printf "  ${LOG_CLR_SECTION:-}${LOG_CLR_BOLD:-}◆ %s${LOG_CLR_RESET:-}\n" "${title}"
    printf "  %s\n" "$(printf '─%.0s' $(seq 1 50))"
}

# 在终端输出完整安装报告摘要
report_print_summary() {
    echo ""
    echo ""
    printf "  ${LOG_CLR_SUCCESS:-}${LOG_CLR_BOLD:-}╔══════════════════════════════════════════════╗${LOG_CLR_RESET:-}\n"
    printf "  ${LOG_CLR_SUCCESS:-}${LOG_CLR_BOLD:-}║      UbuntuInit 安装报告  %-18s║${LOG_CLR_RESET:-}\n" "${_R_REPORT_TIME}"
    printf "  ${LOG_CLR_SUCCESS:-}${LOG_CLR_BOLD:-}╚══════════════════════════════════════════════╝${LOG_CLR_RESET:-}\n"

    _rheader "系统基础"
    _rprint "操作系统:"     "${_R_OS}"
    _rprint "内核版本:"     "${_R_KERNEL}"
    _rprint "系统架构:"     "${_R_ARCH}"
    _rprint "主机名:"       "${_R_HOSTNAME}"
    _rprint "运行时长:"     "${_R_UPTIME}"

    _rheader "硬件资源"
    _rprint "CPU:"          "${_R_CPU_CORES} 核 · ${_R_CPU_MODEL:0:30}"
    _rprint "内存:"         "${_R_MEM_FREE} 可用 / ${_R_MEM_TOTAL} 总计"
    _rprint "Swap:"         "${_R_SWAP_TOTAL}"
    _rprint "磁盘 (/):"     "${_R_DISK_FREE} 可用 / ${_R_DISK_TOTAL} 总 (${_R_DISK_PCT} 已用)"

    _rheader "网络"
    _rprint "本机 IP:"      "${_R_IP_LOCAL}"
    _rprint "公网 IP:"      "${_R_IP_PUBLIC}"
    _rprint "BBR:"          "${_R_BBR}"

    _rheader "服务状态"
    _rprint "SSH:"          "${_R_SSH_STATUS}"
    _rprint "UFW 防火墙:"   "${_R_UFW_STATUS}"
    _rprint "Fail2ban:"     "${_R_FAIL2BAN_STATUS}"
    _rprint "Docker:"       "${_R_DOCKER_STATUS}"
    _rprint "Nginx:"        "${_R_NGINX_STATUS}"
    _rprint "Redis:"        "${_R_REDIS_STATUS}"

    _rheader "软件版本"
    _rprint "Docker:"       "${_R_DOCKER_VER}  (Compose: ${_R_COMPOSE_VER})"
    _rprint "Python:"       "${_R_PYTHON_VER}"
    _rprint "Node.js:"      "${_R_NODE_VER}"
    _rprint "Java:"         "${_R_JAVA_VER}"
    _rprint "Go:"           "${_R_GO_VER}"
    _rprint "Rust:"         "${_R_RUST_VER}"
    _rprint "Nginx:"        "${_R_NGINX_VER}"
    _rprint "Redis:"        "${_R_REDIS_VER}"

    echo ""
    log_success "安装完成！报告已保存到: ${_R_REPORT_FILE:-未知}"
    echo ""
}

# =============================================================================
# 4. Markdown 报告生成
# =============================================================================

# 生成 Markdown 格式安装报告文件
_report_generate_markdown() {
    local report_file="$1"

    cat > "${report_file}" <<MARKDOWN
# UbuntuInit 安装报告

> 生成时间: ${_R_REPORT_TIME}
> 安装耗时: ${_R_INSTALL_DURATION}

---

## 系统基础

| 项目 | 值 |
|------|----|
| 操作系统 | ${_R_OS} |
| 内核版本 | ${_R_KERNEL} |
| 系统架构 | ${_R_ARCH} |
| 主机名   | ${_R_HOSTNAME} |
| 运行时长 | ${_R_UPTIME} |

---

## 硬件资源

| 项目 | 值 |
|------|----|
| CPU 核心 | ${_R_CPU_CORES} 核 |
| CPU 型号 | ${_R_CPU_MODEL} |
| 内存 | ${_R_MEM_FREE} 可用 / ${_R_MEM_TOTAL} 总计 |
| Swap | ${_R_SWAP_TOTAL} |
| 磁盘 (/) | ${_R_DISK_FREE} 可用 / ${_R_DISK_TOTAL} 总计 (${_R_DISK_PCT} 已用) |

---

## 网络

| 项目 | 值 |
|------|----|
| 本机 IP  | ${_R_IP_LOCAL} |
| 公网 IP  | ${_R_IP_PUBLIC} |
| TCP BBR  | ${_R_BBR} |

---

## 服务状态

| 服务 | 状态 |
|------|------|
| SSH        | $(_report_service_status_plain ssh) |
| UFW 防火墙 | ${_R_UFW_STATUS} |
| Fail2ban   | $(_report_service_status_plain fail2ban) |
| Docker     | $(_report_service_status_plain docker) |
| Nginx      | $(_report_service_status_plain nginx) |
| Redis      | $(_report_service_status_plain redis-server) |

---

## 软件版本

| 软件 | 版本 |
|------|------|
| Docker         | ${_R_DOCKER_VER} |
| Docker Compose | ${_R_COMPOSE_VER} |
| Python         | ${_R_PYTHON_VER} |
| Node.js        | ${_R_NODE_VER} |
| Java           | ${_R_JAVA_VER} |
| Go             | ${_R_GO_VER} |
| Rust           | ${_R_RUST_VER} |
| Nginx          | ${_R_NGINX_VER} |
| Redis          | ${_R_REDIS_VER} |

---

## 安装模块记录

**成功:** ${UBINIT_SUCCESS_MODULES[*]:-无}

**跳过:** ${UBINIT_SKIPPED_MODULES[*]:-无}

**失败:** ${UBINIT_FAILED_MODULES[*]:-无}

---

*由 UbuntuInit v${SCRIPT_VERSION:-1.0.0} 自动生成*
MARKDOWN
}

# =============================================================================
# 5. 报告主入口（供 install.sh 调用）
# =============================================================================

# 生成完整报告（终端输出 + Markdown 文件）
report_generate() {
    log_info "正在生成安装报告..."

    # 计算安装耗时
    if [[ -n "${UBINIT_START_TIME:-}" ]]; then
        local end_time
        end_time="$(date +%s)"
        local elapsed=$(( end_time - UBINIT_START_TIME ))
        UBINIT_INSTALL_DURATION="$(util_format_duration "${elapsed}")"
    fi

    # 采集数据
    _report_collect

    # 报告文件路径
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    _R_REPORT_FILE="/var/log/ubuntu-init-report-${timestamp}.md"

    # 生成 Markdown
    _report_generate_markdown "${_R_REPORT_FILE}" 2>/dev/null || \
        log_warning "Markdown 报告写入失败，仅显示终端摘要"

    # 输出终端摘要
    report_print_summary
}
