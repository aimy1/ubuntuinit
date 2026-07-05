#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 备份与回滚库
# =============================================================================
# 文件     : lib/backup.sh
# 说明     : 配置文件备份、原子性恢复、快照管理
#           : 所有备份统一存放到 UBINIT_BACKUP_DIR
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

# =============================================================================
# 1. 初始化
# =============================================================================

# 确保备份目录存在
backup_init() {
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    util_ensure_dir "${backup_dir}" "0750" "root:root" || {
        log_error "无法创建备份目录: ${backup_dir}"
        return 1
    }
    log_debug "备份目录: ${backup_dir}"
}

# =============================================================================
# 2. 文件备份
# =============================================================================

# 备份单个文件（追加时间戳，支持多次备份同一文件）
# 参数: $1=源文件路径  $2=备份标签（可选，用于标识模块）
# 输出: 备份文件路径（echo）
# 返回: 0=成功  1=失败
backup_file() {
    local src="$1"
    local label="${2:-manual}"
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"

    if [[ ! -f "${src}" && ! -d "${src}" ]]; then
        log_debug "备份跳过（文件不存在）: ${src}"
        return 0
    fi

    # 构造备份路径：备份目录 / 标签 / 原始路径（去掉首斜杠）+ 时间戳
    local rel_path="${src#/}"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local dest_dir="${backup_dir}/${label}/$(dirname "${rel_path}")"
    local dest="${dest_dir}/$(basename "${src}").${timestamp}.bak"

    util_ensure_dir "${dest_dir}" || return 1

    if [[ -d "${src}" ]]; then
        cp -a "${src}" "${dest}" 2>/dev/null || {
            log_error "备份目录失败: ${src} → ${dest}"
            return 1
        }
    else
        cp -p "${src}" "${dest}" 2>/dev/null || {
            log_error "备份文件失败: ${src} → ${dest}"
            return 1
        }
    fi

    log_debug "已备份: ${src} → ${dest}"
    echo "${dest}"
    return 0
}

# 备份多个文件（批量）
# 参数: $1=标签  $2..=文件路径列表
backup_files() {
    local label="$1"
    shift
    local f
    for f in "$@"; do
        backup_file "${f}" "${label}" || return 1
    done
}

# =============================================================================
# 3. 快照（将一组文件打成 tar 归档）
# =============================================================================

# 创建文件集快照（tar.gz）
# 参数: $1=快照名  $2..=要备份的文件/目录列表
# 输出: 快照文件路径
backup_snapshot() {
    local name="$1"
    shift
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    local timestamp
    timestamp="$(date +%Y%m%d_%H%M%S)"
    local archive="${backup_dir}/snapshots/${name}_${timestamp}.tar.gz"

    util_ensure_dir "${backup_dir}/snapshots" || return 1

    log_info "创建快照: ${archive}"

    # 过滤掉不存在的路径
    local -a existing=()
    local p
    for p in "$@"; do
        [[ -e "${p}" ]] && existing+=("${p}")
    done

    if [[ ${#existing[@]} -eq 0 ]]; then
        log_warning "快照：没有可备份的文件，跳过"
        return 0
    fi

    tar -czf "${archive}" "${existing[@]}" 2>/dev/null || {
        log_error "快照创建失败: ${archive}"
        return 1
    }

    log_success "快照已保存: ${archive} ($(du -sh "${archive}" | cut -f1))"
    echo "${archive}"
}

# =============================================================================
# 4. 恢复（回滚）
# =============================================================================

# 从备份文件恢复到原始路径
# 参数: $1=备份文件路径  $2=目标路径（不传则自动推断）
backup_restore_file() {
    local backup_src="$1"
    local target="${2:-}"

    if [[ ! -f "${backup_src}" ]]; then
        log_error "备份文件不存在: ${backup_src}"
        return 1
    fi

    # 自动推断目标路径（从备份路径中还原，去掉时间戳后缀和 .bak）
    if [[ -z "${target}" ]]; then
        local basename
        basename="$(basename "${backup_src}")"
        # 去掉 .YYYYMMDD_HHMMSS.bak 后缀
        target="/${basename%.*.bak}"

        # 更准确的推断：从 backup_dir 后的路径结构还原
        local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
        local rel="${backup_src#"${backup_dir}"/*/}"  # 去掉 backup_dir/label/
        rel="${rel%.*.bak}"                            # 去掉时间戳后缀
        target="/${rel}"
    fi

    log_warning "恢复文件: ${backup_src} → ${target}"

    # 先备份当前文件（防止恢复失败）
    [[ -f "${target}" ]] && cp -p "${target}" "${target}.before_restore" 2>/dev/null || true

    cp -p "${backup_src}" "${target}" || {
        log_error "文件恢复失败: ${target}"
        return 1
    }

    log_success "文件已恢复: ${target}"
}

# 列出某标签下的所有备份（按时间排序）
# 参数: $1=标签（可选，不传则列全部）
backup_list() {
    local label="${1:-}"
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
    local search_path="${backup_dir}"
    [[ -n "${label}" ]] && search_path="${backup_dir}/${label}"

    if [[ ! -d "${search_path}" ]]; then
        log_info "没有找到备份记录: ${search_path}"
        return 0
    fi

    echo ""
    log_info "备份记录 (${search_path}):"
    find "${search_path}" -name "*.bak" -o -name "*.tar.gz" 2>/dev/null | \
        sort | while IFS= read -r f; do
            local size
            size="$(du -sh "${f}" 2>/dev/null | cut -f1)"
            printf "  %-12s  %s\n" "${size}" "${f}"
        done
    echo ""
}

# 清理超过 N 天的备份文件
# 参数: $1=保留天数（默认 30）
backup_cleanup_old() {
    local keep_days="${1:-30}"
    local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"

    [[ ! -d "${backup_dir}" ]] && return 0

    log_info "清理 ${keep_days} 天前的备份文件..."

    local count=0
    while IFS= read -r f; do
        rm -f "${f}"
        (( count++ ))
    done < <(find "${backup_dir}" -type f \( -name "*.bak" -o -name "*.tar.gz" \) \
                -mtime +"${keep_days}" 2>/dev/null)

    if (( count > 0 )); then
        log_success "已清理 ${count} 个过期备份文件"
    else
        log_debug "没有需要清理的过期备份"
    fi
}

# =============================================================================
# 5. 模块级备份辅助（供各模块 module_rollback 调用）
# =============================================================================

# 声明一个模块的备份集（模块开始安装时调用，记录需要备份的文件）
# 用法:
#   backup_module_snapshot "ssh" /etc/ssh/sshd_config /etc/ssh/ssh_config
backup_module_snapshot() {
    local module_name="$1"
    shift
    backup_snapshot "${module_name}" "$@"
}

# 快速一键备份 + 修改（确保修改前备份）
# 参数: $1=模块名  $2=文件路径  $3=修改命令（eval 执行）
backup_then_modify() {
    local module="$1"
    local file="$2"
    local modify_cmd="$3"

    # 先备份
    backup_file "${file}" "${module}" || return 1

    # 再执行修改
    eval "${modify_cmd}" || {
        log_error "修改失败，正在恢复: ${file}"
        # 获取最新备份文件
        local backup_dir="${UBINIT_BACKUP_DIR:-/var/backup/ubuntu-init}"
        local latest_backup
        latest_backup="$(find "${backup_dir}/${module}" -name "$(basename "${file}").*.bak" \
            2>/dev/null | sort -r | head -1)"
        [[ -n "${latest_backup}" ]] && backup_restore_file "${latest_backup}" "${file}"
        return 1
    }
}
