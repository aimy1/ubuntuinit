#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — TUI 交互界面库
# =============================================================================
# 文件     : lib/ui.sh
# 说明     : 提供方向键驱动的菜单、复选列表、确认框、进度动画等 TUI 组件
#           : 纯 bash 实现，无外部依赖
# 组件列表 :
#   ui_banner()          — ASCII Art 启动横幅
#   ui_system_info()     — 系统信息面板
#   ui_menu()            — ↑↓ 方向键单选菜单
#   ui_checklist()       — ↑↓+Space 多选复选列表
#   ui_confirm()         — ←→ 方向键 Yes/No 对话框
#   ui_input()           — 文字输入框
#   ui_spinner_start/stop() — 旋转加载动画
#   ui_progress()        — 安装进度条面板
#   ui_main_menu()       — 应用主菜单（组合以上组件）
# =============================================================================

# =============================================================================
# 1. 视觉常量（颜色 + 盒子字符）
# =============================================================================

# 颜色主题
UI_C_RESET='\033[0m'
UI_C_BOLD='\033[1m'
UI_C_DIM='\033[2m'

# 主题色：电光蓝
UI_C_PRIMARY='\033[38;5;39m'
UI_C_PRIMARY_BG='\033[48;5;24m'

# 强调色：薄荷绿
UI_C_ACCENT='\033[38;5;82m'

# 标题色：亮白
UI_C_TITLE='\033[38;5;255m'

# 高亮行背景（深蓝灰）
UI_C_SEL_BG='\033[48;5;236m'
UI_C_SEL_FG='\033[38;5;51m'

# 次要文字（灰）
UI_C_MUTED='\033[38;5;244m'

# 成功/警告/错误
UI_C_OK='\033[38;5;82m'
UI_C_WARN='\033[38;5;220m'
UI_C_ERR='\033[38;5;197m'

# 边框色（深蓝紫）
UI_C_BORDER='\033[38;5;63m'

# ── 盒子绘图字符（Unicode）────────────────────────────────────────
UI_BOX_TL='╭'; UI_BOX_TR='╮'
UI_BOX_BL='╰'; UI_BOX_BR='╯'
UI_BOX_H='─';  UI_BOX_V='│'
UI_BOX_ML='├'; UI_BOX_MR='┤'

# ── 图标 ─────────────────────────────────────────────────────────
UI_ICON_CURSOR='❯'
UI_ICON_CHECK='●'
UI_ICON_UNCHECK='○'
UI_ICON_YES='◉'
UI_ICON_NO='○'

# ── 菜单固定宽度 ─────────────────────────────────────────────────
UI_MENU_WIDTH=58   # 外边框总宽（含两侧 │）
UI_INNER_W=54      # 内容宽度（UI_MENU_WIDTH - 4 for "│ ... │"）

# =============================================================================
# 2. 终端工具函数
# =============================================================================

# 获取终端列数
_ui_term_cols() {
    tput cols 2>/dev/null || echo 80
}

# 获取终端行数
_ui_term_rows() {
    tput lines 2>/dev/null || echo 24
}

# 隐藏光标
_ui_cursor_hide() { printf '\033[?25l'; }

# 显示光标
_ui_cursor_show() { printf '\033[?25h'; }

# 清屏
_ui_clear() { printf '\033[2J\033[H'; }

# 向上移动 N 行并回到行首
_ui_cursor_up() {
    local n="${1:-1}"
    printf "\033[%dA\r" "${n}"
}

# 清除从光标到行尾
_ui_erase_line() { printf '\033[K'; }

# =============================================================================
# 3. 按键读取（核心：解析 ANSI 转义序列）
# =============================================================================

# 读取一次按键，返回标准化名称：
#   UP DOWN LEFT RIGHT ENTER SPACE TAB BACKSPACE QUIT ESC
#   SELECT_ALL SELECT_NONE TOP BOTTOM
#   KEY_<char>（其他可打印字符）
_ui_read_key() {
    local key seq1 seq2

    # 读取第一个字节（阻塞）
    IFS= read -rsn1 key 2>/dev/null || key=''

    if [[ "${key}" == $'\x1b' ]]; then
        # 读取后续字节（0.05s 超时区分单独 ESC）
        IFS= read -rsn1 -t 0.05 seq1 2>/dev/null || seq1=''

        if [[ "${seq1}" == '[' ]]; then
            IFS= read -rsn1 -t 0.05 seq2 2>/dev/null || seq2=''

            case "${seq2}" in
                'A') echo 'UP'    ; return ;;
                'B') echo 'DOWN'  ; return ;;
                'C') echo 'RIGHT' ; return ;;
                'D') echo 'LEFT'  ; return ;;
                '5') IFS= read -rsn1 -t 0.05 _ 2>/dev/null; echo 'PGUP'; return ;;
                '6') IFS= read -rsn1 -t 0.05 _ 2>/dev/null; echo 'PGDN'; return ;;
                'H') echo 'HOME'  ; return ;;
                'F') echo 'END'   ; return ;;
            esac
        fi
        echo 'ESC'; return
    fi

    # 普通按键映射
    case "${key}" in
        ''|$'\n'|$'\r') echo 'ENTER'       ;;
        ' ')             echo 'SPACE'       ;;
        $'\t')           echo 'TAB'         ;;
        $'\x7f')         echo 'BACKSPACE'   ;;
        'q'|'Q')         echo 'QUIT'        ;;
        'k')             echo 'UP'          ;;
        'j')             echo 'DOWN'        ;;
        'h')             echo 'LEFT'        ;;
        'l')             echo 'RIGHT'       ;;
        'a'|'A')         echo 'SELECT_ALL'  ;;
        'n'|'N')         echo 'SELECT_NONE' ;;
        'g')             echo 'TOP'         ;;
        'G')             echo 'BOTTOM'      ;;
        *)               echo "KEY_${key}"  ;;
    esac
}

