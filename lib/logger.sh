#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 日志系统
# =============================================================================
# 文件     : lib/logger.sh
# 说明     : 统一日志输出，支持彩色终端 + 文件双路输出
#           : 提供 INFO / SUCCESS / WARNING / ERROR / DEBUG / SECTION / STEP
# 依赖     : 无（纯 bash）
# =============================================================================

# =============================================================================
# 1. 颜色与图标常量
# =============================================================================

# 根据终端能力初始化颜色变量
_logger_setup_colors() {
    # 检测终端颜色支持
    if [[ -t 1 && "${TERM:-dumb}" != "dumb" && -z "${NO_COLOR:-}" ]]; then
        # ── 重置 ──────────────────────────────────────────────────
        LOG_CLR_RESET='\033[0m'
        LOG_CLR_BOLD='\033[1m'
        LOG_CLR_DIM='\033[2m'

        # ── 日志级别色 ─────────────────────────────────────────────
        LOG_CLR_INFO='\033[38;5;81m'       # 天蓝
        LOG_CLR_SUCCESS='\033[38;5;82m'    # 亮绿
        LOG_CLR_WARNING='\033[38;5;220m'   # 金黄
        LOG_CLR_ERROR='\033[38;5;197m'     # 亮红
        LOG_CLR_DEBUG='\033[38;5;244m'     # 中灰
        LOG_CLR_SECTION='\033[38;5;135m'   # 紫色
        LOG_CLR_STEP='\033[38;5;39m'       # 蓝色

        # ── 辅助色 ─────────────────────────────────────────────────
        LOG_CLR_TIME='\033[38;5;238m'      # 深灰（时间戳）
        LOG_CLR_WHITE='\033[38;5;255m'     # 亮白

        # ── 图标（Unicode）─────────────────────────────────────────
        LOG_ICON_INFO='ℹ'
        LOG_ICON_SUCCESS='✓'
        LOG_ICON_WARNING='⚠'
        LOG_ICON_ERROR='✗'
        LOG_ICON_DEBUG='·'
        LOG_ICON_SECTION='◆'
        LOG_ICON_STEP='→'
    else
        # ── 无色回退 ───────────────────────────────────────────────
        LOG_CLR_RESET='';  LOG_CLR_BOLD='';   LOG_CLR_DIM=''
        LOG_CLR_INFO='';   LOG_CLR_SUCCESS=''; LOG_CLR_WARNING=''
        LOG_CLR_ERROR='';  LOG_CLR_DEBUG='';   LOG_CLR_SECTION=''
        LOG_CLR_STEP='';   LOG_CLR_TIME='';    LOG_CLR_WHITE=''

        LOG_ICON_INFO='[I]'; LOG_ICON_SUCCESS='[+]'
        LOG_ICON_WARNING='[!]'; LOG_ICON_ERROR='[X]'
        LOG_ICON_DEBUG='[D]'; LOG_ICON_SECTION='[=]'
        LOG_ICON_STEP='[>]'
    fi

    export LOG_CLR_RESET LOG_CLR_BOLD LOG_CLR_DIM
    export LOG_CLR_INFO LOG_CLR_SUCCESS LOG_CLR_WARNING
    export LOG_CLR_ERROR LOG_CLR_DEBUG LOG_CLR_SECTION
    export LOG_CLR_STEP LOG_CLR_TIME LOG_CLR_WHITE
    export LOG_ICON_INFO LOG_ICON_SUCCESS LOG_ICON_WARNING
    export LOG_ICON_ERROR LOG_ICON_DEBUG LOG_ICON_SECTION LOG_ICON_STEP
}

# =============================================================================
# 2. 内部工具
# =============================================================================

# 获取当前时间戳字符串
_log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 将日志写入文件（剥离 ANSI 颜色码）
_log_to_file() {
    local level="$1"
    local message="$2"

    [[ -z "${UBINIT_LOG_FILE:-}" ]] && return 0

    local log_dir
    log_dir="$(dirname "${UBINIT_LOG_FILE}")"
    [[ -d "${log_dir}" ]] || mkdir -p "${log_dir}" 2>/dev/null || return 0

    # 用 printf 格式写入，sed 剥离颜色码
    printf '[%s] [%-7s] %s\n' "$(_log_timestamp)" "${level}" "${message}" \
        | sed 's/\x1b\[[0-9;]*[mK]//g' >> "${UBINIT_LOG_FILE}" 2>/dev/null || true
}

