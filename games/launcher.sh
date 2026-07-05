#!/usr/bin/env bash
# =============================================================================
# Terminal Games Launcher — 终端游戏启动器
# =============================================================================
# 用法: bash launcher.sh
# 依赖: games/ 目录下的各游戏脚本
# =============================================================================

GAMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 颜色与样式 ─────────────────────────────────────────────────────────────
R='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

C_RED='\033[38;5;196m'
C_YEL='\033[38;5;226m'
C_GRN='\033[38;5;46m'
C_CYN='\033[38;5;51m'
C_MAG='\033[38;5;201m'
C_BLU='\033[38;5;27m'
C_ORG='\033[38;5;214m'
C_WHT='\033[38;5;255m'

BG_DRK='\033[48;5;234m'
BG_HIL='\033[48;5;238m'

# ── 终端控制 ───────────────────────────────────────────────────────────────
_hide_cursor() { printf '\033[?25l'; }
_show_cursor() { printf '\033[?25h'; }
_clear()       { printf '\033[2J\033[H'; }
_goto()        { printf "\033[%d;%dH" "$1" "$2"; }

# 清理并恢复终端
_cleanup() {
    _show_cursor
    tput rmcup 2>/dev/null
    stty echo 2>/dev/null
    clear
}
trap _cleanup EXIT INT TERM

# ── 读取方向键 ─────────────────────────────────────────────────────────────
_read_key() {
    local key
    IFS= read -r -s -n1 key
    if [[ "${key}" == $'\033' ]]; then
        IFS= read -r -s -n2 -t 0.1 rest
        key="${key}${rest}"
    fi
    case "${key}" in
        $'\033[A') echo "UP"    ;;
        $'\033[B') echo "DOWN"  ;;
        $'\033[C') echo "RIGHT" ;;
        $'\033[D') echo "LEFT"  ;;
        $'\033[H') echo "HOME"  ;;
        $'\n'|$'\r') echo "ENTER" ;;
        ' ')       echo "SPACE" ;;
        q|Q)       echo "QUIT"  ;;
        *)         echo "OTHER:${key}" ;;
    esac
}

# ── 绘制圆角框 ─────────────────────────────────────────────────────────────
_draw_box() {
    local row=$1 col=$2 height=$3 width=$4
    local color="${5:-${C_CYN}}"

    _goto "${row}" "${col}"
    printf "${color}╔"; printf '═%.0s' $(seq 1 $(( width - 2 ))); printf "╗${R}"

    local i
    for (( i=1; i<height-1; i++ )); do
        _goto $(( row + i )) "${col}"
        printf "${color}║${R}"
        _goto $(( row + i )) $(( col + width - 1 ))
        printf "${color}║${R}"
    done

    _goto $(( row + height - 1 )) "${col}"
    printf "${color}╚"; printf '═%.0s' $(seq 1 $(( width - 2 ))); printf "╝${R}"
}

# ── ASCII 标题 ─────────────────────────────────────────────────────────────
_draw_banner() {
    local row="${1:-2}"
    local col="${2:-10}"
    printf "${C_YEL}${BOLD}"
    _goto "${row}"   "${col}"; echo ' ████████╗███████╗██████╗ ███╗   ███╗██╗███╗   ██╗ █████╗ ██╗     '
    _goto "$(( row+1 ))" "${col}"; echo ' ╚══██╔══╝██╔════╝██╔══██╗████╗ ████║██║████╗  ██║██╔══██╗██║     '
    _goto "$(( row+2 ))" "${col}"; echo '    ██║   █████╗  ██████╔╝██╔████╔██║██║██╔██╗ ██║███████║██║     '
    _goto "$(( row+3 ))" "${col}"; echo '    ██║   ██╔══╝  ██╔══██╗██║╚██╔╝██║██║██║╚██╗██║██╔══██║██║     '
    _goto "$(( row+4 ))" "${col}"; echo '    ██║   ███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║██║  ██║███████╗'
    _goto "$(( row+5 ))" "${col}"; echo '    ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚══════╝'
    printf "${R}"
    _goto "$(( row+6 ))" "$(( col + 20 ))"
    printf "${C_CYN}${DIM}纯 Bash 终端游戏集合  v1.0${R}"
}

# ── 主菜单 ─────────────────────────────────────────────────────────────────
main_menu() {
    tput smcup 2>/dev/null
    stty -echo 2>/dev/null
    _hide_cursor

    local -a games=(
        "🐍  Snake       贪吃蛇 — 吃食物让蛇变长，别撞墙！"
        "🔢  2048        数字合并 — 合并到 2048 就赢！"
        "💣  Minesweeper 扫雷 — 找出所有地雷！"
        "❌  退出"
    )
    local -a scripts=(
        "${GAMES_DIR}/snake.sh"
        "${GAMES_DIR}/2048.sh"
        "${GAMES_DIR}/minesweeper.sh"
        "QUIT"
    )
    local -a colors=(
        "${C_GRN}"
        "${C_YEL}"
        "${C_RED}"
        "${C_DIM:-${DIM}}"
    )

    local selected=0
    local total=${#games[@]}

    while true; do
        _clear

        # 标题
        _draw_banner 2 8

        # 菜单框
        local menu_row=12
        local menu_col=25
        local menu_w=42
        local menu_h=$(( total + 4 ))

        _draw_box "${menu_row}" "${menu_col}" "${menu_h}" "${menu_w}" "${C_MAG}"

        _goto $(( menu_row + 1 )) $(( menu_col + 12 ))
        printf "${C_MAG}${BOLD}⬡  选择游戏  ⬡${R}"

        local i
        for (( i=0; i<total; i++ )); do
            _goto $(( menu_row + 3 + i )) $(( menu_col + 2 ))
            if (( i == selected )); then
                printf "${BG_HIL}${C_WHT}${BOLD}  ▶ %-36s  ${R}" "${games[$i]}"
            else
                printf "${colors[$i]}${DIM}    %-36s  ${R}" "${games[$i]}"
            fi
        done

        # 操作提示
        _goto $(( menu_row + menu_h + 2 )) $(( menu_col ))
        printf "${DIM}  ↑↓ 移动   Enter 确认   q 退出${R}"

        # 读取按键
        local key
        key="$(_read_key)"
        case "${key}" in
            UP)    (( selected = (selected - 1 + total) % total )) ;;
            DOWN)  (( selected = (selected + 1) % total )) ;;
            ENTER)
                local script="${scripts[$selected]}"
                if [[ "${script}" == "QUIT" ]]; then
                    return 0
                elif [[ -f "${script}" ]]; then
                    _show_cursor
                    tput rmcup 2>/dev/null
                    stty echo 2>/dev/null
                    bash "${script}"
                    # 游戏退出后重新进入菜单
                    tput smcup 2>/dev/null
                    stty -echo 2>/dev/null
                    _hide_cursor
                else
                    _goto $(( menu_row + menu_h + 3 )) "${menu_col}"
                    printf "${C_RED}  ✗ 游戏文件不存在: ${script}${R}"
                    sleep 1.5
                fi
                ;;
            QUIT) return 0 ;;
        esac
    done
}

main_menu