# =============================================================================
# 4. 基础绘图工具
# =============================================================================

# 绘制水平分隔线（完整边框行）
# 参数: $1=左字符 $2=填充字符 $3=右字符 $4=宽度（含两端）
_ui_hline() {
    local l="$1" f="$2" r="$3" w="$4"
    local mid
    mid="$(printf "${f}%.0s" $(seq 1 $(( w - 2 ))))"
    printf "${UI_C_BORDER}%s%s%s${UI_C_RESET}\n" "${l}" "${mid}" "${r}"
}

# 获取字符串在终端的实际显示宽度（中英文+表情自适应）
_ui_string_width() {
    local str="$1"
    # 移除 ANSI 颜色转义码
    local clean
    clean="$(echo -e "${str}" | sed 's/\x1b\[[0-9;]*m//g' 2>/dev/null)"
    local w
    w="$(echo -n "${clean}" | wc -L 2>/dev/null)"
    if [[ "${w}" =~ ^[0-9]+$ ]]; then
        echo "${w}"
    else
        # 备用方案：将非 ASCII 字符替换为 2 个点以估算显示宽度
        echo -n "${clean}" | sed 's/[^\x00-\x7f]/../g' 2>/dev/null | wc -c
    fi
}

# 绘制内容行（带边框，支持中英文自适应对齐）
# 参数: $1=内容（已含颜色）$2=内容可见长度（可选，默认自动计算）
_ui_row() {
    local content="$1"
    local visible_len="${2:-}"
    if [[ -z "${visible_len}" ]]; then
        visible_len="$(_ui_string_width "${content}")"
    fi
    local pad=$(( UI_INNER_W - visible_len ))
    (( pad < 0 )) && pad=0
    printf "${UI_C_BORDER}│${UI_C_RESET} %s%*s ${UI_C_BORDER}│${UI_C_RESET}\n" \
        "${content}" "${pad}" ''
}

# 绘制空内容行
_ui_empty_row() {
    printf "${UI_C_BORDER}│${UI_C_RESET}%*s${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 2 ))" ''
}

# 居中文本（自适应多字节字符宽度）
# 参数: $1=文本（含或不含颜色） $2=宽度
_ui_center() {
    local text="$1"
    local width="${2:-${UI_INNER_W}}"
    local len
    len="$(_ui_string_width "${text}")"
    local lpad=$(( (width - len) / 2 ))
    local rpad=$(( width - len - lpad ))
    (( lpad < 0 )) && lpad=0
    (( rpad < 0 )) && rpad=0
    printf "%*s%s%*s" "${lpad}" '' "${text}" "${rpad}" ''
}

# =============================================================================
# 5. 启动横幅
# =============================================================================

# 打印 ASCII Art 横幅
ui_banner() {
    local ver="${SCRIPT_VERSION:-1.0.0}"
    local cols
    cols="$(_ui_term_cols)"

    printf '\n'
    printf "${UI_C_PRIMARY}${UI_C_BOLD}"
    cat <<'LOGO'
  ██╗   ██╗██████╗ ██╗   ██╗███╗  ██╗████████╗██╗   ██╗
  ██║   ██║██╔══██╗██║   ██║████╗ ██║╚══██╔══╝██║   ██║
  ██║   ██║██████╔╝██║   ██║██╔██╗██║   ██║   ██║   ██║
  ██║   ██║██╔══██╗██║   ██║██║╚████║   ██║   ██║   ██║
  ╚██████╔╝╚█████╔╝╚██████╔╝██║ ╚███║   ██║   ╚██████╔╝
   ╚═════╝  ╚════╝  ╚═════╝ ╚═╝  ╚══╝   ╚═╝    ╚═════╝
LOGO
    printf "${UI_C_RESET}\n"

    printf "  ${UI_C_MUTED}%s${UI_C_RESET}\n" \
        "Ubuntu Server 一键初始化框架  ·  v${ver}"
    printf "  ${UI_C_MUTED}%s${UI_C_RESET}\n" \
        "支持: Ubuntu 20.04 / 22.04 / 24.04 / 26.04  ·  amd64 / arm64"
    printf '\n'
    printf "  ${UI_C_MUTED}世界在滚动更新，Ubuntu 在长期支持${UI_C_RESET}\n"
    printf "  ${UI_C_DIM}LTS = Long Time Stagnation${UI_C_RESET}\n"
    printf "  ${UI_C_DIM}Made with ♥ by aisaniya${UI_C_RESET}\n"
    printf '\n'

    # 渐变分隔线
    printf "  ${UI_C_PRIMARY}"
    printf '─%.0s' $(seq 1 54)
    printf "${UI_C_RESET}\n\n"
}

