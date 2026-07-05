#!/usr/bin/env bash
# =============================================================================
# 2048 — 纯 Bash 终端实现
# =============================================================================
# 控制: ↑↓←→ 方向键合并数字  q 退出  r 重新开始
# 目标: 合并数字块达到 2048！
# =============================================================================

# ── 颜色 ───────────────────────────────────────────────────────────────────
R='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'

# 每个数值对应的背景/前景色
declare -A TILE_COLOR
TILE_COLOR[0]="$(   printf '\033[48;5;236m\033[38;5;240m')"
TILE_COLOR[2]="$(   printf '\033[48;5;230m\033[38;5;240m')"
TILE_COLOR[4]="$(   printf '\033[48;5;223m\033[38;5;240m')"
TILE_COLOR[8]="$(   printf '\033[48;5;208m\033[38;5;255m')"
TILE_COLOR[16]="$(  printf '\033[48;5;196m\033[38;5;255m')"
TILE_COLOR[32]="$(  printf '\033[48;5;160m\033[38;5;255m')"
TILE_COLOR[64]="$(  printf '\033[48;5;124m\033[38;5;255m')"
TILE_COLOR[128]="$( printf '\033[48;5;226m\033[38;5;240m')"
TILE_COLOR[256]="$( printf '\033[48;5;220m\033[38;5;240m')"
TILE_COLOR[512]="$( printf '\033[48;5;214m\033[38;5;255m')"
TILE_COLOR[1024]="$(printf '\033[48;5;202m\033[38;5;255m')"
TILE_COLOR[2048]="$(printf '\033[48;5;190m\033[1m\033[38;5;232m')"

C_WHT='\033[38;5;255m'; C_YEL='\033[38;5;226m'; C_CYN='\033[38;5;51m'
C_GRN='\033[38;5;46m';  C_RED='\033[38;5;196m'; C_MAG='\033[38;5;201m'
C_ORG='\033[38;5;214m'
BG_DRK='\033[48;5;234m'; BG_BOARD='\033[48;5;238m'

# ── 游戏状态 ───────────────────────────────────────────────────────────────
declare -a BOARD          # 4×4 扁平数组（index = r*4+c）
SCORE=0; BEST=0; MOVED=false; WIN=false; GAME_OVER=false
BEST_FILE="/tmp/.2048_best"

# ── 终端控制 ───────────────────────────────────────────────────────────────
_hide() { printf '\033[?25l'; }
_show() { printf '\033[?25h'; }
_cls()  { printf '\033[2J\033[H'; }
_at()   { printf "\033[%d;%dH" "$1" "$2"; }

_cleanup() { _show; tput rmcup 2>/dev/null; stty echo sane 2>/dev/null; clear; }
trap _cleanup EXIT INT TERM

# ── 读取按键 ───────────────────────────────────────────────────────────────
_read_key() {
    local key
    IFS= read -r -s -n1 key
    if [[ "${key}" == $'\033' ]]; then
        IFS= read -r -s -n2 -t 0.1 rest || true
        key="${key}${rest}"
    fi
    case "${key}" in
        $'\033[A') echo "UP"    ;;
        $'\033[B') echo "DOWN"  ;;
        $'\033[C') echo "RIGHT" ;;
        $'\033[D') echo "LEFT"  ;;
        q|Q)       echo "QUIT"  ;;
        r|R)       echo "RESET" ;;
        *)         echo ""      ;;
    esac
}

# ── 棋盘操作 ───────────────────────────────────────────────────────────────
_init_board() {
    BOARD=( 0 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0 )
    SCORE=0; WIN=false; GAME_OVER=false
    [[ -f "${BEST_FILE}" ]] && BEST="$(cat "${BEST_FILE}" 2>/dev/null || echo 0)"
    _add_random_tile
    _add_random_tile
}

