#!/usr/bin/env bash
# =============================================================================
# 扫雷 Minesweeper — 纯 Bash 终端实现
# =============================================================================
# 控制: ↑↓←→ 移动光标  Space/Enter 翻开  f 插旗  r 重来  q 退出
# 难度: 可在游戏开始时选择
# =============================================================================

# ── 颜色 ───────────────────────────────────────────────────────────────────
R='\033[0m'; BOLD='\033[1m'; DIM='\033[2m'
C_WHT='\033[38;5;255m'; C_GRY='\033[38;5;245m'
C_RED='\033[38;5;196m'; C_YEL='\033[38;5;226m'
C_GRN='\033[38;5;46m';  C_CYN='\033[38;5;51m'
C_MAG='\033[38;5;201m'; C_ORG='\033[38;5;214m'
C_BLU='\033[38;5;27m';  C_PNK='\033[38;5;213m'

BG_HIDDEN='\033[48;5;240m'    # 未翻开格子
BG_SHOWN='\033[48;5;234m'     # 已翻开格子
BG_FLAG='\033[48;5;52m'       # 插旗格子
BG_MINE='\033[48;5;88m'       # 地雷格（游戏结束时显示）
BG_CURSOR='\033[48;5;33m'     # 光标
BG_WIN='\033[48;5;22m'        # 胜利格子

# 数字颜色（1-8）
declare -a NUM_COLOR=(
    ""                      # 0（不显示）
    '\033[38;5;27m\033[1m'  # 1 蓝
    '\033[38;5;46m\033[1m'  # 2 绿
    '\033[38;5;196m\033[1m' # 3 红
    '\033[38;5;19m\033[1m'  # 4 深蓝
    '\033[38;5;88m\033[1m'  # 5 暗红
    '\033[38;5;51m\033[1m'  # 6 青
    '\033[38;5;201m\033[1m' # 7 品红
    '\033[38;5;245m\033[1m' # 8 灰
)

# ── 难度配置 ───────────────────────────────────────────────────────────────
# [难度名, 行数, 列数, 地雷数]
declare -A DIFF_ROWS=( [easy]=9  [medium]=16 [hard]=16 )
declare -A DIFF_COLS=( [easy]=9  [medium]=16 [hard]=30 )
declare -A DIFF_MINES=([easy]=10 [medium]=40 [hard]=99 )

ROWS=9; COLS=9; TOTAL_MINES=10
DIFF="easy"

# ── 游戏状态数组 ───────────────────────────────────────────────────────────
# MINE[r,c]    : 1=地雷
# REVEAL[r,c]  : 1=已翻开
# FLAG[r,c]    : 1=已插旗
# ADJ[r,c]     : 周围地雷数（0-8）
declare -A MINE REVEAL FLAG ADJ

CURSOR_R=0; CURSOR_C=0
FLAGS_LEFT=0; CELLS_LEFT=0
FIRST_CLICK=true; GAME_STATE="play"  # play / won / lost

START_TIME=0

# ── 终端控制 ───────────────────────────────────────────────────────────────
_hide() { printf '\033[?25l'; }
_show() { printf '\033[?25h'; }
_cls()  { printf '\033[2J\033[H'; }
_at()   { printf "\033[%d;%dH" "$1" "$2"; }

_cleanup() { _show; tput rmcup 2>/dev/null; stty echo sane 2>/dev/null; clear; }
trap _cleanup EXIT INT TERM

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
        $'\n'|$'\r'|' ') echo "DIG"  ;;
        f|F) echo "FLAG"  ;;
        r|R) echo "RESET" ;;
        q|Q) echo "QUIT"  ;;
        *)   echo ""      ;;
    esac
}

# ── 棋盘布局 ───────────────────────────────────────────────────────────────
BOARD_TOP=6
BOARD_LEFT=4
CELL_W=4    # 每格显示宽度（含分隔符）

_scr_row() { echo $(( BOARD_TOP + $1 * 2 )); }
_scr_col() { echo $(( BOARD_LEFT + $2 * CELL_W )); }

# ── 初始化棋盘 ─────────────────────────────────────────────────────────────
_init_board() {
    MINE=(); REVEAL=(); FLAG=(); ADJ=()
    FIRST_CLICK=true; GAME_STATE="play"
    FLAGS_LEFT="${TOTAL_MINES}"
    CELLS_LEFT=$(( ROWS * COLS - TOTAL_MINES ))
    START_TIME="${SECONDS}"
    CURSOR_R=0; CURSOR_C=0

    local r c
    for (( r=0; r<ROWS; r++ )); do
        for (( c=0; c<COLS; c++ )); do
            MINE[$r,$c]=0; REVEAL[$r,$c]=0
            FLAG[$r,$c]=0; ADJ[$r,$c]=0
        done
    done
}