# =============================================================================
# 6. 系统信息面板
# =============================================================================

# 打印一行系统信息（左标签 + 右数值）
_ui_info_row() {
    local label="$1"
    local value="$2"
    local label_len=16
    printf "  ${UI_C_MUTED}%-*s${UI_C_RESET}  ${UI_C_ACCENT}%s${UI_C_RESET}\n" \
        "${label_len}" "${label}" "${value}"
}

# 显示系统信息面板（在主菜单上方展示）
ui_system_info() {
    local os_name os_version kernel arch hostname
    local cpu_model mem_total mem_free ip_addr

    os_name="$(. /etc/os-release 2>/dev/null && echo "${NAME:-Unknown}" || echo 'Unknown')"
    os_version="$(. /etc/os-release 2>/dev/null && echo "${VERSION_ID:-?}" || echo '?')"
    kernel="$(uname -r 2>/dev/null || echo 'Unknown')"
    arch="$(uname -m 2>/dev/null || echo 'Unknown')"
    hostname="$(hostname -s 2>/dev/null || echo 'Unknown')"
    cpu_model="$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs || echo 'Unknown')"
    mem_total="$(free -h 2>/dev/null | awk '/^Mem:/{print $2}' || echo '?')"
    mem_free="$(free -h 2>/dev/null | awk '/^Mem:/{print $7}' || echo '?')"
    ip_addr="$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'Unknown')"

    printf "  ${UI_C_BORDER}╭──────────────────────────────────────────────────────╮${UI_C_RESET}\n"
    printf "  ${UI_C_BORDER}│${UI_C_RESET} ${UI_C_PRIMARY}${UI_C_BOLD}  系统信息${UI_C_RESET}%47s${UI_C_BORDER}│${UI_C_RESET}\n" ''
    printf "  ${UI_C_BORDER}├──────────────────────────────────────────────────────┤${UI_C_RESET}\n"
    _ui_info_row "  操作系统" "${os_name} ${os_version}"
    _ui_info_row "  内核"     "${kernel}"
    _ui_info_row "  架构"     "${arch}"
    _ui_info_row "  主机名"   "${hostname}"
    _ui_info_row "  CPU"      "${cpu_model:0:38}"
    _ui_info_row "  内存"     "${mem_free} 可用 / ${mem_total} 总计"
    _ui_info_row "  IP 地址"  "${ip_addr}"
    _ui_info_row "  框架作者" "aisaniya"
    printf "  ${UI_C_BORDER}╰──────────────────────────────────────────────────────╯${UI_C_RESET}\n\n"
}

# =============================================================================
# 7. 单选菜单（↑↓ 方向键）
# =============================================================================

# 内部：渲染所有菜单行（仅行，不含外框，支持中英文自适应对齐）
# 参数: $1=当前选中索引  $2=items数组名（nameref）
_ui_render_menu_items() {
    local sel="$1"
    local -n __items="$2"
    local i=0

    for entry in "${__items[@]}"; do
        # entry 格式: "value:图标 显示标签" 或 "value:显示标签"
        local label="${entry#*:}"
        local label_len
        label_len="$(_ui_string_width "${label}")"

        if (( i == sel )); then
            # 高亮行：光标 (❯) 占 2 字符，左侧 1 空格，右侧 2 空格
            local pad=$(( UI_MENU_WIDTH - 7 - label_len ))
            (( pad < 0 )) && pad=0
            printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_SEL_BG} ${UI_C_SEL_FG}${UI_C_BOLD}${UI_ICON_CURSOR} %s%*s${UI_C_RESET}${UI_C_SEL_BG}  ${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
                "${label}" "${pad}" ''
        else
            # 普通行：左侧 5 空格缩进，右侧 2 空格
            local pad=$(( UI_MENU_WIDTH - 8 - label_len ))
            (( pad < 0 )) && pad=0
            printf "${UI_C_BORDER}│${UI_C_RESET}   ${UI_C_MUTED}  %s%*s${UI_C_RESET}  ${UI_C_BORDER}│${UI_C_RESET}\n" \
                "${label}" "${pad}" ''
        fi
        (( i++ ))
    done
}

