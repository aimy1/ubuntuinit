#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: APT 软件源替换
# =============================================================================
# 文件     : modules/02_mirror.sh
# 说明     : 将 Ubuntu APT 源更换为国内镜像，显著提升下载速度
# 配置变量 : UBINIT_MIRROR_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/utils.sh  lib/backup.sh
# =============================================================================

module_info() {
    echo "name:        mirror"
    echo "description: 更换 APT 软件源为国内镜像"
}

# 检测 sources.list 是否已含目标镜像域名
module_check() {
    local mirror="${UBINIT_MIRROR_APT:-aliyun}"
    local domain

    case "${mirror}" in
        aliyun)    domain="mirrors.aliyun.com" ;;
        tencent)   domain="mirrors.tencent.com" ;;
        huawei)    domain="mirrors.huaweicloud.com" ;;
        ustc)      domain="mirrors.ustc.edu.cn" ;;
        tsinghua)  domain="mirrors.tuna.tsinghua.edu.cn" ;;
        *)         return 1 ;;
    esac

    grep -q "${domain}" /etc/apt/sources.list 2>/dev/null
}

# 构建镜像源内容
_mirror_build_sources() {
    local mirror="$1"
    local codename="$2"
    local base_url

    case "${mirror}" in
        aliyun)    base_url="http://mirrors.aliyun.com/ubuntu" ;;
        tencent)   base_url="http://mirrors.tencent.com/ubuntu" ;;
        huawei)    base_url="http://mirrors.huaweicloud.com/ubuntu" ;;
        ustc)      base_url="http://mirrors.ustc.edu.cn/ubuntu" ;;
        tsinghua)  base_url="http://mirrors.tuna.tsinghua.edu.cn/ubuntu" ;;
        official)  base_url="http://archive.ubuntu.com/ubuntu" ;;
        *)
            log_error "未知镜像源: ${mirror}"
            return 1
            ;;
    esac

    cat <<EOF
# UbuntuInit 自动生成 — 镜像源: ${mirror}
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')

deb ${base_url} ${codename} main restricted universe multiverse
deb ${base_url} ${codename}-updates main restricted universe multiverse
deb ${base_url} ${codename}-backports main restricted universe multiverse
deb ${base_url} ${codename}-security main restricted universe multiverse
EOF
}

module_install() {
    log_section "APT 软件源配置"

    if [[ "${UBINIT_MIRROR_ENABLE:-false}" != "true" ]]; then
        log_info "跳过软件源替换（UBINIT_MIRROR_ENABLE=false）"
        return 0
    fi

    # 读取 OS codename
    local codename
    # shellcheck source=/dev/null
    codename="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-}" || echo '')"

    if [[ -z "${codename}" ]]; then
        log_error "无法读取 Ubuntu 版本代号，跳过源替换"
        return 1
    fi

    local mirror="${UBINIT_MIRROR_APT:-aliyun}"
    log_info "目标镜像: ${mirror}  代号: ${codename}"

    # 构建新的 sources.list 内容
    local new_sources
    new_sources="$(_mirror_build_sources "${mirror}" "${codename}")" || return 1

    # 备份 + 替换
    apt_replace_sources_list "${new_sources}"

    # 刷新包列表
    apt_update

    # Snap 镜像配置（国内仅支持部分场景）
    if [[ "${UBINIT_MIRROR_SNAP:-false}" == "true" ]] && util_cmd_exists snap; then
        log_info "配置 Snap 代理..."
        snap set system proxy.http="${http_proxy:-}" 2>/dev/null || true
        snap set system proxy.https="${https_proxy:-}" 2>/dev/null || true
    fi

    log_success "软件源已切换到: ${mirror}"
    return 0
}

module_uninstall() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    log_info "尝试恢复原始 sources.list..."

    # 找到最新的备份文件
    local latest_backup
    latest_backup="$(find "${backup_dir}" -name "sources.list.*.bak" 2>/dev/null | sort -r | head -1)"

    if [[ -z "${latest_backup}" ]]; then
        log_warning "未找到 sources.list 备份，跳过恢复"
        return 0
    fi

    backup_restore_file "${latest_backup}" /etc/apt/sources.list
    apt_update
    log_success "sources.list 已恢复"
}