# 首次点击后生成地雷（确保首次安全）
_place_mines() {
    local safe_r="$1" safe_c="$2"
    local placed=0
    local r c

    while (( placed < TOTAL_MINES )); do
        r=$(( RANDOM % ROWS ))
        c=$(( RANDOM % COLS ))
        # 避开首次点击及周围
        local dr dc skip=false
        for (( dr=-1; dr<=1; dr++ )); do
            for (( dc=-1; dc<=1; dc++ )); do
                local nr=$(( safe_r + dr )) nc=$(( safe_c + dc ))
                if (( nr == r && nc == c )); then skip=true; fi
            done
        done
        ${skip} && continue
        [[ "${MINE[$r,$c]}" -eq 1 ]] && continue
        MINE[$r,$c]=1
        (( placed++ ))
    done

    # 计算各格子周围地雷数
    for (( r=0; r<ROWS; r++ )); do
        for (( c=0; c<COLS; c++ )); do
            [[ "${MINE[$r,$c]}" -eq 1 ]] && { ADJ[$r,$c]=-1; continue; }
            local count=0 dr dc
            for (( dr=-1; dr<=1; dr++ )); do
                for (( dc=-1; dc<=1; dc++ )); do
                    local nr=$(( r + dr )) nc=$(( c + dc ))
                    (( nr>=0 && nr<ROWS && nc>=0 && nc<COLS )) && \
                        (( count += MINE[$nr,$nc] ))
                done
            done
            ADJ[$r,$c]="${count}"
        done
    done
}

