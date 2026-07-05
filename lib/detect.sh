#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 系统检测库
# =============================================================================
# 文件     : lib/detect.sh
# 说明     : 自动检测系统环境，结果写入全局变量供所有模块使用
#           : 检测项：OS版本/架构/虚拟化/云平台/资源/网络/内核
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

# =============================================================================
# 1. 全局检测结果变量（由 detect_all() 填充，供模块只读）
# =============================================================================

DETECT_OS_ID=""          # ubuntu
DETECT_OS_VERSION=""     # 22.04
DETECT_OS_CODENAME=""    # jammy
DETECT_OS_FULL=""        # Ubuntu 22.04.3 LTS
DETECT_ARCH=""           # amd64 | arm64
DETECT_KERNEL=""         # 5.15.0-...
DETECT_HOSTNAME=""

DETECT_IS_VM=false       # 是否虚拟机
DETECT_IS_CLOUD=false    # 是否云服务器
DETECT_CLOUD_PROVIDER="" # aws | gcp | azure | aliyun | tencent | unknown
DETECT_VIRT_TYPE=""      # kvm | vmware | xen | hyperv | lxc | docker | none

DETECT_CPU_CORES=0       # 物理/逻辑核心数
DETECT_CPU_MODEL=""      # CPU 型号
DETECT_MEM_TOTAL_MB=0    # 总内存（MB）
DETECT_MEM_FREE_MB=0     # 可用内存（MB）
DETECT_SWAP_TOTAL_MB=0   # swap 总量（MB）
DETECT_DISK_FREE_GB=0    # / 分区可用空间（GB）

DETECT_HAS_INTERNET=false   # 公网连通
DETECT_HAS_DNS=false        # DNS 解析正常
DETECT_APT_LOCKED=false     # APT 锁被占用

# =============================================================================
# 2. OS 信息检测
# =============================================================================

# 读取 /etc/os-release 信息
_detect_os() {
    if [[ ! -f /etc/os-release ]]; then
        log_error "无法读取 /etc/os-release，不支持当前系统"
        return 1
    fi

    # shellcheck source=/dev/null
    source /etc/os-release

    DETECT_OS_ID="${ID:-unknown}"
    DETECT_OS_VERSION="${VERSION_ID:-0}"
    DETECT_OS_CODENAME="${VERSION_CODENAME:-unknown}"
    DETECT_OS_FULL="${PRETTY_NAME:-Unknown OS}"
    DETECT_HOSTNAME="$(hostname -s 2>/dev/null || echo 'unknown')"

    log_debug "OS: ${DETECT_OS_FULL}  Codename: ${DETECT_OS_CODENAME}"
}

# 校验是否为受支持的 Ubuntu 版本
detect_assert_ubuntu() {
    _detect_os

    if [[ "${DETECT_OS_ID}" != "ubuntu" ]]; then
        log_error "不支持的系统: ${DETECT_OS_FULL}（仅支持 Ubuntu）"
        return 1
    fi

    # 支持版本列表
    local -a supported=("20.04" "22.04" "24.04" "26.04")
    local ver
    for ver in "${supported[@]}"; do
        [[ "${DETECT_OS_VERSION}" == "${ver}" ]] && return 0
    done

    log_warning "Ubuntu ${DETECT_OS_VERSION} 未经完整测试，建议使用 20.04/22.04/24.04"
    return 0   # 警告但不阻止，保持前向兼容
}

# =============================================================================
# 3. 架构检测
# =============================================================================

_detect_arch() {
    local raw_arch
    raw_arch="$(uname -m)"

    case "${raw_arch}" in
        x86_64)          DETECT_ARCH="amd64" ;;
        aarch64|arm64)   DETECT_ARCH="arm64" ;;
        armv7l)          DETECT_ARCH="armhf" ;;
        *)               DETECT_ARCH="${raw_arch}" ;;
    esac

    log_debug "架构: ${DETECT_ARCH} (uname -m: ${raw_arch})"
}

