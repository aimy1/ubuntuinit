#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — APT 包管理封装库
# =============================================================================
# 文件     : lib/apt.sh
# 说明     : 封装所有 APT 操作，统一日志、错误处理、锁等待、dry-run 支持
# 依赖     : lib/logger.sh  lib/utils.sh  lib/detect.sh
# =============================================================================

# =============================================================================
# 1. 内部配置
# =============================================================================

# APT 非交互环境变量（禁止 debconf 弹出交互对话框）
_APT_ENV=(
    DEBIAN_FRONTEND=noninteractive
    DEBCONF_NONINTERACTIVE_SEEN=true
    UCF_FORCE_CONFFOLD=1
)

# apt-get 公共参数
_APT_OPTS=(
    -y
    -q
    --no-install-recommends
    -o Dpkg::Options::="--force-confold"
    -o Dpkg::Options::="--force-confdef"
)

# =============================================================================
# 2. APT 锁等待
# =============================================================================

# 等待 APT 锁释放（最多等 N 秒）
# 参数: $1=超时秒数（默认 120）
apt_wait_lock() {
    local timeout="${1:-120}"
    local elapsed=0
    local lock_files=(
        "/var/lib/dpkg/lock-frontend"
        "/var/lib/dpkg/lock"
        "/var/cache/apt/archives/lock"
    )

    while (( elapsed < timeout )); do
        local locked=false
        local f
        for f in "${lock_files[@]}"; do
            if lsof "${f}" &>/dev/null 2>&1; then
                locked=true
                break
            fi
        done

        [[ "${locked}" == "false" ]] && return 0

        if (( elapsed == 0 )); then
            log_warning "APT 正在被其他进程占用，最多等待 ${timeout}s..."
        fi

        sleep 2
        (( elapsed += 2 ))
    done

    log_error "等待 APT 锁超时（${timeout}s），请手动检查: sudo lsof /var/lib/dpkg/lock-frontend"
    return 1
}

# =============================================================================
# 3. 核心 APT 操作
# =============================================================================

# 执行 apt-get update
# 参数: $1=是否静默（true|false，默认 false）
apt_update() {
    local quiet="${1:-false}"

    log_info "更新 APT 软件包列表..."
    apt_wait_lock || return 1

    if [[ "${UBINIT_DRY_RUN:-false}" == "true" ]]; then
        log_debug "[DRY-RUN] apt-get update"
        return 0
    fi

    local opts=()
    [[ "${quiet}" == "true" ]] && opts+=(-q)

    if env "${_APT_ENV[@]}" apt-get update "${opts[@]}" 2>&1 | \
        grep -v "^Hit\|^Get\|^Ign\|^Reading" | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done; then
        log_success "APT 更新完成"
        return 0
    else
        log_error "APT 更新失败"
        return 1
    fi
}

# 执行 apt-get upgrade
# 参数: $1=是否仅安全更新（true|false，默认 false）
apt_upgrade() {
    local security_only="${1:-false}"

    log_info "升级已安装软件包..."
    apt_wait_lock || return 1

    if [[ "${UBINIT_DRY_RUN:-false}" == "true" ]]; then
        log_debug "[DRY-RUN] apt-get upgrade"
        return 0
    fi

    local cmd="upgrade"
    if [[ "${security_only}" == "true" ]]; then
        cmd="--only-upgrade install $(apt-get --just-print upgrade 2>/dev/null | grep '^Inst' | grep -i security | awk '{print $2}' | tr '\n' ' ')"
    fi

    if env "${_APT_ENV[@]}" apt-get "${_APT_OPTS[@]}" ${cmd} 2>&1 | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done; then
        log_success "APT 升级完成"
        return 0
    else
        log_error "APT 升级失败"
        return 1
    fi
}

# 安装一个或多个软件包
# 参数: $@=包名列表
# 返回: 0=成功  1=失败
apt_install() {
    if [[ $# -eq 0 ]]; then
        log_error "apt_install: 未指定软件包"
        return 1
    fi

    log_info "安装软件包: $*"
    apt_wait_lock || return 1

    if [[ "${UBINIT_DRY_RUN:-false}" == "true" ]]; then
        log_debug "[DRY-RUN] apt-get install $*"
        return 0
    fi

    if env "${_APT_ENV[@]}" apt-get install "${_APT_OPTS[@]}" "$@" 2>&1 | \
        while IFS= read -r line; do
            # 过滤冗余输出，只记录关键信息
            case "${line}" in
                Setting\ up*|Unpacking*|Selecting*)
                    log_debug "APT: ${line}" ;;
                E:*|Err:*)
                    log_error "APT: ${line}" ;;
            esac
        done; then
        log_success "安装成功: $*"
        return 0
    else
        log_error "安装失败: $*"
        return 1
    fi
}

# 卸载软件包（保留配置文件）
# 参数: $@=包名列表
apt_remove() {
    [[ $# -eq 0 ]] && return 0

    log_info "移除软件包: $*"
    apt_wait_lock || return 1

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] apt-get remove $*"; return 0
    }

    env "${_APT_ENV[@]}" apt-get remove "${_APT_OPTS[@]}" "$@" 2>&1 | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done

    log_success "移除成功: $*"
}