# 内部：完整绘制单选菜单（框 + 标题 + 行 + 提示）
# 参数: $1=标题  $2=当前选中索引  $3=items数组名
_ui_draw_menu() {
    local title="$1"
    local sel="$2"
    local arr_name="$3"
    local -n __draw_items="${arr_name}"

    _ui_hline "${UI_BOX_TL}" "${UI_BOX_H}" "${UI_BOX_TR}" "${UI_MENU_WIDTH}"

    # 标题行
    local centered_title
    centered_title="$(_ui_center "${title}" "$(( UI_MENU_WIDTH - 4 ))")"
    printf "${UI_C_BORDER}│${UI_C_RESET} ${UI_C_TITLE}${UI_C_BOLD}%s${UI_C_RESET} ${UI_C_BORDER}│${UI_C_RESET}\n" \
        "${centered_title}"

    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"
    _ui_empty_row
    _ui_render_menu_items "${sel}" "${arr_name}"
    _ui_empty_row
    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"

        # 操作提示行（增加 Home/End/PgUp/PgDn 提示）
        local hint="  ↑/k 上移  ↓/j 下移  g 首行  G 末行  Enter 确认  q 退出"
        printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_MUTED}%-*s${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
            "$(( UI_MENU_WIDTH - 2 ))" "${hint}" >&2

        _ui_hline "${UI_BOX_BL}" "${UI_BOX_H}" "${UI_BOX_BR}" "${UI_MENU_WIDTH}"
}

# 公共 API：方向键单选菜单
# 参数: $1=标题  $2..=条目（格式: "value:label" 或 "label"）
# 输出: 选中条目的 value 部分（冒号前），选中后自动换行
# 返回: 0=确认  1=取消/退出
ui_menu() {
    local title="$1"
    shift
    local -a items=("$@")
    local total="${#items[@]}"
    local sel=0

    # 计算菜单总行数（用于重绘时向上移动光标）
    # top_border + title + mid_border + empty + items + empty + mid_border + hint + bottom_border
    local total_lines=$(( total + 8 ))

    _ui_cursor_hide

    # 注册清理：函数返回时恢复光标
    # shellcheck disable=SC2064
    trap "_ui_cursor_show" RETURN

    # 首次绘制
    _ui_draw_menu "${title}" "${sel}" items

    while true; do
        local key
        key="$(_ui_read_key)"
        prev_sel="${sel}"

        case "${key}" in
            UP|PGUP)   (( sel > 0 ))          && (( sel-- )) ;;
            DOWN|PGDN) (( sel < total - 1 ))   && (( sel++ )) ;;
            TOP|HOME)  sel=0 ;;
            BOTTOM|END) sel=$(( total - 1 )) ;;
            ENTER)
                _ui_cursor_show
                # 返回 value（冒号前）或整个字符串
                local chosen="${items[${sel}]}"
                echo "${chosen%%:*}"
                return 0
                ;;
            QUIT|ESC|BACKSPACE)
                _ui_cursor_show
                return 1
                ;;
        esac

        # 选中变化时使用增量重绘
        if (( sel != prev_sel )); then
            _ui_cursor_up "${total_lines}"
            _ui_draw_menu "${title}" "${sel}" items
        fi
    done
}

# =============================================================================
# 8. 多选复选列表（↑↓+Space）
# =============================================================================

# 内部：绘制复选列表中的单行（支持中英文+表情自适应对齐）
# 参数: $1=索引 $2=是否当前行(0/1) $3=items数组名 $4=checked数组名
_ui_draw_checklist_row() {
    local idx="$1"
    local is_current="$2"
    local items_name="$3"
    local chk_name="$4"
    local -n __row_items="${items_name}"
    local -n __row_chk="${chk_name}"

    local entry="${__row_items[$idx]}"
    local value="${entry%%:*}"
    local label="${entry#*:}"
    local num_checked="${__row_chk[$idx]:-0}"

    local check_icon status_icon
    if (( num_checked )); then
        check_icon="${UI_C_ACCENT}${UI_ICON_CHECK}${UI_C_RESET}"
    else
        check_icon="${UI_C_MUTED}${UI_ICON_UNCHECK}${UI_C_RESET}"
    fi

    if _ui_check_module_installed "${value}"; then
        status_icon="${UI_C_INSTALLED}✓${UI_C_RESET}"
    else
        status_icon="${UI_C_NOT_INSTALLED}○${UI_C_RESET}"
    fi

    local label_len
    label_len="$(_ui_string_width "${label}")"
    # 图标和边框固定占位14个字符
    local pad=$(( UI_MENU_WIDTH - 14 - label_len ))
    (( pad < 0 )) && pad=0

    if (( is_current )); then
        printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_SEL_BG} ${UI_C_SEL_FG}${UI_C_BOLD}${UI_ICON_CURSOR}${UI_C_RESET}${UI_C_SEL_BG} %b ${UI_C_SEL_FG}%s%*s ${UI_C_RESET}${UI_C_SEL_BG}%b${UI_C_RESET}${UI_C_SEL_BG} ${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
            "${check_icon}" "${label}" "${pad}" '' "${status_icon}" >&2
    else
        printf "${UI_C_BORDER}│${UI_C_RESET}    %b ${UI_C_MUTED}%s%*s ${UI_C_RESET}%b  ${UI_C_BORDER}│${UI_C_RESET}\n" \
            "${check_icon}" "${label}" "${pad}" '' "${status_icon}" >&2
    fi
}

