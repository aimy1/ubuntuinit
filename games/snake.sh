#!/usr/bin/env bash
# =============================================================================
# 贪吃蛇 Snake — 纯 Bash 终端实现
# =============================================================================
# 控制: ↑↓←→ 方向键  q 退出  r 重新开始
# =============================================================================

# ── 颜色 ───────────────────────────────────────────────────────────────────
R='\033[0m';  BOLD='\033[1m';  DIM='\033[2m'
C_GRN='\033[38;5;46m';   C_GRN2='\033[38;5;82m'
C_RED='\033[38;5;196m';  C_YEL='\033[38;5;226m'
C_CYN='\033[38;5;51m';   C_MAG='\033[38;5;201m'
C_ORG='\033[38;5;214m';  C_WHT='\033[38;5;255m'
C_DRK='\033[38;5;240m'
BG_BLK='\033[48;5;232m'; BG_GRN='\033[48;5;22m'
BG_RED='\033[48;5;88m';  BG_YEL='\033[48;5;58m'

# ── 游戏参数 ───────────────────────────────────────────────────────────────
BOARD_ROWS=22          # 游戏区行数
BOARD_COLS=50          # 游戏区列数（宽字符时每格=2个字符位置）
BOARD_TOP=4            # 游戏区起始行
BOARD_LEFT=4           # 游戏区起始列

CELL_W=2               # 每个格子显示宽度（2字符）
TICK_MS=120            # 初始移动间隔（毫秒）
SPEED_UP_EVERY=5       # 每吃N个食物加速

# ── 游戏状态 ───────────────────────────────────────────────────────────────
declare -a SNAKE_X=()  # 蛇身 X 坐标（列）
declare -a SNAKE_Y=()  # 蛇身 Y 坐标（行）
FOOD_X=0; FOOD_Y=0
DIR_X=1; DIR_Y=0       # 方向向量
SCORE=0; HIGH_SCORE=0
GAME_OVER=false
TICK="${TICK_MS}"
HS_FILE="/tmp/.snake_hs"

# ── 终端控制 ───────────────────────────────────────────────────────────────
_hide() { printf '\033[?25l'; }
_show() { printf '\033[?25h'; }
_cls()  { printf '\033[2J\033[H'; }
_at()   { printf "\033[%d;%dH" "$1" "$2"; }

_cleanup() { _show; tput rmcup 2>/dev/null; stty echo sane 2>/dev/null; clear; }
trap _cleanup EXIT INT TERM

# ── 读取按键（非阻塞，timeout=TICK ms） ───────────────────────────────────
_read_input() {
    local key
    IFS= read -r -s -n1 -t "$(echo "scale=3; ${TICK}/1000" | bc 2>/dev/null || echo 0.12)" key || true
    if [[ "${key}" == $'\033' ]]; then
        IFS= read -r -s -n2 -t 0.05 rest || true
        key="${key}${rest}"
    fi
    echo "${key}"
}

# ── 绘制边框和 UI ──────────────────────────────────────────────────────────
_draw_border() {
    local r="${BOARD_TOP}" c="${BOARD_LEFT}"
    local w=$(( BOARD_COLS * CELL_W + 2 ))
    local h=$(( BOARD_ROWS + 2 ))

    # 上边框
    _at "${r}" "${c}"; printf "${C_CYN}${BOLD}╔"; printf '═%.0s' $(seq 1 $(( w - 2 ))); printf "╗${R}"
    # 下边框
    _at $(( r + h - 1 )) "${c}"; printf "${C_CYN}${BOLD}╚"; printf '═%.0s' $(seq 1 $(( w - 2 ))); printf "╝${R}"
    # 左右边框
    local i
    for (( i=1; i<h-1; i++ )); do
        _at $(( r + i )) "${c}"; printf "${C_CYN}${BOLD}║${R}"
        _at $(( r + i )) $(( c + w - 1 )); printf "${C_CYN}${BOLD}║${R}"
    done
}

_draw_hud() {
    _at 1 "${BOARD_LEFT}"
    printf "${BG_BLK}${C_GRN}${BOLD}  🐍 SNAKE  ${R}"
    printf "${BG_BLK}${C_WHT}  得分: ${C_YEL}${BOLD}%-6d${R}" "${SCORE}"
    printf "${BG_BLK}${C_WHT}  最高: ${C_ORG}${BOLD}%-6d${R}" "${HIGH_SCORE}"
    local spd=$(( (TICK_MS - TICK) / 10 + 1 ))
    printf "${BG_BLK}${C_WHT}  速度: ${C_MAG}${BOLD}%-2d${R}" "${spd}"

    # 操作提示
    local tip_col=$(( BOARD_LEFT + BOARD_COLS * CELL_W + 6 ))
    _at "${BOARD_TOP}" "${tip_col}";   printf "${C_CYN}${BOLD}控制说明${R}"
    _at $(( BOARD_TOP+1 )) "${tip_col}"; printf "${C_WHT}↑↓←→  移动方向${R}"
    _at $(( BOARD_TOP+2 )) "${tip_col}"; printf "${C_WHT}p      暂停/继续${R}"
    _at $(( BOARD_TOP+3 )) "${tip_col}"; printf "${C_WHT}r      重新开始${R}"
    _at $(( BOARD_TOP+4 )) "${tip_col}"; printf "${C_WHT}q      退出游戏${R}"
    _at $(( BOARD_TOP+6 )) "${tip_col}"; printf "${DIM}长度: %d${R}" "${#SNAKE_X[@]}"
}

