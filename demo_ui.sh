#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — TUI 演示脚本
# =============================================================================
# 用途: 在 Ubuntu 上独立运行，预览完整 TUI 界面效果
# 运行: bash demo_ui.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_VERSION="1.0.0"

# 加载库
source "${SCRIPT_DIR}/lib/logger.sh"
source "${SCRIPT_DIR}/lib/ui.sh"

# 配置
UBINIT_LOG_FILE="/tmp/ubinit-demo.log"
UBINIT_VERBOSE=false

# 初始化
logger_init "false"

# ── 演示 1：Banner ──────────────────────────────────────────
demo_banner() {
    _ui_clear
    ui_banner
    sleep 1
}

# ── 演示 2：系统信息面板 ────────────────────────────────────
demo_sysinfo() {
    ui_system_info
    echo ""
    log_info  "这是 INFO 级别日志"
    log_success "这是 SUCCESS 级别日志"
    log_warning "这是 WARNING 级别日志"
    log_error "这是 ERROR 级别日志（演示用）"
    log_step 1 5 "安装网络工具包..."
    echo ""
    sleep 1
}

# ── 演示 3：单选菜单 ─────────────────────────────────────────
demo_menu() {
    echo ""
    local choice
    choice="$(ui_menu \
        '  演示：单选菜单  ' \
        "opt1:🖥  系统基础配置" \
        "opt2:🐳  Docker 环境" \
        "opt3:🛠  开发工具" \
        "opt4:🗄  数据库服务" \
        "opt5:❌  返回" \
    )" || choice="cancelled"

    echo ""
    log_info "你选择了: ${choice}"
    sleep 1
}

# ── 演示 4：复选列表 ─────────────────────────────────────────
demo_checklist() {
    echo ""
    local selected
    selected="$(ui_checklist \
        '  演示：多选复选列表  ' \
        "docker:🐳  Docker CE" \
        "nginx:🌊  Nginx" \
        "redis:🔴  Redis" \
        "node:🟢  Node.js" \
        "python:🐍  Python" \
    )" || selected=""

    echo ""
    log_info "你选择了: ${selected:-（无）}"
    sleep 1
}

# ── 演示 5：确认框 ───────────────────────────────────────────
demo_confirm() {
    echo ""
    if ui_confirm "确认开始安装以上模块？" "yes"; then
        log_success "用户确认，开始安装！"
    else
        log_warning "用户取消操作"
    fi
    sleep 1
}

# ── 演示 6：Spinner 动画 ─────────────────────────────────────
demo_spinner() {
    echo ""
    ui_spinner_start "正在安装 Docker CE..."
    sleep 3
    ui_spinner_stop "Docker CE 安装成功" "ok"

    ui_spinner_start "正在配置 Nginx..."
    sleep 2
    ui_spinner_stop "Nginx 配置完成" "ok"

    ui_spinner_start "正在检测网络..."
    sleep 1
    ui_spinner_stop "网络检测失败（演示）" "err"
}

# ── 演示 7：进度条 ───────────────────────────────────────────
demo_progress() {
    echo ""
    log_section "安装进度演示"
    local modules=("system" "ssh" "docker" "nginx" "redis")
    local total="${#modules[@]}"
    local i=1
    for mod in "${modules[@]}"; do
        ui_progress "${mod}" "${i}" "${total}" "安装中..."
        sleep 0.6
        ui_progress "${mod}" "${i}" "${total}" "✓ 完成"
        echo ""
        (( i++ ))
    done
}

# ── 主演示流程 ───────────────────────────────────────────────
main() {
    demo_banner
    demo_sysinfo
    demo_menu
    demo_checklist
    demo_confirm
    demo_spinner
    demo_progress

    echo ""
    log_success "TUI 演示完成！运行 sudo bash install.sh 开始正式安装。"
    echo ""
}

main "$@"