# =============================================================================
# 4. 虚拟化检测
# =============================================================================

_detect_virt() {
    DETECT_IS_VM=false
    DETECT_VIRT_TYPE="none"

    # 优先使用 systemd-detect-virt
    if util_cmd_exists systemd-detect-virt; then
        local virt
        virt="$(systemd-detect-virt 2>/dev/null || echo 'none')"
        if [[ "${virt}" != "none" ]]; then
            DETECT_IS_VM=true
            DETECT_VIRT_TYPE="${virt}"
            log_debug "虚拟化 (systemd-detect-virt): ${virt}"
            return 0
        fi
    fi

    # 回退：检查 /proc/cpuinfo 和 DMI 信息
    if grep -qi "hypervisor" /proc/cpuinfo 2>/dev/null; then
        DETECT_IS_VM=true
        DETECT_VIRT_TYPE="unknown-hypervisor"
    elif [[ -f /sys/class/dmi/id/product_name ]]; then
        local product
        product="$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')"
        case "${product}" in
            *kvm*)    DETECT_IS_VM=true; DETECT_VIRT_TYPE="kvm"    ;;
            *vmware*) DETECT_IS_VM=true; DETECT_VIRT_TYPE="vmware" ;;
            *xen*)    DETECT_IS_VM=true; DETECT_VIRT_TYPE="xen"    ;;
            *virtualbox*) DETECT_IS_VM=true; DETECT_VIRT_TYPE="virtualbox" ;;
        esac
    fi

    # 检测容器环境
    if [[ -f /.dockerenv ]]; then
        DETECT_IS_VM=true; DETECT_VIRT_TYPE="docker"
    elif grep -q "lxc" /proc/1/environ 2>/dev/null; then
        DETECT_IS_VM=true; DETECT_VIRT_TYPE="lxc"
    fi

    log_debug "虚拟化: ${DETECT_VIRT_TYPE} (is_vm=${DETECT_IS_VM})"
}

# =============================================================================
# 5. 云平台检测
# =============================================================================

_detect_cloud() {
    DETECT_IS_CLOUD=false
    DETECT_CLOUD_PROVIDER="unknown"

    # AWS: 检查 DMI 或 metadata endpoint
    if grep -qi "amazon" /sys/class/dmi/id/bios_vendor 2>/dev/null || \
       grep -qi "amazon" /sys/class/dmi/id/product_version 2>/dev/null; then
        DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="aws"; return 0
    fi

    # GCP: 检查 DMI product_name
    if grep -qi "google" /sys/class/dmi/id/bios_vendor 2>/dev/null; then
        DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="gcp"; return 0
    fi

    # Azure: 检查 DMI chassis
    if grep -qi "microsoft" /sys/class/dmi/id/chassis_vendor 2>/dev/null; then
        DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="azure"; return 0
    fi

    # 阿里云: 检查 DMI
    if grep -qi "alibaba" /sys/class/dmi/id/product_name 2>/dev/null; then
        DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="aliyun"; return 0
    fi

    # 腾讯云
    if grep -qi "tencent" /sys/class/dmi/id/product_name 2>/dev/null; then
        DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="tencent"; return 0
    fi

    # 通用：检查是否有云 metadata 服务（IMDS）响应
    if util_cmd_exists curl; then
        if curl -sf --connect-timeout 1 http://169.254.169.254/latest/meta-data/ &>/dev/null; then
            DETECT_IS_CLOUD=true; DETECT_CLOUD_PROVIDER="aws-compatible"
        fi
    fi

    log_debug "云平台: ${DETECT_CLOUD_PROVIDER} (is_cloud=${DETECT_IS_CLOUD})"
}

# =============================================================================
# 6. 硬件资源检测
# =============================================================================

