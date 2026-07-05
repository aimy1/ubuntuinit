#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 卸载入口
# =============================================================================
# 文件        : uninstall.sh
# 职责        : 按安装反向顺序，逐模块执行卸载
# 用法        : sudo bash uninstall.sh [选项]
#             : sudo bash install.sh --uninstall [选项]
#
# 选项:
#   -m, --modules <list>  仅卸载指定模块
#   -n, --non-interactive 无人值守模式
#   -v, --verbose         DEBUG 日志
#   -h, --help            帮助
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# 0. 基础路径
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"

# =============================================================================
# 1. 加载公共库（当作独立入口运行时需要自行加载）
# =============================================================================

# 仅在直接运行时加载（被 install.sh source 时跳过，已由父脚本加载）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # shellcheck source=lib/logger.sh
    source "${SCRIPT_DIR}/lib/logger.sh"
    # shellcheck source=lib/utils.sh
    source "${SCRIPT_DIR}/lib/utils.sh"
    # shellcheck source=lib/ui.sh
    source "${SCRIPT_DIR}/lib/ui.sh"

    UBINIT_NON_INTERACTIVE=false
    UBINIT_VERBOSE=false
    UBINIT_SELECTED_MODULES=""
    UBINIT_DEFAULT_CONF="${SCRIPT_DIR}/config/default.conf"
    UBINIT_CUSTOM_CONF="${SCRIPT_DIR}/config/custom.conf"
fi

# =============================================================================
# 2. 帮助信息
# =============================================================================

_uninstall_help() {
    cat <<EOF
UbuntuInit 卸载工具 v${SCRIPT_VERSION:-1.0.0}

用法: sudo bash ${SCRIPT_NAME} [选项]

选项:
  -m, --modules <list>    仅卸载指定模块（逗号分隔）
  -n, --non-interactive   无人值守模式
  -v, --verbose           DEBUG 日志
  -h, --help              显示此帮助信息

示例:
  sudo bash ${SCRIPT_NAME}                     # 交互选择卸载模块
  sudo bash ${SCRIPT_NAME} -n -m docker,nginx  # 无人值守卸载 Docker 和 Nginx
EOF
}

# =============================================================================
# 3. 参数解析（仅在独立运行时使用）
# =============================================================================

_parse_uninstall_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -m|--modules)
                [[ -z "${2:-}" ]] && log_error "选项 $1 需要一个参数" && exit 1
                UBINIT_SELECTED_MODULES="$2"
                shift 2
                ;;
            -n|--non-interactive)
                UBINIT_NON_INTERACTIVE=true
                shift
                ;;
            -v|--verbose)
                UBINIT_VERBOSE=true
                shift
                ;;
            -h|--help)
                _uninstall_help
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                _uninstall_help
                exit 1
                ;;
        esac
    done
}

# =============================================================================
# 4. 卸载模块注册（与安装顺序相反）
# =============================================================================

# 卸载顺序：与安装顺序严格相反，防止依赖残留
declare -a UNINSTALL_REGISTRY=(
    "directories:28_directories"
    "log_mgmt:27_log_mgmt"
    "shell:26_shell"
    "grafana:25_monitor_grafana"
    "node_exporter:24_monitor_node_exp"
    "netdata:23_monitor_netdata"
    "openresty:22_web_openresty"
    "caddy:21_web_caddy"
    "apache:20_web_apache"
    "nginx:19_web_nginx"
    "mongodb:18_db_mongodb"
    "postgresql:17_db_postgresql"
    "mysql:16_db_mysql"
    "mariadb:15_db_mariadb"
    "redis:14_db_redis"
    "rust:13_dev_rust"
    "go:12_dev_go"
    "java:11_dev_java"
    "node:10_dev_node"
    "python:09_dev_python"
    "docker:08_docker"
    "optimize:07_optimize"
    "nettools:06_network_tools"
    "security:05_security"
    "user:04_user"
    "ssh:03_ssh"
    "mirror:02_mirror"
    "system:01_system"
)

# =============================================================================
# 5. 卸载执行引擎
# =============================================================================

# 判断模块是否在卸载列表中
_is_uninstall_selected() {
    local alias="$1"
    [[ -z "${UBINIT_SELECTED_MODULES}" ]] && return 0

    local IFS=','
    for m in ${UBINIT_SELECTED_MODULES}; do
        m="$(util_trim "${m}")"
        [[ "${m}" == "${alias}" ]] && return 0
    done
    return 1
}

# 执行单个模块卸载
_uninstall_module() {
    local alias="$1"
    local filename="$2"
    local module_path="${SCRIPT_DIR}/modules/${filename}.sh"

    if [[ ! -f "${module_path}" ]]; then
        log_debug "卸载：模块文件不存在，跳过: ${module_path}"
        return 0
    fi

    if ! _is_uninstall_selected "${alias}"; then
        log_debug "模块 [${alias}] 未在卸载列表中，跳过"
        return 0
    fi

    # 加载模块
    # shellcheck source=/dev/null
    source "${module_path}"

    # 检测是否实际已安装
    if declare -f module_check &>/dev/null && ! module_check; then
        log_info "模块 [${alias}] 未安装，跳过卸载"
        return 0
    fi

    log_info "━━━ 卸载模块: [${alias}] ━━━"

    if declare -f module_uninstall &>/dev/null; then
        if module_uninstall; then
            log_success "模块 [${alias}] 卸载成功"
        else
            log_error "模块 [${alias}] 卸载失败，请手动处理"
        fi
    else
        log_warning "模块 [${alias}] 未实现 module_uninstall()，跳过"
    fi
}

# =============================================================================
# 6. 卸载主函数（被 install.sh --uninstall 调用或独立运行）
# =============================================================================

# 执行卸载流程（可被 install.sh source 后调用）
run_uninstall() {
    # 检查 root
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "必须以 root 权限运行"
        exit 1
    fi

    log_warning "════════════════════════════════════════"
    log_warning "  警告：即将开始卸载 UbuntuInit 组件"
    log_warning "  此操作不可逆，请确认后继续"
    log_warning "════════════════════════════════════════"

    # 交互确认
    if [[ "${UBINIT_NON_INTERACTIVE}" == "false" ]]; then
        if ! ui_confirm "确认执行卸载操作？" "no"; then
            log_info "用户取消卸载"
            return 0
        fi
    fi

    local entry alias filename
    for entry in "${UNINSTALL_REGISTRY[@]}"; do
        alias="${entry%%:*}"
        filename="${entry##*:}"
        _uninstall_module "${alias}" "${filename}"
    done

    log_success "卸载流程完成"
}

# =============================================================================
# 7. 独立运行入口
# =============================================================================

# 仅在直接执行时运行 main（被 source 时跳过）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # shellcheck source=config/default.conf
    [[ -f "${UBINIT_DEFAULT_CONF}" ]] && source "${UBINIT_DEFAULT_CONF}"
    # shellcheck source=/dev/null
    [[ -f "${UBINIT_CUSTOM_CONF}" ]] && source "${UBINIT_CUSTOM_CONF}"

    logger_init "${UBINIT_VERBOSE}"
    _parse_uninstall_args "$@"
    run_uninstall
fi