# 内部：渲染所有复选行
# 参数: $1=当前光标行  $2=checked数组名  $3=items数组名
_ui_render_checklist_items() {
    local cur="$1"
    local chk_name="$2"
    local items_name="$3"
    local -n __cl_items="${items_name}"
    local total="${#__cl_items[@]}"
    local i=0

    for (( i=0; i<total; i++ )); do
        local is_current=0
        (( i == cur )) && is_current=1
        _ui_draw_checklist_row "${i}" "${is_current}" "${items_name}" "${chk_name}"
    done
}

# 内部：完整绘制复选列表框
# 参数: $1=标题 $2=当前光标 $3=checked数组名 $4=items数组名 $5=上次光标（可选，-1表示全量重绘）$6=是否仅重绘当前行
_ui_draw_checklist() {
    local title="$1"
    local cur="$2"
    local chk_name="$3"
    local items_name="$4"
    local prev_cur="${5:--1}"
    local only_rows="${6:-false}"   # true=仅重绘变化的行，false=全量重绘
    local -n __dcl_items="${items_name}"
    local total="${#__dcl_items[@]}"
    # 底部 footer 占用的行数（空行+分隔线+图例+提示+底部边框）
    local footer_lines=5
    # header 占用的行数（上边框+标题+分隔线+空行）
    local header_lines=4

    # 增量重绘模式：只更新变化的行
    if (( prev_cur >= 0 )) && [[ "${only_rows}" == "true" ]]; then
        local bottom_offset

        # 上一个选中行 → 切换到非选中状态
        if (( prev_cur < total )); then
            bottom_offset=$(( header_lines + (total - 1 - prev_cur) + footer_lines ))
            printf "\033[%dA" "${bottom_offset}" >&2
            printf "\r" >&2
            _ui_draw_checklist_row "${prev_cur}" 0 "${items_name}" "${chk_name}"
        fi

        # 当前选中行 → 切换到选中状态
        if (( cur < total )); then
            bottom_offset=$(( header_lines + (total - 1 - cur) + footer_lines ))
            printf "\033[%dA" "${bottom_offset}" >&2
            printf "\r" >&2
            _ui_draw_checklist_row "${cur}" 1 "${items_name}" "${chk_name}"
        fi

        # 返回到菜单底部
        printf "\033[%dB" "$(( header_lines + (total - 1 - cur) + footer_lines - 1 ))" >&2
        return
    fi

    # 全量重绘模式
    _ui_hline "${UI_BOX_TL}" "${UI_BOX_H}" "${UI_BOX_TR}" "${UI_MENU_WIDTH}"

    local centered_title
    centered_title="$(_ui_center "${title}" "$(( UI_MENU_WIDTH - 4 ))")"
    printf "${UI_C_BORDER}│${UI_C_RESET} ${UI_C_TITLE}${UI_C_BOLD}%s${UI_C_RESET} ${UI_C_BORDER}│${UI_C_RESET}\n" \
        "${centered_title}" >&2

    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"
    _ui_empty_row
    _ui_render_checklist_items "${cur}" "${chk_name}" "${items_name}"
    _ui_empty_row
    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"

    # 状态图例
    local legend="  ${UI_C_INSTALLED}✓ 已安装${UI_C_RESET}  ${UI_C_NOT_INSTALLED}○ 未安装${UI_C_RESET}  ${UI_C_ACCENT}● 已选中${UI_C_RESET}"
    printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_MUTED}%-*s${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 2 ))" "${legend}" >&2

    # 操作提示（含 Tab=选择, q/◄=返回）
    local hint="  ↑↓/jk 移动  Space/Tab 选择  A 全选  N 清空  Enter 确认  q/◄ 返回"
    printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_MUTED}%-*s${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 2 ))" "${hint}" >&2

    _ui_hline "${UI_BOX_BL}" "${UI_BOX_H}" "${UI_BOX_BR}" "${UI_MENU_WIDTH}"
}

# 公共 API：多选复选列表。支持增量重绘
# 参数: $1=标题  $2..=条目（格式: "value:label"）
# 输出: 选中条目 value 的逗号分隔列表
# 返回: 0=确认  1=取消
ui_checklist() {
    local title="$1"
    shift
    local -a items=("$@")
    local total="${#items[@]}"
    local cur=0
    local prev_cur=-1
    local -a checked=()
    local i

    for (( i=0; i<total; i++ )); do checked[$i]=0; done

    _ui_cursor_hide
    # shellcheck disable=SC2064
    trap "_ui_cursor_show" RETURN

    # 首次全量绘制
    _ui_draw_checklist "${title}" "${cur}" checked items

    while true; do
        local key
        key="$(_ui_read_key)"
        prev_cur="${cur}"
        local need_rows=false   # 仅重绘变化的行
        local full_redraw=false # 全量重绘

        case "${key}" in
            UP)    (( cur > 0 ))          && (( cur-- )) ;;
            DOWN)  (( cur < total - 1 ))  && (( cur++ )) ;;
            TOP)   cur=0 ;;
            BOTTOM) cur=$(( total - 1 )) ;;
            SPACE|TAB)
                checked[$cur]=$(( 1 - checked[$cur] ))
                need_rows=true
                ;;
            SELECT_ALL)
                for (( i=0; i<total; i++ )); do checked[$i]=1; done
                full_redraw=true
                ;;
            SELECT_NONE)
                for (( i=0; i<total; i++ )); do checked[$i]=0; done
                full_redraw=true
                ;;
            ENTER)
                _ui_cursor_show
                local result=()
                for (( i=0; i<total; i++ )); do
                    if (( checked[i] )); then
                        result+=("${items[$i]%%:*}")
                    fi
                done
                local IFS=','
                echo "${result[*]}"
                return 0
                ;;
            QUIT|ESC|BACKSPACE)
                _ui_cursor_show
                return 1
                ;;
        esac

        if [[ "${full_redraw}" == "true" ]]; then
            # 全选/全不选：用光标向上跳后全量重绘
            local jump=$(( total + 7 ))
            printf "\033[%dA" "${jump}" >&2
            _ui_draw_checklist "${title}" "${cur}" checked items
        elif (( cur != prev_cur )) || [[ "${need_rows}" == "true" ]]; then
            # 移动或单项切换：仅重绘变化的行
            _ui_draw_checklist "${title}" "${cur}" checked items "${prev_cur}" "true"
        fi
    done
}

