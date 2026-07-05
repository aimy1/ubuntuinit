#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 网络检测工具库
# =============================================================================
# 文件     : lib/network.sh
# 说明     : 网络连通性检测、DNS、端口、下载等网络相关工具函数
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

# =============================================================================
# 1. 连通性检测
# =============================================================================

# 检测互联网连接（同时尝试多个目标，任意一个成功即可）
# 参数: $1=超时秒数（默认 5）
# 返回: 0=已连接  1=无法连接
net_check_internet() {
    local timeout="${1:-5}"
    local -a targets=(
        "https://1.1.1.1"
        "https://8.8.8.8"
        "https://www.baidu.com"
    )

    local target
    for target in "${targets[@]}"; do
        if curl -sf --connect-timeout "${timeout}" --max-time "$(( timeout * 2 ))" \
            "${target}" &>/dev/null 2>&1; then
            log_debug "网络连通（via ${target}）"
            return 0
        fi
    done

    # 回退：ping 检测
    if ping -c1 -W"${timeout}" 8.8.8.8 &>/dev/null 2>&1; then
        log_debug "网络连通（via ping 8.8.8.8）"
        return 0
    fi

    log_debug "网络连通检测失败"
    return 1
}

# 检测 DNS 解析是否正常
# 参数: $1=测试域名（默认 cloudflare.com）
# 返回: 0=正常  1=异常
net_check_dns() {
    local domain="${1:-cloudflare.com}"

    if getent hosts "${domain}" &>/dev/null 2>&1; then
        log_debug "DNS 解析正常（${domain}）"
        return 0
    fi

    if host -W3 "${domain}" &>/dev/null 2>&1; then
        log_debug "DNS 解析正常（host ${domain}）"
        return 0
    fi

    if nslookup "${domain}" &>/dev/null 2>&1; then
        log_debug "DNS 解析正常（nslookup ${domain}）"
        return 0
    fi

    log_debug "DNS 解析失败: ${domain}"
    return 1
}

# =============================================================================
# 2. 端口检测
# =============================================================================

# 检测本机端口是否处于监听状态
# 参数: $1=端口号
# 返回: 0=监听中  1=未监听
net_port_listening() {
    local port="$1"
    ss -tlnp 2>/dev/null | grep -q ":${port}\b" || \
    netstat -tlnp 2>/dev/null | grep -q ":${port}\b"
}

# 检测远程主机端口是否可访问
# 参数: $1=主机  $2=端口  $3=超时秒（默认 3）
# 返回: 0=可访问  1=不可访问
net_port_reachable() {
    local host="$1"
    local port="$2"
    local timeout="${3:-3}"

    timeout "${timeout}" bash -c \
        "echo >/dev/tcp/${host}/${port}" &>/dev/null 2>&1
}

# 等待端口开放（带超时）
# 参数: $1=端口  $2=超时秒（默认 30）  $3=主机（默认 localhost）
net_wait_port() {
    local port="$1"
    local timeout="${2:-30}"
    local host="${3:-localhost}"
    local elapsed=0

    log_debug "等待端口 ${host}:${port} 开放（最多 ${timeout}s）..."

    while (( elapsed < timeout )); do
        net_port_reachable "${host}" "${port}" 1 && return 0
        sleep 1
        (( elapsed++ ))
    done

    log_error "端口 ${host}:${port} 在 ${timeout}s 内未开放"
    return 1
}

# =============================================================================
# 3. 下载工具
# =============================================================================

# 安全下载文件（支持 curl 和 wget 回退）
# 参数: $1=URL  $2=保存路径  $3=超时秒（默认 60）
net_download() {
    local url="$1"
    local dest="$2"
    local timeout="${3:-60}"

    util_ensure_dir "$(dirname "${dest}")"

    log_debug "下载: ${url} → ${dest}"

    if util_cmd_exists curl; then
        curl -fsSL \
            --connect-timeout 10 \
            --max-time "${timeout}" \
            --retry 3 \
            --retry-delay 2 \
            -o "${dest}" \
            "${url}" 2>&1 || {
            log_error "下载失败 (curl): ${url}"
            return 1
        }
    elif util_cmd_exists wget; then
        wget -q \
            --timeout="${timeout}" \
            --tries=3 \
            --wait=2 \
            -O "${dest}" \
            "${url}" 2>&1 || {
            log_error "下载失败 (wget): ${url}"
            return 1
        }
    else
        log_error "缺少下载工具（curl 或 wget），请先安装"
        return 1
    fi

    log_debug "下载完成: ${dest} ($(du -sh "${dest}" 2>/dev/null | cut -f1))"
    return 0
}

# 获取 URL 的内容（输出到 stdout）
# 参数: $1=URL  $2=超时秒（默认 15）
net_fetch() {
    local url="$1"
    local timeout="${2:-15}"

    if util_cmd_exists curl; then
        curl -fsSL --connect-timeout 5 --max-time "${timeout}" "${url}" 2>/dev/null
    elif util_cmd_exists wget; then
        wget -qO- --timeout="${timeout}" "${url}" 2>/dev/null
    else
        log_error "缺少 curl 或 wget"
        return 1
    fi
}

# =============================================================================
# 4. IP 与接口工具
# =============================================================================

# 获取本机主 IPv4 地址
net_local_ipv4() {
    # 优先通过路由表获取出口 IP
    ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $7; exit}' || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    echo "Unknown"
}

# 获取公网 IP 地址
# 参数: $1=超时（默认 5s）
net_public_ip() {
    local timeout="${1:-5}"
    local -a services=(
        "https://api4.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me/ip"
        "https://ipinfo.io/ip"
    )

    local svc
    for svc in "${services[@]}"; do
        local ip
        ip="$(net_fetch "${svc}" "${timeout}" 2>/dev/null | tr -d '[:space:]')"
        if [[ "${ip}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "${ip}"
            return 0
        fi
    done

    echo "Unknown"
}

# 获取所有网络接口及 IP（用于报告展示）
net_list_interfaces() {
    ip -o addr show 2>/dev/null | awk '/inet /{print $2, $4}' | grep -v '^lo '
}

# =============================================================================
# 5. 域名与证书
# =============================================================================

# 检测域名是否解析到本机 IP
# 参数: $1=域名
# 返回: 0=是  1=否
net_domain_points_here() {
    local domain="$1"
    local local_ip
    local_ip="$(net_local_ipv4)"

    local resolved_ip
    resolved_ip="$(getent hosts "${domain}" 2>/dev/null | awk '{print $1; exit}')"

    [[ "${resolved_ip}" == "${local_ip}" ]]
}

# =============================================================================
# 6. 代理检测
# =============================================================================

# 检测环境变量中是否配置了代理
net_has_proxy() {
    [[ -n "${http_proxy:-}" || -n "${https_proxy:-}" || \
       -n "${HTTP_PROXY:-}" || -n "${HTTPS_PROXY:-}" ]]
}

# 打印当前代理设置
net_show_proxy() {
    if net_has_proxy; then
        log_info "检测到代理配置:"
        log_info "  http_proxy  = ${http_proxy:-${HTTP_PROXY:-未设置}}"
        log_info "  https_proxy = ${https_proxy:-${HTTPS_PROXY:-未设置}}"
    else
        log_debug "无代理配置"
    fi
}
