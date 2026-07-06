#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — Ubuntu Server 一键初始化框架
# =============================================================================
# 文件        : install.sh
# 职责        : 程序主入口（仅负责：初始化 → 读配置 → 执行模块 → 输出报告）
# 用法        : sudo bash install.sh [选项]
#
# 选项:
#   -c, --config <file>   指定自定义配置文件（默认: config/custom.conf）
#   -m, --modules <list>  仅执行指定模块，逗号分隔（如: system,docker,ssh）
#   -n, --non-interactive 无人值守模式，跳过所有交互提示
#   -s, --skip-preflight  跳过预检（调试用，生产环境慎用）
#   -v, --verbose         启用 DEBUG 级别日志
#   -h, --help            显示帮助信息
#   --dry-run             模拟执行，不做任何实际更改
#   --uninstall           进入卸载模式
#
# 示例:
#   sudo bash install.sh                          # 交互模式
#   sudo bash install.sh -n -c /etc/my.conf       # 无人值守 + 自定义配置
#   sudo bash install.sh -m system,ssh,docker     # 仅执行指定模块
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# =============================================================================
# 0. 脚本基础路径（所有路径基于此，避免 cd 依赖）
# =============================================================================

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="1.0.0"

# =============================================================================
# 1. 引导阶段：加载公共库（logger 必须最先加载）
# =============================================================================

# shellcheck source=lib/logger.sh
source "${SCRIPT_DIR}/lib/logger.sh"

# shellcheck source=lib/utils.sh
source "${SCRIPT_DIR}/lib/utils.sh"

# shellcheck source=lib/detect.sh
source "${SCRIPT_DIR}/lib/detect.sh"

# shellcheck source=lib/apt.sh
source "${SCRIPT_DIR}/lib/apt.sh"

# shellcheck source=lib/service.sh
source "${SCRIPT_DIR}/lib/service.sh"

# shellcheck source=lib/network.sh
source "${SCRIPT_DIR}/lib/network.sh"

# shellcheck source=lib/backup.sh
source "${SCRIPT_DIR}/lib/backup.sh"

# shellcheck source=lib/ui.sh
source "${SCRIPT_DIR}/lib/ui.sh"

# shellcheck source=lib/report.sh
source "${SCRIPT_DIR}/lib/report.sh"

# =============================================================================
# 2. 全局运行时变量（供所有模块读取，禁止在模块内修改）
# =============================================================================

# --- 程序运行标志 ---
UBINIT_NON_INTERACTIVE=false    # 无人值守模式
UBINIT_VERBOSE=false            # DEBUG 日志
UBINIT_DRY_RUN=false            # 模拟执行
UBINIT_SKIP_PREFLIGHT=false     # 跳过预检
UBINIT_UNINSTALL_MODE=false     # 卸载模式

# --- 配置文件路径 ---
UBINIT_DEFAULT_CONF="${SCRIPT_DIR}/config/default.conf"
UBINIT_CUSTOM_CONF="${SCRIPT_DIR}/config/custom.conf"

# --- 模块过滤（空=全部执行）---
UBINIT_SELECTED_MODULES=""

# --- 状态追踪 ---
UBINIT_FAILED_MODULES=()        # 执行失败的模块列表
UBINIT_SKIPPED_MODULES=()       # 被跳过的模块列表
UBINIT_SUCCESS_MODULES=()       # 执行成功的模块列表
UBINIT_START_TIME=""            # 开始时间戳

# --- 导出给子模块使用的只读变量 ---
export SCRIPT_DIR
export SCRIPT_VERSION

# =============================================================================
# 3. 帮助信息
# =============================================================================

