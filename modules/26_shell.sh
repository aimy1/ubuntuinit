#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Shell 环境美化
# =============================================================================
# 文件     : modules/26_shell.sh
# 说明     : 安装 Zsh + Oh My Zsh + Starship Prompt + Fastfetch + bash-completion
# 配置变量 : UBINIT_SHELL_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        shell"
    echo "description: Shell 美化（Zsh / Oh-My-Zsh / Starship / Fastfetch）"
}

module_check() {
    # Zsh 或 Starship 任一已安装即视为已配置
    command -v zsh &>/dev/null || command -v starship &>/dev/null
}

# 安装 bash-completion
_shell_bash_completion() {
    [[ "${UBINIT_SHELL_BASH_COMPLETION:-true}" != "true" ]] && return 0

    apt_ensure_installed bash-completion

    # 确保 /etc/bash.bashrc 加载 bash-completion
    util_append_line /etc/bash.bashrc \
        "[ -f /etc/bash_completion ] && . /etc/bash_completion"

    log_success "bash-completion 已配置"
}

# 安装 fastfetch（系统信息展示）
_shell_fastfetch() {
    [[ "${UBINIT_SHELL_FASTFETCH:-false}" != "true" ]] && return 0
    command -v fastfetch &>/dev/null && { log_debug "fastfetch 已安装"; return 0; }

    log_info "安装 fastfetch..."
    # 尝试多种安装方式
    if apt_is_available fastfetch; then
        apt_install fastfetch
    elif util_cmd_exists snap; then
        snap install fastfetch 2>/dev/null && \
            log_success "fastfetch 已通过 snap 安装"
    else
        # 从 GitHub release 下载 deb 包
        local ver="2.26.1"
        local arch
        case "${DETECT_ARCH:-$(uname -m)}" in
            amd64|x86_64)  arch="amd64" ;;
            arm64|aarch64) arch="arm64" ;;
            *) arch="amd64" ;;
        esac
        net_download \
            "https://github.com/fastfetch-cli/fastfetch/releases/download/${ver}/fastfetch-linux-${arch}.deb" \
            "/tmp/fastfetch.deb" 60 && \
            dpkg -i /tmp/fastfetch.deb 2>/dev/null && \
            rm -f /tmp/fastfetch.deb
    fi

    command -v fastfetch &>/dev/null && log_success "fastfetch 安装完成"
}

# 安装 Zsh
_shell_zsh() {
    [[ "${UBINIT_SHELL_ZSH:-false}" != "true" ]] && return 0

    log_info "安装 Zsh..."
    apt_install zsh

    # 设为目标用户的默认 Shell
    local target_user="${UBINIT_USER_NAME:-${SUDO_USER:-root}}"
    if id "${target_user}" &>/dev/null; then
        chsh -s "$(command -v zsh)" "${target_user}"
        log_info "用户 ${target_user} 的默认 Shell 已切换为 Zsh（重新登录后生效）"
    fi
}

# 安装 Oh My Zsh
_shell_ohmyzsh() {
    [[ "${UBINIT_SHELL_OH_MY_ZSH:-false}" != "true" ]] && return 0
    ! command -v zsh &>/dev/null && { log_warning "Zsh 未安装，跳过 Oh My Zsh"; return 0; }

    local ohmyzsh_dir="${HOME}/.oh-my-zsh"
    if [[ -d "${ohmyzsh_dir}" ]]; then
        log_debug "Oh My Zsh 已存在，跳过"
        return 0
    fi

    log_info "安装 Oh My Zsh..."
    net_download \
        "https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh" \
        "/tmp/ohmyzsh-install.sh" 60 || {
        log_warning "Oh My Zsh 安装脚本下载失败，跳过"
        return 0
    }

    RUNZSH=no CHSH=no sh /tmp/ohmyzsh-install.sh 2>&1 | \
        while IFS= read -r line; do log_debug "ohmyzsh: ${line}"; done
    rm -f /tmp/ohmyzsh-install.sh

    log_success "Oh My Zsh 安装完成"
}

# 安装 Starship Prompt
_shell_starship() {
    [[ "${UBINIT_SHELL_STARSHIP:-false}" != "true" ]] && return 0
    command -v starship &>/dev/null && { log_debug "Starship 已安装"; return 0; }

    log_info "安装 Starship Prompt..."
    net_download "https://starship.rs/install.sh" "/tmp/starship-install.sh" 60 || {
        log_warning "Starship 安装脚本下载失败，跳过"
        return 0
    }

    sh /tmp/starship-install.sh -y 2>&1 | \
        while IFS= read -r line; do log_debug "starship: ${line}"; done
    rm -f /tmp/starship-install.sh

    if command -v starship &>/dev/null; then
        # 添加到 bash
        util_append_line "${HOME}/.bashrc" 'eval "$(starship init bash)"'

        # 添加到 zsh（若已安装）
        command -v zsh &>/dev/null && \
            util_append_line "${HOME}/.zshrc" 'eval "$(starship init zsh)"' 2>/dev/null || true

        log_success "Starship Prompt 安装完成"
    fi
}

module_install() {
    log_section "Shell 环境美化"

    _shell_bash_completion
    _shell_fastfetch
    _shell_zsh
    _shell_ohmyzsh
    _shell_starship

    log_success "Shell 环境配置完成"
    return 0
}

module_uninstall() {
    log_info "清除 Shell 美化配置..."
    apt_purge zsh bash-completion 2>/dev/null || true
    rm -f /usr/local/bin/starship
    rm -rf "${HOME}/.oh-my-zsh"
    snap remove fastfetch 2>/dev/null || true
    apt_purge fastfetch 2>/dev/null || true
    log_success "Shell 美化配置已清除"
}
