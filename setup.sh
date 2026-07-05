#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 命令安装脚本
# =============================================================================
# 用法: sudo bash setup.sh [--uninstall] [--games]
# 效果: 安装后可在终端直接输入 ubinit 启动
# =============================================================================

set -euo pipefail

# ── 颜色 ───────────────────────────────────────────────────────────────────
R='\033[0m'; BOLD='\033[1m'
C_GRN='\033[38;5;46m';  C_RED='\033[38;5;196m'
C_YEL='\033[38;5;226m'; C_CYN='\033[38;5;51m'
C_WHT='\033[38;5;255m'; C_MAG='\033[38;5;201m'

log_ok()   { echo -e "  ${C_GRN}✓${R} $*"; }
log_err()  { echo -e "  ${C_RED}✗${R} $*" >&2; }
log_info() { echo -e "  ${C_CYN}→${R} $*"; }
log_warn() { echo -e "  ${C_YEL}⚠${R} $*"; }

# ── 路径定位 ───────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBINIT_SCRIPT="${SCRIPT_DIR}/ubinit"
INSTALL_SCRIPT="${SCRIPT_DIR}/install.sh"
GAMES_SCRIPT="${SCRIPT_DIR}/games/launcher.sh"
INSTALL_DIR="/usr/local/bin"

# ── 参数解析 ───────────────────────────────────────────────────────────────
OPT_UNINSTALL=false
OPT_GAMES=true    # 默认同时安装 ugames 命令

for arg in "$@"; do
    case "${arg}" in
        --uninstall|-u) OPT_UNINSTALL=true ;;
        --no-games)     OPT_GAMES=false    ;;
        --games)        OPT_GAMES=true     ;;
        --help|-h)
            echo "用法: sudo bash setup.sh [选项]"
            echo ""
            echo "选项:"
            echo "  --uninstall   卸载 ubinit / ugames 命令"
            echo "  --no-games    不安装 ugames 命令"
            echo "  --help        显示此帮助"
            exit 0
            ;;
    esac
done

# ── 打印横幅 ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${C_MAG}  ╔══════════════════════════════════════╗${R}"
echo -e "${BOLD}${C_MAG}  ║    UbuntuInit  命令安装程序          ║${R}"
echo -e "${BOLD}${C_MAG}  ╚══════════════════════════════════════╝${R}"
echo ""

# ── 权限检查 ───────────────────────────────────────────────────────────────
if [[ "${EUID}" -ne 0 ]]; then
    log_err "需要 root 权限，请使用: sudo bash setup.sh"
    exit 1
fi

# ── 卸载模式 ───────────────────────────────────────────────────────────────
if [[ "${OPT_UNINSTALL}" == "true" ]]; then
    echo -e "  ${C_YEL}${BOLD}卸载命令...${R}"
    echo ""

    local_removed=false

    if [[ -L "${INSTALL_DIR}/ubinit" ]] || [[ -f "${INSTALL_DIR}/ubinit" ]]; then
        rm -f "${INSTALL_DIR}/ubinit"
        log_ok "已删除: ${INSTALL_DIR}/ubinit"
        local_removed=true
    fi

    if [[ -L "${INSTALL_DIR}/ugames" ]] || [[ -f "${INSTALL_DIR}/ugames" ]]; then
        rm -f "${INSTALL_DIR}/ugames"
        log_ok "已删除: ${INSTALL_DIR}/ugames"
    fi

    # 移除 /etc/profile.d 中的配置（若有）
    rm -f /etc/profile.d/ubinit.sh 2>/dev/null || true

    echo ""
    if [[ "${local_removed}" == "true" ]]; then
        log_ok "卸载完成！ubinit 命令已移除"
    else
        log_warn "未找到已安装的命令，可能未曾安装"
    fi
    echo ""
    exit 0
fi

# ── 安装模式 ───────────────────────────────────────────────────────────────
echo -e "  ${C_CYN}${BOLD}安装信息${R}"
log_info "项目目录:   ${SCRIPT_DIR}"
log_info "安装目标:   ${INSTALL_DIR}/ubinit"
[[ "${OPT_GAMES}" == "true" ]] && \
    log_info "游戏命令:   ${INSTALL_DIR}/ugames"
echo ""

# ── 验证源文件 ─────────────────────────────────────────────────────────────
if [[ ! -f "${UBINIT_SCRIPT}" ]]; then
    log_err "找不到 ubinit 脚本: ${UBINIT_SCRIPT}"
    log_err "请确认从项目根目录运行: sudo bash setup.sh"
    exit 1