# 递归翻开（BFS 展开空白区域）
_reveal() {
    local start_r="$1" start_c="$2"
    local -a queue_r=( "${start_r}" ) queue_q=( "${start_c}" )
    local head=0

    while (( head < ${#queue_r[@]} )); do
        local r="${queue_r[$head]}" c="${queue_q[$head]}"
        (( head++ ))

        [[ "${REVEAL[$r,$c]}" -eq 1 ]] && continue
        [[ "${FLAG[$r,$c]}"   -eq 1 ]] && continue

        REVEAL[$r,$c]=1
        (( CELLS_LEFT-- ))

        # 如果是空白格（周围0个地雷），递归展开
        if [[ "${ADJ[$r,$c]}" -eq 0 ]]; then
            local dr dc
            for (( dr=-1; dr<=1; dr++ )); do
                for (( dc=-1; dc<=1; dc++ )); do
                    local nr=$(( r + dr )) nc=$(( c + dc ))
                    if (( nr>=0 && nr<ROWS && nc>=0 && nc<COLS )) && \
                       [[ "${REVEAL[$nr,$nc]}" -eq 0 ]]; then
                        queue_r+=( "${nr}" ); queue_q+=( "${nc}" )
                    fi
                done
            done
        fi
    done
}

# 显示所有地雷（游戏结束时）
_reveal_all_mines() {
    local r c
    for (( r=0; r<ROWS; r++ )); do
        for (( c=0; c<COLS; c++ )); do
            [[ "${MINE[$r,$c]}" -eq 1 ]] && REVEAL[$r,$c]=1
        done
    done
}

# ── 渲染 ───────────────────────────────────────────────────────────────────
_render_hud() {
    _at 1 "${BOARD_LEFT}"
    printf "${BOLD}${C_MAG}  ╔════════════════════════════════╗${R}"
    _at 2 "${BOARD_LEFT}"
    printf "${BOLD}${C_MAG}  ║  💣 扫 雷 MINESWEEPER 💣      ║${R}"
    _at 3 "${BOARD_LEFT}"
    printf "${BOLD}${C_MAG}  ╠═══════════════╦════════════════╣${R}"
    _at 4 "${BOARD_LEFT}"
    local elapsed=$(( SECONDS - START_TIME ))
    printf "${C_MAG}  ║${R} 🚩 旗帜: ${C_RED}${BOLD}%-4d${R}${C_MAG}  ║${R}  ⏱  时间: ${C_YEL}${BOLD}%-4d${R}秒${C_MAG}  ║${R}" \
        "${FLAGS_LEFT}" "${elapsed}"
    _at 5 "${BOARD_LEFT}"
    printf "${BOLD}${C_MAG}  ╚═══════════════╩════════════════╝${R}"

    # 操作提示
    local tips_col=$(( BOARD_LEFT + COLS * CELL_W + 6 ))
    _at "${BOARD_TOP}" "${tips_col}";   printf "${C_CYN}${BOLD}操作说明${R}"
    _at $(( BOARD_TOP+1 )) "${tips_col}"; printf "${C_WHT}↑↓←→  移动光标${R}"
    _at $(( BOARD_TOP+2 )) "${tips_col}"; printf "${C_WHT}Space  翻开格子${R}"
    _at $(( BOARD_TOP+3 )) "${tips_col}"; printf "${C_WHT}f      插旗/取旗${R}"
    _at $(( BOARD_TOP+4 )) "${tips_col}"; printf "${C_WHT}r      重新开始${R}"
    _at $(( BOARD_TOP+5 )) "${tips_col}"; printf "${C_WHT}q      退出游戏${R}"
    _at $(( BOARD_TOP+7 )) "${tips_col}"; printf "${DIM}难度: ${DIFF}${R}"
    _at $(( BOARD_TOP+8 )) "${tips_col}"; printf "${DIM}${ROWS}x${COLS}  ${TOTAL_MINES}💣${R}"
}

_render_cell() {
    local r="$1" c="$2"
    local sr sc bg label color

    sr="$(_scr_row "${r}")"
    sc="$(_scr_col "${r}" "${c}")"

    local is_cursor=false
    (( r == CURSOR_R && c == CURSOR_C )) && is_cursor=true

    # 渲染上半行（空白行）
    _at "${sr}" "${sc}"
    # 渲染下半行（内容行）
    local content_row=$(( sr + 1 ))
    _at "${content_row}" "${sc}"

    if [[ "${REVEAL[$r,$c]}" -eq 1 ]]; then
        # 已翻开
        if [[ "${MINE[$r,$c]}" -eq 1 ]]; then
            # 地雷
            bg="${BG_MINE}"
            label=" 💣 "
            color="${C_RED}"
        else
            bg="${BG_SHOWN}"
            local adj="${ADJ[$r,$c]}"
            if (( adj == 0 )); then
                label="    "; color="${C_GRY}"
            else
                label=" ${adj}  "
                color="${NUM_COLOR[$adj]}"
            fi
        fi

        ${is_cursor} && bg="${BG_WIN}"
        _at "${sr}"           "${sc}"; printf "${bg}    ${R}"
        _at "${content_row}"  "${sc}"; printf "${bg}${color}%s${R}" "${label}"

    elif [[ "${FLAG[$r,$c]}" -eq 1 ]]; then
        # 插旗
        bg="${BG_FLAG}"; ${is_cursor} && bg="${BG_CURSOR}"
        _at "${sr}"           "${sc}"; printf "${bg}    ${R}"
        _at "${content_row}"  "${sc}"; printf "${bg}${C_YEL}${BOLD} 🚩  ${R}"

    else
        # 未翻开
        bg="${BG_HIDDEN}"; ${is_cursor} && bg="${BG_CURSOR}"
        _at "${sr}"           "${sc}"; printf "${bg}    ${R}"
        _at "${content_row}"  "${sc}"; printf "${bg}${C_GRY} ▓▓ ${R}"
    fi
}

_render_board() {
    local r c
    for (( r=0; r<ROWS; r++ )); do
        for (( c=0; c<COLS; c++ )); do
            _render_cell "${r}" "${c}"
        done
        # 行间分隔线
        local sep_row=$(( BOARD_TOP + r * 2 + 2 ))
        _at "${sep_row}" "${BOARD_LEFT}"
        printf "${DIM}"
        local col
        for (( col=0; col<COLS; col++ )); do printf "────"; done
        printf "${R}"
    done
}

_render_overlay() {
    local mid_row=$(( BOARD_TOP + ROWS ))
    local mid_col="${BOARD_LEFT}"

    if [[ "${GAME_STATE}" == "won" ]]; then
        _at $(( mid_row+2 )) "${mid_col}"
        printf '\033[48;5;22m\033[38;5;255m\033[1m  🎉 恭喜你！全部扫清！得分: %-5d  r=重来  q=退出  \033[0m' \
            "$(( (ROWS * COLS - TOTAL_MINES) * TOTAL_MINES ))"
    elif [[ "${GAME_STATE}" == "lost" ]]; then
        _at $(( mid_row+2 )) "${mid_col}"
        printf '\033[48;5;88m\033[38;5;255m\033[1m  💥 BOOM！踩到地雷了！继续吗？r=重来  q=退出        \033[0m'
    fi
}

# ── 难度选择菜单 ───────────────────────────────────────────────────────────
_difficulty_menu() {
    _cls
    _hide

    local -a diffs=("easy" "medium" "hard")
    local -a labels=(
        "🟢 简单   9×9   10 个地雷"
        "🟡 中等  16×16  40 个地雷"
        "🔴 困难  16×30  99 个地雷"
    )
    local selected=0

    while true; do
        _at 2 8; printf "${BOLD}${C_CYN}╔═════════════════════════════╗${R}"
        _at 3 8; printf "${BOLD}${C_CYN}║   💣 选择游戏难度 💣        ║${R}"
        _at 4 8; printf "${BOLD}${C_CYN}╠═════════════════════════════╣${R}"

        local i
        for (( i=0; i<3; i++ )); do
            _at $(( 5 + i )) 8
            if (( i == selected )); then
                printf "${BOLD}${C_CYN}║${R} ${BOLD}\033[48;5;238m${C_WHT} ▶ %-27s ${R}${BOLD}${C_CYN}║${R}" "${labels[$i]}"
            else
                printf "${BOLD}${C_CYN}║${R}   ${DIM}%-27s ${R}${BOLD}${C_CYN}║${R}" "${labels[$i]}"
            fi
        done

        _at 8 8; printf "${BOLD}${C_CYN}╚═════════════════════════════╝${R}"
        _at 9 8; printf "${DIM}↑↓ 选择  Enter 确认  q 退出${R}"

        local key
        key="$(_read_key)"
        case "${key}" in
            UP)    (( selected = (selected + 2) % 3 )) ;;
            DOWN)  (( selected = (selected + 1) % 3 )) ;;
            DIG)
                DIFF="${diffs[$selected]}"
                ROWS="${DIFF_ROWS[$DIFF]}"
                COLS="${DIFF_COLS[$DIFF]}"
                TOTAL_MINES="${DIFF_MINES[$DIFF]}"
                return 0
                ;;
            QUIT)  return 1 ;;
        esac
    done
}