# =============================================================================
# 9. Yes/No 确认框（←→ 方向键）
# =============================================================================

# 内部：绘制确认框
_ui_draw_confirm() {
    local message="$1"
    local sel="$2"    # 0=Yes  1=No

    _ui_hline "${UI_BOX_TL}" "${UI_BOX_H}" "${UI_BOX_TR}" "${UI_MENU_WIDTH}"
    _ui_empty_row

    # 消息行（可多行）
    printf "${UI_C_BORDER}│${UI_C_RESET}  ${UI_C_WHITE}%-*s${UI_C_RESET}  ${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 6 ))" "${message}"

    _ui_empty_row
    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"
    _ui_empty_row

    # Yes / No 按钮
    local yes_btn no_btn
    if (( sel == 0 )); then
        yes_btn="${UI_C_PRIMARY_BG}${UI_C_BOLD}  ${UI_ICON_YES}  是  ${UI_C_RESET}"
        no_btn="${UI_C_MUTED}  ${UI_ICON_NO}  否  ${UI_C_RESET}"
    else
        yes_btn="${UI_C_MUTED}  ${UI_ICON_NO}  是  ${UI_C_RESET}"
        no_btn="${UI_C_ERR}${UI_C_PRIMARY_BG}${UI_C_BOLD}  ${UI_ICON_YES}  否  ${UI_C_RESET}"
    fi

    printf "${UI_C_BORDER}│${UI_C_RESET}          %s      %s%*s${UI_C_BORDER}│${UI_C_RESET}\n" \
        "${yes_btn}" "${no_btn}" 12 ''

    _ui_empty_row
    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"

    local hint="  ←/→ 切换  Enter 确认"
    printf "${UI_C_BORDER}│${UI_C_RESET}${UI_C_MUTED}%-*s${UI_C_RESET}${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 2 ))" "${hint}"
    _ui_hline "${UI_BOX_BL}" "${UI_BOX_H}" "${UI_BOX_BR}" "${UI_MENU_WIDTH}"
}

# 公共 API：确认框
# 参数: $1=提示消息  $2=默认值（"yes"|"no"，默认 "yes"）
# 返回: 0=Yes  1=No
ui_confirm() {
    local message="$1"
    local default="${2:-yes}"
    local sel=0
    [[ "${default}" == "no" ]] && sel=1

    local total_lines=10

    _ui_cursor_hide
    # shellcheck disable=SC2064
    trap "_ui_cursor_show" RETURN

    _ui_draw_confirm "${message}" "${sel}"

    while true; do
        local key
        key="$(_ui_read_key)"

        case "${key}" in
            LEFT|RIGHT|TAB)
                sel=$(( 1 - sel ))
                _ui_cursor_up "${total_lines}"
                _ui_draw_confirm "${message}" "${sel}"
                ;;
            ENTER)
                _ui_cursor_show
                return "${sel}"
                ;;
            QUIT|ESC)
                _ui_cursor_show
                return 1
                ;;
        esac
    done
}

# =============================================================================
# 10. 文本输入框
# =============================================================================

# 公共 API：文本输入框
# 参数: $1=提示文字  $2=默认值（可空）
# 输出: 用户输入的文本
# 返回: 0=确认  1=取消
ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local input="${default}"

    _ui_cursor_show
    printf '\n'
    _ui_hline "${UI_BOX_TL}" "${UI_BOX_H}" "${UI_BOX_TR}" "${UI_MENU_WIDTH}"
    printf "${UI_C_BORDER}│${UI_C_RESET}  ${UI_C_WHITE}${UI_C_BOLD}%-*s${UI_C_RESET}  ${UI_C_BORDER}│${UI_C_RESET}\n" \
        "$(( UI_MENU_WIDTH - 6 ))" "${prompt}"
    _ui_hline "${UI_BOX_ML}" "${UI_BOX_H}" "${UI_BOX_MR}" "${UI_MENU_WIDTH}"

    printf "${UI_C_BORDER}│${UI_C_RESET}  ${UI_C_PRIMARY}❯ ${UI_C_RESET}"
    # 读取一行（支持退格）
    IFS= read -re -i "${default}" -p "" input 2>/dev/null || {
        IFS= read -re input
    }

    _ui_hline "${UI_BOX_BL}" "${UI_BOX_H}" "${UI_BOX_BR}" "${UI_MENU_WIDTH}"

    echo "${input}"
    return 0
}