# ── 坐标转屏幕位置 ─────────────────────────────────────────────────────────
_scr_row() { echo $(( BOARD_TOP + 1 + $1 )); }
_scr_col() { echo $(( BOARD_LEFT + 1 + $1 * CELL_W )); }

# ── 绘制单个格子 ───────────────────────────────────────────────────────────
_draw_cell() {
    local row="$1" col="$2" char="$3" color="$4"
    _at "$(_scr_row "${row}")" "$(_scr_col "${col}")"
    printf "${color}%s${R}" "${char}"
}

_erase_cell() {
    local row="$1" col="$2"
    _at "$(_scr_row "${row}")" "$(_scr_col "${col}")"
    printf "  "
}

# ── 绘制完整蛇 ─────────────────────────────────────────────────────────────
_draw_snake_full() {
    local i
    for (( i=0; i<${#SNAKE_X[@]}; i++ )); do
        if (( i == 0 )); then
            _draw_cell "${SNAKE_Y[$i]}" "${SNAKE_X[$i]}" "██" "${C_GRN}${BOLD}"
        else
            _draw_cell "${SNAKE_Y[$i]}" "${SNAKE_X[$i]}" "▓▓" "${C_GRN2}"
        fi
    done
}

# ── 生成随机食物 ───────────────────────────────────────────────────────────
_place_food() {
    local occupied
    while true; do
        FOOD_X=$(( RANDOM % BOARD_COLS ))
        FOOD_Y=$(( RANDOM % BOARD_ROWS ))
        occupied=false
        local i
        for (( i=0; i<${#SNAKE_X[@]}; i++ )); do
            if (( SNAKE_X[i] == FOOD_X && SNAKE_Y[i] == FOOD_Y )); then
                occupied=true; break
            fi
        done
        [[ "${occupied}" == "false" ]] && break
    done
    # 随机食物种类
    local foods=("🍎" "🍊" "🍋" "🍇" "🍓" "⭐" "💎")
    FOOD_CHAR="${foods[$(( RANDOM % ${#foods[@]} ))]}"
}

_draw_food() {
    _at "$(_scr_row "${FOOD_Y}")" "$(_scr_col "${FOOD_X}")"
    printf "${C_RED}${BOLD}${FOOD_CHAR}${R}"
}

# ── 初始化游戏 ─────────────────────────────────────────────────────────────
_init_game() {
    SNAKE_X=( $(( BOARD_COLS / 2 )) $(( BOARD_COLS / 2 - 1 )) $(( BOARD_COLS / 2 - 2 )) )
    SNAKE_Y=( $(( BOARD_ROWS / 2 )) $(( BOARD_ROWS / 2 ))     $(( BOARD_ROWS / 2 )) )
    DIR_X=1; DIR_Y=0
    SCORE=0; GAME_OVER=false; TICK="${TICK_MS}"
    [[ -f "${HS_FILE}" ]] && HIGH_SCORE="$(cat "${HS_FILE}" 2>/dev/null || echo 0)"

    _cls; _draw_border; _place_food; _draw_food; _draw_snake_full
    _draw_hud
}

# ── 碰撞检测 ───────────────────────────────────────────────────────────────
_check_self_collision() {
    local hx="${SNAKE_X[0]}" hy="${SNAKE_Y[0]}"
    local i
    for (( i=1; i<${#SNAKE_X[@]}; i++ )); do
        (( SNAKE_X[i] == hx && SNAKE_Y[i] == hy )) && return 0
    done
    return 1
}

# ── 游戏结束画面 ───────────────────────────────────────────────────────────
_show_game_over() {
    # 更新最高分
    if (( SCORE > HIGH_SCORE )); then
        HIGH_SCORE="${SCORE}"
        echo "${HIGH_SCORE}" > "${HS_FILE}"
    fi

    local mid_row=$(( BOARD_TOP + BOARD_ROWS / 2 ))
    local mid_col=$(( BOARD_LEFT + BOARD_COLS * CELL_W / 2 - 10 ))

    _at "${mid_row}"       "${mid_col}"; printf "${BG_RED}${C_WHT}${BOLD}  ╔══════════════════╗  ${R}"
    _at $(( mid_row+1 ))   "${mid_col}"; printf "${BG_RED}${C_WHT}${BOLD}  ║   GAME  OVER  ！  ║  ${R}"
    _at $(( mid_row+2 ))   "${mid_col}"; printf "${BG_RED}${C_YEL}${BOLD}  ║  得分: %-10d║  ${R}" "${SCORE}"
    _at $(( mid_row+3 ))   "${mid_col}"; printf "${BG_RED}${C_ORG}${BOLD}  ║  最高: %-10d║  ${R}" "${HIGH_SCORE}"
    _at $(( mid_row+4 ))   "${mid_col}"; printf "${BG_RED}${C_WHT}${BOLD}  ║  r=重来  q=退出   ║  ${R}"
    _at $(( mid_row+5 ))   "${mid_col}"; printf "${BG_RED}${C_WHT}${BOLD}  ╚══════════════════╝  ${R}"
}

# ── 主游戏循环 ─────────────────────────────────────────────────────────────
_game_loop() {
    local pending_dx="${DIR_X}" pending_dy="${DIR_Y}"
    local paused=false

    while true; do
        # 读取输入
        local key
        key="$(_read_input)"

        case "${key}" in
            $'\033[A'|$'\033[A ') # UP
                (( DIR_Y != 1  )) && { pending_dx=0;  pending_dy=-1; } ;;
            $'\033[B') # DOWN
                (( DIR_Y != -1 )) && { pending_dx=0;  pending_dy=1;  } ;;
            $'\033[C') # RIGHT
                (( DIR_X != -1 )) && { pending_dx=1;  pending_dy=0;  } ;;
            $'\033[D') # LEFT
                (( DIR_X != 1  )) && { pending_dx=-1; pending_dy=0;  } ;;
            p|P) paused=$([[ "${paused}" == "true" ]] && echo false || echo true)
                if [[ "${paused}" == "true" ]]; then
                    local pr=$(( BOARD_TOP + BOARD_ROWS / 2 ))
                    local pc=$(( BOARD_LEFT + BOARD_COLS * CELL_W / 2 - 5 ))
                    _at "${pr}" "${pc}"; printf "${BG_YEL}${BOLD}  ⏸  已暂停  ⏸  ${R}"
                fi ;;
            r|R) return 0 ;;   # 重新开始信号
            q|Q) return 1 ;;   # 退出信号
        esac

        [[ "${paused}" == "true" ]] && continue

        # 更新方向
        DIR_X="${pending_dx}"; DIR_Y="${pending_dy}"

        # 计算新蛇头
        local new_hx=$(( SNAKE_X[0] + DIR_X ))
        local new_hy=$(( SNAKE_Y[0] + DIR_Y ))

        # 撞墙检测
        if (( new_hx < 0 || new_hx >= BOARD_COLS || new_hy < 0 || new_hy >= BOARD_ROWS )); then
            GAME_OVER=true; _show_game_over
            while true; do
                key="$(_read_input)"
                [[ "${key}" == "r" || "${key}" == "R" ]] && return 0
                [[ "${key}" == "q" || "${key}" == "Q" ]] && return 1
            done
        fi

        # 移动蛇：新头插入
        SNAKE_X=( "${new_hx}" "${SNAKE_X[@]}" )
        SNAKE_Y=( "${new_hy}" "${SNAKE_Y[@]}" )

        # 自身碰撞
        if _check_self_collision; then
            GAME_OVER=true; _show_game_over
            while true; do
                key="$(_read_input)"
                [[ "${key}" == "r" || "${key}" == "R" ]] && return 0
                [[ "${key}" == "q" || "${key}" == "Q" ]] && return 1
            done
        fi

        # 吃到食物
        if (( new_hx == FOOD_X && new_hy == FOOD_Y )); then
            (( SCORE += 10 ))
            # 加速
            if (( SCORE % (SPEED_UP_EVERY * 10) == 0 && TICK > 50 )); then
                (( TICK -= 10 ))
            fi
            _place_food; _draw_food
        else
            # 移除尾部
            local tail_x="${SNAKE_X[-1]}" tail_y="${SNAKE_Y[-1]}"
            unset 'SNAKE_X[-1]'; unset 'SNAKE_Y[-1]'
            _erase_cell "${tail_y}" "${tail_x}"
        fi

        # 绘制新蛇头（深绿身体颜色跟随）
        _draw_cell "${SNAKE_Y[0]}" "${SNAKE_X[0]}" "██" "${C_GRN}${BOLD}"
        if (( ${#SNAKE_X[@]} > 1 )); then
            _draw_cell "${SNAKE_Y[1]}" "${SNAKE_X[1]}" "▓▓" "${C_GRN2}"
        fi

        _draw_hud
    done
}

# ── 主程序 ─────────────────────────────────────────────────────────────────
main() {
    tput smcup 2>/dev/null
    stty -echo 2>/dev/null
    _hide

    while true; do
        _init_game
        _game_loop || break   # return 1 = 退出
    done
}

main