# 核心打印函数（终端 + 文件双路输出）
_log_print() {
    local color="$1"
    local icon="$2"
    local level="$3"
    local message="$4"

    # ── 终端输出（彩色）────────────────────────────────────────────
    printf "${LOG_CLR_DIM}${LOG_CLR_TIME}%s${LOG_CLR_RESET} ${color}${LOG_CLR_BOLD}%s${LOG_CLR_RESET} ${color}%-9s${LOG_CLR_RESET} %s\n" \
        "$(_log_timestamp)" "${icon}" "[${level}]" "${message}"

    # ── 文件输出（无色）────────────────────────────────────────────
    _log_to_file "${level}" "${message}"
}

# =============================================================================
# 3. 公共日志 API
# =============================================================================

# 普通信息
log_info() {
    _log_print "${LOG_CLR_INFO}" "${LOG_ICON_INFO}" "INFO" "$*"
}

# 操作成功
log_success() {
    _log_print "${LOG_CLR_SUCCESS}" "${LOG_ICON_SUCCESS}" "SUCCESS" "$*"
}

# 警告（不中断）
log_warning() {
    _log_print "${LOG_CLR_WARNING}" "${LOG_ICON_WARNING}" "WARNING" "$*"
}

# 错误（输出到 stderr）
log_error() {
    _log_print "${LOG_CLR_ERROR}" "${LOG_ICON_ERROR}" "ERROR" "$*" >&2
}

# 调试（仅 UBINIT_VERBOSE=true 时输出）
log_debug() {
    [[ "${UBINIT_VERBOSE:-false}" != "true" ]] && return 0
    _log_print "${LOG_CLR_DEBUG}" "${LOG_ICON_DEBUG}" "DEBUG" "$*"
}

# 节标题（大横幅）
log_section() {
    local title="$1"
    local pad=2
    local line_char='─'
    local width=58
    local side
    side="$(printf "${line_char}%.0s" $(seq 1 $(( (width - ${#title} - 2) / 2 ))))"

    echo ""
    printf "${LOG_CLR_SECTION}${LOG_CLR_BOLD}  %s %s %s${LOG_CLR_RESET}\n" \
        "${side}" "${title}" "${side}"
    echo ""

    _log_to_file "SECTION" "=== ${title} ==="
}

# 带编号的步骤提示
log_step() {
    local step="$1"
    local total="$2"
    local message="$3"

    printf "  ${LOG_CLR_STEP}${LOG_CLR_BOLD}[%d/%d]${LOG_CLR_RESET} ${LOG_CLR_STEP}${LOG_ICON_STEP}${LOG_CLR_RESET} %s\n" \
        "${step}" "${total}" "${message}"

    _log_to_file "STEP" "[${step}/${total}] ${message}"
}

# 行内进度条（调用方负责轮询更新）
# 用法: log_progress 当前值 总量 描述
log_progress() {
    local current="$1"
    local total="$2"
    local label="${3:-}"
    local bar_width=40
    local filled=$(( current * bar_width / total ))
    local empty=$(( bar_width - filled ))
    local pct=$(( current * 100 / total ))

    local bar
    bar="$(printf '█%.0s' $(seq 1 "${filled}"))$(printf '░%.0s' $(seq 1 "${empty}"))"

    printf "\r  ${LOG_CLR_INFO}[%-${bar_width}s]${LOG_CLR_RESET} ${LOG_CLR_BOLD}%3d%%${LOG_CLR_RESET}  %s" \
        "${bar}" "${pct}" "${label}"

    (( current >= total )) && echo ""
}

# =============================================================================
# 4. 初始化入口
# =============================================================================

# 初始化日志系统（必须在第一个 log_* 调用前执行）
# 参数: $1 = verbose (true|false)
logger_init() {
    local verbose="${1:-false}"

    _logger_setup_colors

    # 创建日志文件并写入会话头
    if [[ -n "${UBINIT_LOG_FILE:-}" ]]; then
        local log_dir
        log_dir="$(dirname "${UBINIT_LOG_FILE}")"
        mkdir -p "${log_dir}" 2>/dev/null || true

        {
            echo "========================================"
            echo " UbuntuInit 会话开始: $(date '+%Y-%m-%d %H:%M:%S')"
            echo " PID: $$  User: $(id -un)"
            echo "========================================"
        } >> "${UBINIT_LOG_FILE}" 2>/dev/null || true
    fi

    log_debug "日志系统初始化完成 (verbose=${verbose})"
}