_get() { echo "${BOARD[$(( $1 * 4 + $2 ))]]}"; }
_set() { BOARD[$(( $1 * 4 + $2 ))]="${3}"; }

# 找所有空格子，随机放一个 2（90%）或 4（10%）
_add_random_tile() {
    local -a empty=()
    local i
    for (( i=0; i<16; i++ )); do
        [[ "${BOARD[$i]}" -eq 0 ]] && empty+=("${i}")
    done
    [[ ${#empty[@]} -eq 0 ]] && return 1
    local idx="${empty[$(( RANDOM % ${#empty[@]} ))]}"
    BOARD["${idx}"]=$(( RANDOM % 10 < 9 ? 2 : 4 ))
}

# 压缩一行（去掉零，左对齐）
_compress_row() {
    local -a row=("$@")
    local -a out=()
    local v
    for v in "${row[@]}"; do
        [[ "${v}" -ne 0 ]] && out+=("${v}")
    done
    while (( ${#out[@]} < 4 )); do out+=(0); done
    echo "${out[@]}"
}

# 合并一行（从左到右）
_merge_row() {
    local -a row=("$@")
    local i
    for (( i=0; i<3; i++ )); do
        if [[ "${row[$i]}" -ne 0 && "${row[$i]}" -eq "${row[$(( i+1 ))]}" ]]; then
            local merged=$(( row[i] * 2 ))
            row[$i]="${merged}"
            row[$(( i+1 ))]=0
            (( SCORE += merged ))
            (( SCORE > BEST )) && BEST="${SCORE}" && echo "${BEST}" > "${BEST_FILE}"
            [[ "${merged}" -eq 2048 ]] && WIN=true
        fi
    done
    echo "${row[@]}"
}

# 处理一行（压缩→合并→压缩），返回是否有变化
_process_row() {
    local -a orig=("$@")
    read -r -a compressed <<< "$(_compress_row "${orig[@]}")"
    read -r -a merged     <<< "$(_merge_row    "${compressed[@]}")"
    read -r -a final      <<< "$(_compress_row "${merged[@]}")"
    echo "${final[@]}"
    # 检测是否有变化
    local i
    for (( i=0; i<4; i++ )); do
        [[ "${orig[$i]}" != "${final[$i]}" ]] && return 0
    done
    return 1
}

# 四个方向移动
_move_left() {
    MOVED=false
    local r
    for (( r=0; r<4; r++ )); do
        local -a row=( "$(_get "${r}" 0)" "$(_get "${r}" 1)" "$(_get "${r}" 2)" "$(_get "${r}" 3)" )
        local -a new_row
        if read -r -a new_row <<< "$(_process_row "${row[@]}")"; then MOVED=true; fi
        local c; for (( c=0; c<4; c++ )); do _set "${r}" "${c}" "${new_row[$c]}"; done
    done
}

_move_right() {
    MOVED=false
    local r
    for (( r=0; r<4; r++ )); do
        local -a row=( "$(_get "${r}" 3)" "$(_get "${r}" 2)" "$(_get "${r}" 1)" "$(_get "${r}" 0)" )
        local -a new_row
        if read -r -a new_row <<< "$(_process_row "${row[@]}")"; then MOVED=true; fi
        local c; for (( c=0; c<4; c++ )); do _set "${r}" "$(( 3-c ))" "${new_row[$c]}"; done
    done
}

_move_up() {
    MOVED=false
    local c
    for (( c=0; c<4; c++ )); do
        local -a col=( "$(_get 0 "${c}")" "$(_get 1 "${c}")" "$(_get 2 "${c}")" "$(_get 3 "${c}")" )
        local -a new_col
        if read -r -a new_col <<< "$(_process_row "${col[@]}")"; then MOVED=true; fi
        local r; for (( r=0; r<4; r++ )); do _set "${r}" "${c}" "${new_col[$r]}"; done
    done
}

_move_down() {
    MOVED=false
    local c
    for (( c=0; c<4; c++ )); do
        local -a col=( "$(_get 3 "${c}")" "$(_get 2 "${c}")" "$(_get 1 "${c}")" "$(_get 0 "${c}")" )
        local -a new_col
        if read -r -a new_col <<< "$(_process_row "${col[@]}")"; then MOVED=true; fi
        local r; for (( r=0; r<4; r++ )); do _set "$(( 3-r ))" "${c}" "${new_col[$r]}"; done
    done
}

# 检测游戏结束（无空格且无可合并相邻格）
_check_game_over() {
    local r c val
    for (( r=0; r<4; r++ )); do
        for (( c=0; c<4; c++ )); do
            val="$(_get "${r}" "${c}")"
            [[ "${val}" -eq 0 ]] && return 1
            (( c < 3 )) && [[ "${val}" -eq "$(_get "${r}" "$(( c+1 ))")" ]] && return 1
            (( r < 3 )) && [[ "${val}" -eq "$(_get "$(( r+1 ))" "${c}")" ]] && return 1
        done
    done
    return 0
}

# ── 渲染 ───────────────────────────────────────────────────────────────────
# 每个格子宽 8 字符，高 3 行
TILE_W=8
TILE_H=3
BOARD_START_ROW=6
BOARD_START_COL=8

_render_tile() {
    local screen_row="$1" screen_col="$2" val="$3"
    local color="${TILE_COLOR[${val}]:-${TILE_COLOR[0]}}"
    local label

    if [[ "${val}" -eq 0 ]]; then
        label="        "
    else
        label="$(printf '%*s%*s' "$(( (8 + ${#val}) / 2 ))" "${val}" "$(( (8 - ${#val}) / 2 + 1 ))" "")"
        label="${label:0:8}"
    fi

    # 三行：空行、数字行、空行
    _at "${screen_row}"       "${screen_col}"; printf "${color}        ${R}"
    _at $(( screen_row + 1 )) "${screen_col}"; printf "${color}%s${R}" "${label}"
    _at $(( screen_row + 2 )) "${screen_col}"; printf "${color}        ${R}"
}

_render_board() {
    local r c sr sc val
    for (( r=0; r<4; r++ )); do
        for (( c=0; c<4; c++ )); do
            val="$(_get "${r}" "${c}")"
            sr=$(( BOARD_START_ROW + r * TILE_H + r ))
            sc=$(( BOARD_START_COL + c * TILE_W + c ))
            _render_tile "${sr}" "${sc}" "${val}"
        done
    done
}

_render_hud() {
    _at 1 "${BOARD_START_COL}"
    printf "${BOLD}${C_YEL} ██████╗  ██████╗ ██╗  ██╗ █████╗${R}"
    _at 2 "${BOARD_START_COL}"
    printf "${BOLD}${C_ORG} ╚════██╗██╔═████╗██║  ██║██╔══██╗${R}"
    _at 3 "${BOARD_START_COL}"
    printf "${BOLD}${C_RED}  █████╔╝██║██╔██║███████║╚█████╔╝${R}"
    _at 4 "${BOARD_START_COL}"
    printf "${BOLD}${C_MAG} ██╔═══╝ ████╔╝██║╚════██║ ╚═══██╗${R}"
    _at 5 "${BOARD_START_COL}"
    printf "${BOLD}${C_CYN} ███████╗╚██████╔╝     ██║ █████╔╝${R}"

    # 分数框
    local score_col=$(( BOARD_START_COL + 37 ))
    _at 1 "${score_col}"; printf "${BG_DRK}${C_WHT}${BOLD}  得分  ${R}"
    _at 2 "${score_col}"; printf "${BG_DRK}${C_YEL}${BOLD} %-6d ${R}" "${SCORE}"
    _at 3 "${score_col}"; printf "${BG_DRK}${C_WHT}${BOLD}  最佳  ${R}"
    _at 4 "${score_col}"; printf "${BG_DRK}${C_ORG}${BOLD} %-6d ${R}" "${BEST}"

    # 操作提示
    local tips_row=$(( BOARD_START_ROW + 4 * TILE_H + 6 ))
    _at "${tips_row}" "${BOARD_START_COL}"
    printf "${DIM}  ↑↓←→ 移动   r 重新开始   q 退出${R}"
}

_render_overlay() {
    local mid_row=$(( BOARD_START_ROW + 6 ))
    local mid_col=$(( BOARD_START_COL + 2 ))

    if [[ "${WIN}" == "true" ]]; then
        _at "${mid_row}"     "${mid_col}"; printf '\033[48;5;190m\033[38;5;232m\033[1m  ╔══════════════════════╗  \033[0m'
        _at $(( mid_row+1 )) "${mid_col}"; printf '\033[48;5;190m\033[38;5;232m\033[1m  ║  🎉 YOU WIN! 2048! 🎉 ║  \033[0m'
        _at $(( mid_row+2 )) "${mid_col}"; printf '\033[48;5;190m\033[38;5;232m\033[1m  ║  得分: %-14d║  \033[0m' "${SCORE}"
        _at $(( mid_row+3 )) "${mid_col}"; printf '\033[48;5;190m\033[38;5;232m\033[1m  ║  继续玩 或 r=重来      ║  \033[0m'
        _at $(( mid_row+4 )) "${mid_col}"; printf '\033[48;5;190m\033[38;5;232m\033[1m  ╚══════════════════════╝  \033[0m'
    elif [[ "${GAME_OVER}" == "true" ]]; then
        _at "${mid_row}"     "${mid_col}"; printf '\033[48;5;88m\033[38;5;255m\033[1m  ╔══════════════════════╗  \033[0m'
        _at $(( mid_row+1 )) "${mid_col}"; printf '\033[48;5;88m\033[38;5;255m\033[1m  ║    💀 GAME OVER 💀    ║  \033[0m'
        _at $(( mid_row+2 )) "${mid_col}"; printf '\033[48;5;88m\033[38;5;226m\033[1m  ║  得分: %-14d║  \033[0m' "${SCORE}"
        _at $(( mid_row+3 )) "${mid_col}"; printf '\033[48;5;88m\033[38;5;255m\033[1m  ║  r=重新开始  q=退出   ║  \033[0m'
        _at $(( mid_row+4 )) "${mid_col}"; printf '\033[48;5;88m\033[38;5;255m\033[1m  ╚══════════════════════╝  \033[0m'
    fi
}

# ── 主程序 ─────────────────────────────────────────────────────────────────
main() {
    tput smcup 2>/dev/null
    stty -echo 2>/dev/null
    _hide

    while true; do
        _cls
        _init_board
        _render_hud
        _render_board

        while true; do
            local key
            key="$(_read_key)"

            case "${key}" in
                QUIT)  return ;;
                RESET) break  ;;
                UP)    _move_up    ;;
                DOWN)  _move_down  ;;
                LEFT)  _move_left  ;;
                RIGHT) _move_right ;;
                *)     continue    ;;
            esac

            [[ "${key}" == "RESET" ]] && break

            if [[ "${MOVED}" == "true" ]]; then
                _add_random_tile
                _render_board
                _render_hud
            fi

            # 胜利检测（显示提示但允许继续）
            if [[ "${WIN}" == "true" ]] && ! ${_WIN_SHOWN:-false}; then
                _render_overlay
                _WIN_SHOWN=true
            fi

            # 游戏结束检测
            if _check_game_over; then
                GAME_OVER=true
                _render_overlay

                # 等待 r 或 q
                while true; do
                    key="$(_read_key)"
                    [[ "${key}" == "RESET" ]] && break 2
                    [[ "${key}" == "QUIT"  ]] && return
                done
            fi
        done
    done
}

main