# ── 主游戏循环 ─────────────────────────────────────────────────────────────
_game_loop() {
    _cls
    _init_board
    _render_hud
    _render_board

    local last_hud_update="${SECONDS}"

    while [[ "${GAME_STATE}" == "play" ]]; do
        # 每秒刷新 HUD（计时器）
        if (( SECONDS != last_hud_update )); then
            _render_hud
            last_hud_update="${SECONDS}"
        fi

        local key
        key="$(_read_key)"

        case "${key}" in
            UP)    (( CURSOR_R = (CURSOR_R - 1 + ROWS) % ROWS )) ;;
            DOWN)  (( CURSOR_R = (CURSOR_R + 1) % ROWS )) ;;
            LEFT)  (( CURSOR_C = (CURSOR_C - 1 + COLS) % COLS )) ;;
            RIGHT) (( CURSOR_C = (CURSOR_C + 1) % COLS )) ;;

            DIG)
                [[ "${FLAG[$CURSOR_R,$CURSOR_C]}" -eq 1 ]] && continue
                [[ "${REVEAL[$CURSOR_R,$CURSOR_C]}" -eq 1 ]] && continue

                # 首次点击：生成地雷
                if [[ "${FIRST_CLICK}" == "true" ]]; then
                    _place_mines "${CURSOR_R}" "${CURSOR_C}"
                    FIRST_CLICK=false
                fi

                if [[ "${MINE[$CURSOR_R,$CURSOR_C]}" -eq 1 ]]; then
                    # 踩雷！
                    REVEAL[$CURSOR_R,$CURSOR_C]=1
                    GAME_STATE="lost"
                    _reveal_all_mines
                else
                    _reveal "${CURSOR_R}" "${CURSOR_C}"
                    [[ "${CELLS_LEFT}" -eq 0 ]] && GAME_STATE="won"
                fi
                ;;

            FLAG)
                [[ "${REVEAL[$CURSOR_R,$CURSOR_C]}" -eq 1 ]] && continue
                if [[ "${FLAG[$CURSOR_R,$CURSOR_C]}" -eq 1 ]]; then
                    FLAG[$CURSOR_R,$CURSOR_C]=0
                    (( FLAGS_LEFT++ ))
                else
                    FLAG[$CURSOR_R,$CURSOR_C]=1
                    (( FLAGS_LEFT-- ))
                fi
                ;;

            RESET) return 0 ;;
            QUIT)  return 1 ;;
            *)     continue ;;
        esac

        # 更新光标前后的格子
        _render_board
        _render_hud
    done

    # 游戏结束
    _render_board
    _render_overlay

    while true; do
        local key
        key="$(_read_key)"
        [[ "${key}" == "RESET" ]] && return 0
        [[ "${key}" == "QUIT"  ]] && return 1
    done
}

# ── 主程序 ─────────────────────────────────────────────────────────────────
main() {
    tput smcup 2>/dev/null
    stty -echo 2>/dev/null
    _hide

    while true; do
        _difficulty_menu || break
        while true; do
            _game_loop || return
        done
    done
}

main