# 输出帮助信息
show_help() {
    cat <<EOF
$(ui_banner)

用法: sudo bash ${SCRIPT_NAME} [选项]

选项:
  -c, --config <file>     指定自定义配置文件
                          默认: ${UBINIT_CUSTOM_CONF}
  -m, --modules <list>    仅执行指定模块（逗号分隔）
                          可用模块: system,mirror,ssh,user,security,
                                    nettools,optimize,docker,
                                    python,node,java,go,rust,
                                    redis,mariadb,mysql,postgresql,mongodb,
                                    nginx,apache,caddy,openresty,
                                    netdata,node_exporter,grafana,
                                    shell,log_mgmt,directories
  -n, --non-interactive   无人值守模式（跳过所有交互提示）
  -s, --skip-preflight    跳过系统预检（调试用）
  -v, --verbose           启用 DEBUG 级别详细日志
      --dry-run           模拟执行，不做任何实际更改
      --uninstall         进入卸载模式
  -h, --help              显示此帮助信息

示例:
  # 交互模式（推荐首次使用）
  sudo bash ${SCRIPT_NAME}

  # 无人值守全量安装
  sudo bash ${SCRIPT_NAME} --non-interactive

  # 使用自定义配置无人值守安装
  sudo bash ${SCRIPT_NAME} -n -c /path/to/my.conf

  # 仅安装 Docker 和 Node.js
  sudo bash ${SCRIPT_NAME} -m docker,node

  # 模拟执行（预览将要做的操作）
  sudo bash ${SCRIPT_NAME} --dry-run

文档: https://github.com/ublinuxinit/ubuntu-init
版本: ${SCRIPT_VERSION}
EOF
}

# =============================================================================
# 4. 参数解析
# =============================================================================

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--config)
                [[ -z "${2:-}" ]] && log_error "选项 $1 需要一个参数" && exit 1
                UBINIT_CUSTOM_CONF="$2"
                shift 2
                ;;
            -m|--modules)
                [[ -z "${2:-}" ]] && log_error "选项 $1 需要一个参数" && exit 1
                UBINIT_SELECTED_MODULES="$2"
                shift 2
                ;;
            -n|--non-interactive)
                UBINIT_NON_INTERACTIVE=true
                shift
                ;;
            -s|--skip-preflight)
                UBINIT_SKIP_PREFLIGHT=true
                shift
                ;;
            -v|--verbose)
                UBINIT_VERBOSE=true
                shift
                ;;
            --dry-run)
                UBINIT_DRY_RUN=true
                shift
                ;;
            --uninstall)
                UBINIT_UNINSTALL_MODE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # 导出运行标志供模块读取
    export UBINIT_NON_INTERACTIVE
    export UBINIT_VERBOSE
    export UBINIT_DRY_RUN
    export UBINIT_SKIP_PREFLIGHT
}

# =============================================================================
# 5. 配置加载
# =============================================================================

# 加载配置文件（先加载默认值，再用自定义值覆盖）
load_config() {
    log_info "加载配置..."

    # 加载默认配置（必须存在）
    if [[ ! -f "${UBINIT_DEFAULT_CONF}" ]]; then
        log_error "默认配置文件不存在: ${UBINIT_DEFAULT_CONF}"
        exit 1
    fi
    # shellcheck source=config/default.conf
    source "${UBINIT_DEFAULT_CONF}"
    log_debug "已加载默认配置: ${UBINIT_DEFAULT_CONF}"

    # 加载自定义配置（可选，存在则覆盖默认值）
    if [[ -f "${UBINIT_CUSTOM_CONF}" ]]; then
        # shellcheck source=/dev/null
        source "${UBINIT_CUSTOM_CONF}"
        log_debug "已加载自定义配置: ${UBINIT_CUSTOM_CONF}"
    else
        log_debug "未找到自定义配置，使用默认值: ${UBINIT_CUSTOM_CONF}"
    fi

    # 将配置变量导出给子模块
    _export_config_vars
}

# 将所有配置变量导出（以 UBINIT_ 前缀统一管理）
_export_config_vars() {
    # 遍历所有以 UBINIT_ 开头的变量并导出
    while IFS='=' read -r name _; do
        [[ "${name}" == UBINIT_* ]] && export "${name?}"
    done < <(declare -p | grep -oE 'UBINIT_[A-Z0-9_]+')
}

# =============================================================================
# 6. 模块注册表
# =============================================================================

