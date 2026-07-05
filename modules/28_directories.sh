#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 标准目录初始化
# =============================================================================
# 文件     : modules/28_directories.sh
# 说明     : 创建运维标准目录结构，设置权限和所有者
# 配置变量 : UBINIT_DIRS_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        directories"
    echo "description: 创建标准运维目录结构（/data /docker /backup /scripts /logs）"
}

module_check() {
    # 检测第一个目录是否已存在
    local -a dirs=()
    read -r -a dirs <<< "${UBINIT_DIRS_LIST:-/data /docker /backup /scripts /logs}"
    [[ ${#dirs[@]} -gt 0 ]] && [[ -d "${dirs[0]}" ]]
}

module_install() {
    log_section "标准目录初始化"

    if [[ "${UBINIT_DIRS_ENABLE:-true}" != "true" ]]; then
        log_info "跳过（UBINIT_DIRS_ENABLE=false）"
        return 0
    fi

    local mode="${UBINIT_DIRS_MODE:-0755}"
    local owner="${UBINIT_DIRS_OWNER:-root:root}"

    # 解析目录列表（空格分隔）
    local -a dirs=()
    read -r -a dirs <<< "${UBINIT_DIRS_LIST:-/data /docker /backup /scripts /logs}"

    local created=0
    local dir

    for dir in "${dirs[@]}"; do
        dir="$(util_trim "${dir}")"
        [[ -z "${dir}" ]] && continue

        if [[ -d "${dir}" ]]; then
            log_debug "目录已存在: ${dir}"
        else
            mkdir -p "${dir}" || {
                log_error "无法创建目录: ${dir}"
                continue
            }
            log_info "已创建: ${dir}"
            (( created++ ))
        fi

        # 设置权限
        chmod "${mode}" "${dir}" 2>/dev/null || true

        # 设置所有者（非 root:root 才修改，避免误操作）
        if [[ "${owner}" != "root:root" ]] && [[ "${owner}" != "root" ]]; then
            chown "${owner}" "${dir}" 2>/dev/null || \
                log_warning "无法设置 ${dir} 所有者为 ${owner}"
        fi
    done

    # 创建子目录结构（约定目录）
    local subdir_map=(
        "/data/app"
        "/data/upload"
        "/docker/compose"
        "/docker/volumes"
        "/backup/daily"
        "/backup/weekly"
        "/scripts/cron"
        "/logs/app"
        "/logs/system"
    )

    local sub
    for sub in "${subdir_map[@]}"; do
        # 仅在父目录存在时创建
        local parent="${sub%/*}"
        if [[ -d "${parent}" ]] && [[ ! -d "${sub}" ]]; then
            mkdir -p "${sub}" 2>/dev/null && log_debug "已创建子目录: ${sub}"
        fi
    done

    # 写入 MOTD 提示
    util_ensure_dir /etc/motd.d 2>/dev/null || true
    if [[ -d /etc/motd.d ]]; then
        cat > /etc/motd.d/ubinit-dirs <<EOF
┌─────────────────────────────────────────┐
│  UbuntuInit — 标准目录结构               │
│                                         │
│  /data      应用数据                    │
│  /docker    Docker Compose 项目         │
│  /backup    备份文件                    │
│  /scripts   自定义脚本                  │
│  /logs      应用日志                    │
└─────────────────────────────────────────┘
EOF
    fi

    log_success "目录初始化完成（新建 ${created} 个目录）"
    log_info "目录结构: ${dirs[*]}"
    return 0
}

module_uninstall() {
    log_warning "目录卸载：仅删除**空目录**（含数据的目录会被跳过）"

    local -a dirs=()
    read -r -a dirs <<< "${UBINIT_DIRS_LIST:-/data /docker /backup /scripts /logs}"
    local dir

    for dir in "${dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            if rmdir "${dir}" 2>/dev/null; then
                log_info "已删除空目录: ${dir}"
            else
                log_warning "目录非空，已跳过: ${dir}"
            fi
        fi
    done

    rm -f /etc/motd.d/ubinit-dirs
    log_success "目录清理完成"
}