# =============================================================================
# 11. 旋转加载动画（后台 spinner）
# =============================================================================

# 全局 spinner PID
_UI_SPINNER_PID=""

# 启动 spinner（后台进程）
# 参数: $1=提示文字
ui_spinner_start() {
    local label="${1:-处理中}"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local colors=(
        '\033[38;5;51m'
        '\033[38;5;45m'
        '\033[38;5;39m'
        '\033[38;5;33m'
        '\033[38;5;27m'
    )

    _ui_cursor_hide

    (
        local i=0
        local ci=0
        while true; do
            local frame="${frames[$i]}"
            local color="${colors[$ci]}"
            printf "\r  ${color}${UI_C_BOLD}%s${UI_C_RESET}  %s  " "${frame}" "${label}"
            (( i = (i + 1) % ${#frames[@]} ))
            (( ci = (ci + 1) % ${#colors[@]} ))
            sleep 0.08
        done
    ) &

    _UI_SPINNER_PID=$!
    disown "${_UI_SPINNER_PID}" 2>/dev/null || true
}

# 停止 spinner
# 参数: $1=最终消息  $2=状态（ok|err|warn，默认 ok）
ui_spinner_stop() {
    local final_msg="${1:-完成}"
    local status="${2:-ok}"

    if [[ -n "${_UI_SPINNER_PID}" ]]; then
        kill "${_UI_SPINNER_PID}" 2>/dev/null || true
        wait "${_UI_SPINNER_PID}" 2>/dev/null || true
        _UI_SPINNER_PID=""
    fi

    _ui_erase_line

    local icon color
    case "${status}" in
        ok)   icon="${UI_ICON_SUCCESS:-✓}"; color="${UI_C_OK}"   ;;
        err)  icon="${UI_ICON_ERROR:-✗}";   color="${UI_C_ERR}"  ;;
        warn) icon="${UI_ICON_WARNING:-⚠}"; color="${UI_C_WARN}" ;;
        *)    icon="·";                     color="${UI_C_MUTED}" ;;
    esac

    printf "\r  ${color}${UI_C_BOLD}%s${UI_C_RESET}  %s\n" "${icon}" "${final_msg}"
    _ui_cursor_show
}

# =============================================================================
# 12. 安装进度面板
# =============================================================================

# 渲染模块安装进度面板（供 install.sh 在执行模块时调用）
# 参数: $1=当前模块名  $2=当前序号  $3=总数  $4=状态消息
ui_progress() {
    local module="$1"
    local current="$2"
    local total="$3"
    local msg="${4:-}"

    local pct=$(( current * 100 / total ))
    local bar_width=44
    local filled=$(( current * bar_width / total ))
    local empty=$(( bar_width - filled ))

    local bar="${UI_C_PRIMARY}$(printf '█%.0s' $(seq 1 "${filled}"))${UI_C_MUTED}$(printf '░%.0s' $(seq 1 "${empty}"))${UI_C_RESET}"

    printf "\r  [%s] ${UI_C_BOLD}%3d%%${UI_C_RESET}  ${UI_C_MUTED}%s${UI_C_RESET}  %s" \
        "${bar}" "${pct}" "${module}" "${msg}"

    (( current >= total )) && printf '\n'
}

# =============================================================================
# 13. 应用主菜单
# =============================================================================

# 主菜单各分类与对应模块别名
declare -A _UI_CATEGORY_MODULES=(
    ["system"]="system mirror"
    ["security"]="ssh user security"
    ["docker"]="docker"
    ["dev"]="python node java go rust"
    ["database"]="redis mariadb mysql postgresql mongodb"
    ["web"]="nginx apache caddy openresty"
    ["monitor"]="netdata node_exporter grafana"
    ["tools"]="nettools optimize shell log_mgmt directories"
)

# 所有模块（用于自定义选择）
declare -a _UI_ALL_MODULES=(
    "system:🖥  APT 更新 & 系统基础"
    "mirror:🔄  更换软件源（阿里云/腾讯云）"
    "ssh:🔑  SSH 安全配置"
    "user:👤  创建管理员用户"
    "security:🔒  UFW + Fail2ban + 安全加固"
    "nettools:🌐  网络工具包"
    "optimize:⚡  BBR + 系统性能优化"
    "docker:🐳  Docker CE + Compose"
    "python:🐍  Python 环境"
    "node:🟢  Node.js 环境"
    "java:☕  Java 环境（OpenJDK）"
    "go:🔵  Go 环境"
    "rust:🦀  Rust 环境"
    "redis:🔴  Redis"
    "mariadb:🐬  MariaDB"
    "mysql:🐬  MySQL"
    "postgresql:🐘  PostgreSQL"
    "mongodb:🍃  MongoDB"
    "nginx:🌊  Nginx"
    "apache:🪶  Apache"
    "caddy:⚙  Caddy"
    "openresty:🚀  OpenResty"
    "netdata:📊  Netdata 监控"
    "node_exporter:📈  Prometheus Node Exporter"
    "grafana:📉  Grafana Agent"
    "shell:💻  Shell 美化（zsh/starship）"
    "log_mgmt:📋  日志管理（journald/logrotate）"
    "directories:📁  创建标准目录"
)

# 分类菜单条目
declare -a _UI_MAIN_MENU_ITEMS=(
    "full:⚡  全量安装（推荐首次使用）"
    "system_cat:🖥  系统基础配置"
    "security_cat:🔒  安全加固"
    "docker_cat:🐳  Docker 环境"
    "dev_cat:🛠  开发工具"
    "db_cat:🗄  数据库服务"
    "web_cat:🌐  Web 服务器"
    "monitor_cat:📊  监控系统"
    "custom:🎛  自定义选择模块"
    "games:🎮  终端娱乐小游戏"
    "quit:❌  退出"
)

# 将分类模块别名展开为复选列表条目
# 使用 nameref 输出到数组，避免 echo 拱号导致的带空格元素拆分
# 参数: $1=分类键  $2=输出数组名
_ui_category_to_checklist() {
    local category="$1"
    local -n _result_arr="$2"
    local -a module_aliases
    # shellcheck disable=SC2206
    module_aliases=( ${_UI_CATEGORY_MODULES["${category}"]:-} )

    _result_arr=()
    local alias
    for alias in "${module_aliases[@]}"; do
        local entry
        for entry in "${_UI_ALL_MODULES[@]}"; do
            if [[ "${entry%%:*}" == "${alias}" ]]; then
                _result_arr+=("${entry}")
                break
            fi
        done
    done
}

# 公共 API：应用主菜单入口
# 输出: 逗号分隔的选中模块别名列表
# 返回: 0=有选中  1=用户退出
ui_main_menu() {
    while true; do
        _ui_clear
        ui_banner
        ui_system_info

        local choice
        if ! choice="$(ui_menu '  主菜单  ' "${_UI_MAIN_MENU_ITEMS[@]}")"; then
            return 1
        fi

        case "${choice}" in
            full)
                # 全量：返回除 preflight 外的所有模块
                local all_vals=()
                for entry in "${_UI_ALL_MODULES[@]}"; do
                    all_vals+=("${entry%%:*}")
                done
                local IFS=','
                echo "${all_vals[*]}"
                return 0
                ;;

            games)
                local launcher="${SCRIPT_DIR}/games/launcher.sh"
                if [[ -f "${launcher}" ]]; then
                    # 临时恢复终端的键盘回显和光标，保证小游戏可正常读取输入
                    stty echo 2>/dev/null || true
                    printf '\033[?25h' >&2
                    bash "${launcher}"
                    # 重新回归 TUI 的隐藏光标和禁用键盘回显状态
                    stty -echo 2>/dev/null || true
                    printf '\033[?25l' >&2
                else
                    ui_confirm "未找到终端游戏启动器 (${launcher})" "yes" >/dev/null
                fi
                continue
                ;;

            quit)
                return 1
                ;;

            custom)
                _ui_clear
                ui_banner
                local selected_mods
                if selected_mods="$(ui_checklist '  选择要安装的模块  ' "${_UI_ALL_MODULES[@]}")"; then
                    if [[ -n "${selected_mods}" ]]; then
                        echo "${selected_mods}"
                        return 0
                    else
                        # 未选任何模块，提示后回到主菜单
                        ui_confirm "未选择任何模块，返回主菜单？" "yes" >/dev/null
                        continue
                    fi
                fi
                continue
                ;;

            *_cat)
                # 分类快捷入口
                local cat_key="${choice%_cat}"
                local -a cat_items=()
                # 使用 nameref 输出，避免带空格标签块分裂
                _ui_category_to_checklist "${cat_key}" cat_items

                if [[ "${#cat_items[@]}" -eq 0 ]]; then
                    continue
                fi

                _ui_clear
                ui_banner

                local cat_title
                case "${cat_key}" in
                    system)   cat_title='  系统基础配置  ' ;;
                    security) cat_title='  安全加固模块  ' ;;
                    docker)   cat_title='  Docker 环境   ' ;;
                    dev)      cat_title='  开发工具       ' ;;
                    database) cat_title='  数据库服务     ' ;;
                    web)      cat_title='  Web 服务器     ' ;;
                    monitor)  cat_title='  监控系统       ' ;;
                    tools)    cat_title='  系统工具       ' ;;
                    *)        cat_title="  ${cat_key}    " ;;
                esac

                local selected_mods
                if selected_mods="$(ui_checklist "${cat_title}" "${cat_items[@]}")"; then
                    if [[ -n "${selected_mods}" ]]; then
                        echo "${selected_mods}"
                        return 0
                    fi
                fi
                continue
                ;;
        esac
    done
}