# 全量模块执行顺序（按依赖顺序排列）
# 格式: "模块别名:模块文件名"
declare -a MODULE_REGISTRY=(
    "preflight:00_preflight"
    "system:01_system"
    "mirror:02_mirror"
    "ssh:03_ssh"
    "user:04_user"
    "security:05_security"
    "nettools:06_network_tools"
    "optimize:07_optimize"
    "docker:08_docker"
    "python:09_dev_python"
    "node:10_dev_node"
    "java:11_dev_java"
    "go:12_dev_go"
    "rust:13_dev_rust"
    "redis:14_db_redis"
    "mariadb:15_db_mariadb"
    "mysql:16_db_mysql"
    "postgresql:17_db_postgresql"
    "mongodb:18_db_mongodb"
    "nginx:19_web_nginx"
    "apache:20_web_apache"
    "caddy:21_web_caddy"
    "openresty:22_web_openresty"
    "netdata:23_monitor_netdata"
    "node_exporter:24_monitor_node_exp"
    "grafana:25_monitor_grafana"
    "shell:26_shell"
    "log_mgmt:27_log_mgmt"
    "directories:28_directories"
)

# =============================================================================
# 7. 模块执行引擎
# =============================================================================

# 判断某模块是否在用户选定列表中
_is_module_selected() {
    local alias="$1"

    # 未指定过滤列表 → 全部执行
    [[ -z "${UBINIT_SELECTED_MODULES}" ]] && return 0

    # preflight 永远执行（除非被 --skip-preflight 覆盖）
    [[ "${alias}" == "preflight" ]] && return 0

    # 检查别名是否在列表中
    local IFS=','
    for m in ${UBINIT_SELECTED_MODULES}; do
        m="$(util_trim "${m}")"
        [[ "${m}" == "${alias}" ]] && return 0
    done
    return 1
}

# 执行单个模块
_run_module() {
    local alias="$1"
    local filename="$2"
    local module_path="${SCRIPT_DIR}/modules/${filename}.sh"

    # 检查模块文件存在
    if [[ ! -f "${module_path}" ]]; then
        log_warning "模块文件不存在，跳过: ${module_path}"
        UBINIT_SKIPPED_MODULES+=("${alias}")
        return 0
    fi

    # 检查是否选中
    if ! _is_module_selected "${alias}"; then
        log_debug "模块 [${alias}] 未在执行列表中，跳过"
        UBINIT_SKIPPED_MODULES+=("${alias}")
        return 0
    fi

    # 加载模块
    # shellcheck source=/dev/null
    source "${module_path}"

    # 检测是否已安装（幂等保护）
    if declare -f module_check &>/dev/null && module_check; then
        log_info "模块 [${alias}] 检测已完成，跳过重复执行"
        UBINIT_SKIPPED_MODULES+=("${alias}(已完成)")
        return 0
    fi

    # dry-run 模式
    if [[ "${UBINIT_DRY_RUN}" == "true" ]]; then
        log_info "[DRY-RUN] 将执行模块: ${alias}"
        UBINIT_SUCCESS_MODULES+=("${alias}(dry-run)")
        return 0
    fi

    log_info "━━━ 执行模块: [${alias}] ━━━"
    local start_ts
    start_ts="$(date +%s)"

    # 执行安装函数
    if declare -f module_install &>/dev/null; then
        if module_install; then
            local end_ts elapsed
            end_ts="$(date +%s)"
            elapsed=$(( end_ts - start_ts ))
            log_success "模块 [${alias}] 执行成功 (耗时 ${elapsed}s)"
            UBINIT_SUCCESS_MODULES+=("${alias}")
        else
            log_error "模块 [${alias}] 执行失败"
            UBINIT_FAILED_MODULES+=("${alias}")
            # 非 preflight 模块失败时，尝试回滚
            if [[ "${alias}" != "preflight" ]] && declare -f module_rollback &>/dev/null; then
                log_warning "尝试回滚模块: ${alias}"
                module_rollback || log_warning "模块 [${alias}] 回滚失败，请手动处理"
            fi
            # 根据配置决定是否继续
            if [[ "${UBINIT_STOP_ON_ERROR:-false}" == "true" ]]; then
                log_error "已启用 STOP_ON_ERROR，终止执行"
                exit 1
            fi
        fi
    else
        log_warning "模块 [${alias}] 未实现 module_install()，跳过"
        UBINIT_SKIPPED_MODULES+=("${alias}")
    fi
}