_detect_hardware() {
    # CPU
    DETECT_CPU_CORES="$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo 1)"
    DETECT_CPU_MODEL="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'Unknown')"

    # 内存（MB）
    local mem_total_kb mem_available_kb
    mem_total_kb="$(  grep MemTotal     /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)"
    mem_available_kb="$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)"
    DETECT_MEM_TOTAL_MB=$(( mem_total_kb / 1024 ))
    DETECT_MEM_FREE_MB=$(( mem_available_kb / 1024 ))

    # Swap（MB）
    local swap_total_kb
    swap_total_kb="$(grep SwapTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)"
    DETECT_SWAP_TOTAL_MB=$(( swap_total_kb / 1024 ))

    # 磁盘（/ 分区可用 GB）
    DETECT_DISK_FREE_GB="$(df -BG / 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4}' || echo 0)"

    # 内核
    DETECT_KERNEL="$(uname -r)"

    log_debug "CPU: ${DETECT_CPU_CORES} 核 | 内存: ${DETECT_MEM_TOTAL_MB}MB | 磁盘: ${DETECT_DISK_FREE_GB}GB"
}

# =============================================================================
# 7. 网络与 DNS 检测
# =============================================================================

_detect_network() {
    # 互联网连通性（超时 3s）
    if curl -sf --connect-timeout 3 --max-time 5 https://1.1.1.1 &>/dev/null || \
       ping -c1 -W3 1.1.1.1 &>/dev/null 2>&1; then
        DETECT_HAS_INTERNET=true
    else
        DETECT_HAS_INTERNET=false
    fi

    # DNS 解析（解析 cloudflare.com）
    if getent hosts cloudflare.com &>/dev/null 2>&1 || \
       host -W 3 cloudflare.com &>/dev/null 2>&1; then
        DETECT_HAS_DNS=true
    else
        DETECT_HAS_DNS=false
    fi

    log_debug "网络: internet=${DETECT_HAS_INTERNET} dns=${DETECT_HAS_DNS}"
}

# =============================================================================
# 8. APT 锁检测
# =============================================================================

_detect_apt_lock() {
    local lock_files=(
        "/var/lib/dpkg/lock"
        "/var/lib/dpkg/lock-frontend"
        "/var/lib/apt/lists/lock"
        "/var/cache/apt/archives/lock"
    )

    DETECT_APT_LOCKED=false

    local f
    for f in "${lock_files[@]}"; do
        if lsof "${f}" &>/dev/null 2>&1; then
            DETECT_APT_LOCKED=true
            log_debug "APT 锁文件被占用: ${f}"
            return 0
        fi
    done

    # 尝试获取锁（flock 方式）
    if ! flock --nonblock /var/lib/dpkg/lock-frontend true 2>/dev/null; then
        DETECT_APT_LOCKED=true
    fi
}

# =============================================================================
# 9. 统一检测入口
# =============================================================================

# 执行所有检测项，填充全局变量
# 返回: 0=全部通过  1=有致命错误
detect_all() {
    log_info "执行系统环境检测..."

    _detect_os       || return 1
    _detect_arch
    _detect_hardware
    _detect_virt
    _detect_cloud
    _detect_network
    _detect_apt_lock

    # 导出所有 DETECT_ 变量供子模块使用
    export DETECT_OS_ID DETECT_OS_VERSION DETECT_OS_CODENAME DETECT_OS_FULL
    export DETECT_ARCH DETECT_KERNEL DETECT_HOSTNAME
    export DETECT_IS_VM DETECT_VIRT_TYPE DETECT_IS_CLOUD DETECT_CLOUD_PROVIDER
    export DETECT_CPU_CORES DETECT_CPU_MODEL
    export DETECT_MEM_TOTAL_MB DETECT_MEM_FREE_MB DETECT_SWAP_TOTAL_MB
    export DETECT_DISK_FREE_GB DETECT_HAS_INTERNET DETECT_HAS_DNS DETECT_APT_LOCKED

    log_debug "系统检测完成"
    return 0
}