fi

if [[ ! -f "${INSTALL_SCRIPT}" ]]; then
    log_err "找不到主程序: ${INSTALL_SCRIPT}"
    log_err "请确认项目文件完整"
    exit 1
fi

# ── 赋予脚本可执行权限 ─────────────────────────────────────────────────────
echo -e "  ${C_CYN}${BOLD}设置执行权限...${R}"

chmod +x "${UBINIT_SCRIPT}"
log_ok "ubinit 已设为可执行"

chmod +x "${SCRIPT_DIR}/install.sh"
chmod +x "${SCRIPT_DIR}/uninstall.sh"
log_ok "install.sh / uninstall.sh 已设为可执行"

# lib 目录
find "${SCRIPT_DIR}/lib"     -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
find "${SCRIPT_DIR}/modules" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
log_ok "lib/ 和 modules/ 已批量设为可执行"

# games 目录
if [[ "${OPT_GAMES}" == "true" ]] && [[ -d "${SCRIPT_DIR}/games" ]]; then
    find "${SCRIPT_DIR}/games" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
    log_ok "games/ 已设为可执行"
fi

echo ""

# ── 创建软链接 ─────────────────────────────────────────────────────────────
echo -e "  ${C_CYN}${BOLD}创建全局命令...${R}"

# 备份已存在的 ubinit 命令（非本项目）
if [[ -f "${INSTALL_DIR}/ubinit" ]] && [[ ! -L "${INSTALL_DIR}/ubinit" ]]; then
    mv "${INSTALL_DIR}/ubinit" "${INSTALL_DIR}/ubinit.bak.$(date +%s)"
    log_warn "已存在的 ubinit 命令已备份"
fi

# 创建或更新软链接
ln -sf "${UBINIT_SCRIPT}" "${INSTALL_DIR}/ubinit"
log_ok "已创建: ubinit → ${UBINIT_SCRIPT}"

# 安装 ugames 命令
if [[ "${OPT_GAMES}" == "true" ]] && [[ -f "${GAMES_SCRIPT}" ]]; then
    chmod +x "${GAMES_SCRIPT}"
    ln -sf "${GAMES_SCRIPT}" "${INSTALL_DIR}/ugames"
    log_ok "已创建: ugames → ${GAMES_SCRIPT}"
fi

echo ""

# ── 验证安装结果 ───────────────────────────────────────────────────────────
echo -e "  ${C_CYN}${BOLD}验证安装...${R}"

if command -v ubinit &>/dev/null; then
    log_ok "ubinit 命令可用  →  $(command -v ubinit)"
else
    log_warn "ubinit 未在当前 PATH 中（可能需要重新打开终端）"
    # 尝试写入 profile.d
    cat > /etc/profile.d/ubinit.sh <<'EOF'
# UbuntuInit 命令路径
export PATH="/usr/local/bin:$PATH"
EOF
    log_info "已写入 /etc/profile.d/ubinit.sh，重新登录后生效"
fi

if [[ "${OPT_GAMES}" == "true" ]] && command -v ugames &>/dev/null; then
    log_ok "ugames 命令可用  →  $(command -v ugames)"
fi

# ── 完成提示 ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${C_GRN}  ╔══════════════════════════════════════╗${R}"
echo -e "${BOLD}${C_GRN}  ║          安装完成！                  ║${R}"
echo -e "${BOLD}${C_GRN}  ╚══════════════════════════════════════╝${R}"
echo ""
echo -e "  现在可以直接在终端输入:"
echo ""
echo -e "    ${BOLD}${C_YEL}sudo ubinit${R}          ${C_WHT}# 启动 UbuntuInit 初始化工具${R}"
echo -e "    ${BOLD}${C_YEL}sudo ubinit --help${R}   ${C_WHT}# 查看帮助${R}"
echo -e "    ${BOLD}${C_YEL}sudo ubinit --dry-run${R}${C_WHT}# 预览模式（不实际修改）${R}"
[[ "${OPT_GAMES}" == "true" ]] && \
    echo -e "    ${BOLD}${C_YEL}ugames${R}               ${C_WHT}# 启动终端游戏集合${R}"
echo ""
echo -e "  卸载命令: ${C_RED}sudo bash ${SCRIPT_DIR}/setup.sh --uninstall${R}"
echo ""