# 按注册顺序执行所有模块
run_all_modules() {
    log_info "开始执行模块队列（共 ${#MODULE_REGISTRY[@]} 个模块）..."
    log_info "已选定模块: ${UBINIT_SELECTED_MODULES:-(全部执行)}"
    log_debug "执行模式: NON_INTERACTIVE=${UBINIT_NON_INTERACTIVE}, DRY_RUN=${UBINIT_DRY_RUN}"

    local entry alias filename
    for entry in "${MODULE_REGISTRY[@]}"; do
        alias="${entry%%:*}"
        filename="${entry##*:}"

        if [[ "${alias}" == "preflight" ]]; then
            # preflight 模块特殊处理
            if [[ "${UBINIT_SKIP_PREFLIGHT}" == "true" ]]; then
                log_warning "跳过系统预检（--skip-preflight），请确保环境符合要求"
                UBINIT_SKIPPED_MODULES+=("preflight")
            else
                # 预检失败就立即中止
                _run_module "${alias}" "${filename}" || {
                    log_error "系统预检失败，终止安装。请修复上述问题后重试。"
                    exit 1
                }
            fi
        else
            _run_module "${alias}" "${filename}"
        fi
    done
}

# =============================================================================
# 8. 交互模式入口
# =============================================================================

# 运行 TUI 菜单，让用户选择要安装的模块
run_interactive_menu() {
    log_info "进入交互模式..."
    # 直接前台运行，菜单返回 0 时全局变量 UBINIT_SELECTED_MODULES 已经自动被修改并 export
    ui_main_menu || {
        log_info "用户取消，退出"
        exit 0
    }
}

# =============================================================================
# 9. 清理与异常处理
# =============================================================================

# 捕获 EXIT 信号，输出最终统计
_on_exit() {
    local exit_code=$?
    local end_time
    end_time="$(date +%s)"
    local elapsed=$(( end_time - UBINIT_START_TIME ))

    echo ""
    if [[ ${exit_code} -eq 0 ]]; then
        log_success "UbuntuInit 完成 (总耗时: ${elapsed}s)"
        _print_summary
    else
        log_error "UbuntuInit 异常退出 (退出码: ${exit_code}, 耗时: ${elapsed}s)"
        _print_summary
    fi
}

# 捕获 INT/TERM 信号
_on_interrupt() {
    echo ""
    log_warning "收到中断信号，正在安全退出..."
    exit 130
}

# 输出执行摘要
_print_summary() {
    echo ""
    log_info "═══════════════ 执行摘要 ═══════════════"
    log_success "成功模块 (${#UBINIT_SUCCESS_MODULES[@]}): ${UBINIT_SUCCESS_MODULES[*]:-无}"
    log_warning "跳过模块 (${#UBINIT_SKIPPED_MODULES[@]}): ${UBINIT_SKIPPED_MODULES[*]:-无}"

    if [[ ${#UBINIT_FAILED_MODULES[@]} -gt 0 ]]; then
        log_error "失败模块 (${#UBINIT_FAILED_MODULES[@]}): ${UBINIT_FAILED_MODULES[*]}"
    fi
    log_info "═══════════════════════════════════════"
}

# =============================================================================
# 10. 主函数
# =============================================================================

main() {
    UBINIT_START_TIME="$(date +%s)"

    # 注册信号处理
    trap '_on_exit' EXIT
    trap '_on_interrupt' INT TERM

    # 解析参数
    parse_args "$@"

    # 初始化日志系统
    logger_init "${UBINIT_VERBOSE}"

    # 显示横幅
    ui_banner

    # 检查 root 权限（最基础检测，不依赖模块）
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "必须以 root 权限运行: sudo bash ${SCRIPT_NAME}"
        exit 1
    fi

    # 进入卸载模式
    if [[ "${UBINIT_UNINSTALL_MODE}" == "true" ]]; then
        log_warning "进入卸载模式"
        # shellcheck source=/dev/null
        [[ -f "${SCRIPT_DIR}/uninstall.sh" ]] && source "${SCRIPT_DIR}/uninstall.sh" && run_uninstall
        exit $?
    fi

    # 加载配置
    load_config

    # 交互模式：弹出菜单让用户选择模块
    if [[ "${UBINIT_NON_INTERACTIVE}" == "false" && -z "${UBINIT_SELECTED_MODULES}" ]]; then
        run_interactive_menu
    fi

    # 执行所有选定模块
    run_all_modules

    # 生成安装报告
    report_generate

    return 0
}

# =============================================================================
# 11. 入口
# =============================================================================
main "$@"