# =============================================================================
# 10. 预检断言（供 00_preflight.sh 调用）
# =============================================================================

# 断言 root 权限
detect_assert_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "需要 root 权限，请使用: sudo bash install.sh"
        return 1
    fi
    log_debug "Root 权限: 通过"
}

# 断言最小内存（MB）
# 参数: $1=最小内存 MB（默认 512）
detect_assert_min_memory() {
    local min_mb="${1:-512}"
    if (( DETECT_MEM_TOTAL_MB < min_mb )); then
        log_error "内存不足: ${DETECT_MEM_TOTAL_MB}MB（最低要求 ${min_mb}MB）"
        return 1
    fi
    log_debug "内存: ${DETECT_MEM_TOTAL_MB}MB ≥ ${min_mb}MB 通过"
}

# 断言最小磁盘空间（GB）
# 参数: $1=最小 GB（默认 5）
detect_assert_min_disk() {
    local min_gb="${1:-5}"
    if (( DETECT_DISK_FREE_GB < min_gb )); then
        log_error "磁盘空间不足: ${DETECT_DISK_FREE_GB}GB 可用（最低要求 ${min_gb}GB）"
        return 1
    fi
    log_debug "磁盘: ${DETECT_DISK_FREE_GB}GB ≥ ${min_gb}GB 通过"
}

# 断言网络连通
detect_assert_internet() {
    if [[ "${DETECT_HAS_INTERNET}" != "true" ]]; then
        log_error "无法连接互联网，请检查网络配置"
        return 1
    fi
    log_debug "网络连通: 通过"
}

# 断言 APT 未被锁定
detect_assert_apt_free() {
    if [[ "${DETECT_APT_LOCKED}" == "true" ]]; then
        log_error "APT 正在被其他进程使用，请等待其完成后再运行"
        log_info  "提示: sudo lsof /var/lib/dpkg/lock-frontend"
        return 1
    fi
    log_debug "APT 锁: 未占用，通过"
}

# 打印检测摘要（供 preflight 模块调用）
detect_print_summary() {
    echo ""
    log_section "系统环境检测摘要"

    local vm_label="物理机"
    [[ "${DETECT_IS_VM}" == "true" ]] && vm_label="虚拟机 (${DETECT_VIRT_TYPE})"

    local cloud_label="非云环境"
    [[ "${DETECT_IS_CLOUD}" == "true" ]] && cloud_label="${DETECT_CLOUD_PROVIDER}"

    local net_label="${LOG_CLR_ERR:-}✗ 无网络${LOG_CLR_RESET:-}"
    [[ "${DETECT_HAS_INTERNET}" == "true" ]] && net_label="${LOG_CLR_OK:-}✓ 已连接${LOG_CLR_RESET:-}"

    printf "  %-20s %s\n" "操作系统:"    "${DETECT_OS_FULL}"
    printf "  %-20s %s\n" "内核版本:"    "${DETECT_KERNEL}"
    printf "  %-20s %s\n" "系统架构:"    "${DETECT_ARCH}"
    printf "  %-20s %s\n" "主机名:"      "${DETECT_HOSTNAME}"
    printf "  %-20s %s\n" "CPU:"         "${DETECT_CPU_CORES} 核 - ${DETECT_CPU_MODEL:0:36}"
    printf "  %-20s %s\n" "内存:"        "${DETECT_MEM_TOTAL_MB}MB 总 / ${DETECT_MEM_FREE_MB}MB 可用"
    printf "  %-20s %s\n" "Swap:"        "${DETECT_SWAP_TOTAL_MB}MB"
    printf "  %-20s %s\n" "磁盘(/):"     "${DETECT_DISK_FREE_GB}GB 可用"
    printf "  %-20s %s\n" "运行环境:"    "${vm_label}"
    printf "  %-20s %s\n" "云平台:"      "${cloud_label}"
    printf "  %-20s %b\n" "网络连通:"    "${net_label}"
    echo ""
}