# 彻底卸载软件包（含配置文件）
# 参数: $@=包名列表
apt_purge() {
    [[ $# -eq 0 ]] && return 0

    log_info "清除软件包: $*"
    apt_wait_lock || return 1

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] apt-get purge $*"; return 0
    }

    env "${_APT_ENV[@]}" apt-get purge "${_APT_OPTS[@]}" "$@" 2>&1 | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done

    log_success "清除完成: $*"
}

# 清理不需要的依赖
apt_autoremove() {
    log_info "清理多余依赖包..."

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] apt-get autoremove"; return 0
    }

    env "${_APT_ENV[@]}" apt-get autoremove "${_APT_OPTS[@]}" 2>&1 | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done

    log_success "自动清理完成"
}

# 清理下载缓存
apt_autoclean() {
    log_info "清理 APT 下载缓存..."

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] apt-get autoclean"; return 0
    }

    apt-get autoclean -q 2>&1 | while IFS= read -r line; do log_debug "APT: ${line}"; done
    log_success "缓存清理完成"
}

# =============================================================================
# 4. 软件包状态检测
# =============================================================================

# 检查软件包是否已安装
# 参数: $1=包名
# 返回: 0=已安装  1=未安装
apt_is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

# 检查软件包是否可用（在 APT 源中存在）
# 参数: $1=包名
apt_is_available() {
    apt-cache show "$1" &>/dev/null 2>&1
}

# 获取软件包当前安装版本
# 参数: $1=包名
apt_installed_version() {
    dpkg-query -W -f='${Version}' "$1" 2>/dev/null || echo ""
}

# 批量检查并安装（已安装的跳过）
# 参数: $@=包名列表
apt_ensure_installed() {
    local -a to_install=()
    local pkg

    for pkg in "$@"; do
        if apt_is_installed "${pkg}"; then
            log_debug "已安装: ${pkg}，跳过"
        else
            to_install+=("${pkg}")
        fi
    done

    if [[ ${#to_install[@]} -eq 0 ]]; then
        log_debug "所有软件包已安装，跳过"
        return 0
    fi

    apt_install "${to_install[@]}"
}

# =============================================================================
# 5. APT 源管理
# =============================================================================

# 添加 GPG 密钥（支持 URL 和本地文件）
# 参数: $1=密钥来源（URL 或文件路径） $2=保存路径（.asc 或 .gpg）
apt_add_key() {
    local source="$1"
    local dest="$2"

    util_ensure_dir "$(dirname "${dest}")"

    if [[ "${source}" == http* ]]; then
        log_debug "下载 GPG 密钥: ${source} → ${dest}"
        curl -fsSL "${source}" | gpg --dearmor -o "${dest}" || {
            log_error "下载 GPG 密钥失败: ${source}"
            return 1
        }
    else
        gpg --dearmor -o "${dest}" < "${source}" || {
            log_error "导入 GPG 密钥失败: ${source}"
            return 1
        }
    fi

    chmod 644 "${dest}"
    log_debug "GPG 密钥已写入: ${dest}"
}

# 添加 APT 源列表文件（.sources 格式，DEB822）
# 参数: $1=文件名（不含路径）  $2=内容
apt_add_source() {
    local filename="$1"
    local content="$2"
    local dest="/etc/apt/sources.list.d/${filename}"

    log_debug "写入 APT 源: ${dest}"

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] 写入 APT 源: ${dest}"
        return 0
    }

    util_write_file "${dest}" "${content}" || return 1
    log_success "APT 源已添加: ${dest}"
}

# 备份并替换 /etc/apt/sources.list
# 参数: $1=新内容
apt_replace_sources_list() {
    local new_content="$1"
    local backup_path="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}/sources.list.$(date +%Y%m%d_%H%M%S).bak"

    # 备份原文件
    if [[ -f /etc/apt/sources.list ]]; then
        util_ensure_dir "$(dirname "${backup_path}")"
        cp /etc/apt/sources.list "${backup_path}" && \
            log_debug "APT sources.list 已备份到: ${backup_path}"
    fi

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && {
        log_debug "[DRY-RUN] 替换 /etc/apt/sources.list"
        return 0
    }

    util_write_file /etc/apt/sources.list "${new_content}" && \
        log_success "APT sources.list 已更新"
}

# =============================================================================
# 6. dpkg 修复工具
# =============================================================================

# 修复损坏的 dpkg 状态
apt_fix_broken() {
    log_info "修复损坏的 APT 依赖..."

    [[ "${UBINIT_DRY_RUN:-false}" == "true" ]] && return 0

    env "${_APT_ENV[@]}" apt-get install --fix-broken "${_APT_OPTS[@]}" 2>&1 | \
        while IFS= read -r line; do log_debug "APT: ${line}"; done

    dpkg --configure -a 2>&1 | while IFS= read -r line; do log_debug "DPKG: ${line}"; done
    log_success "APT 依赖修复完成"
}
