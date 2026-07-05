#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Node.js 环境
# =============================================================================
# 文件     : modules/10_dev_node.sh
# 说明     : 安装 Node.js（nvm/nodesource/apt），配置 npm 国内镜像
# 配置变量 : UBINIT_NODE_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        node"
    echo "description: Node.js 环境（nvm/nodesource/apt 方式）"
}

module_check() { command -v node &>/dev/null; }

# nvm 方式
_node_install_nvm() {
    local version="${UBINIT_NODE_VERSION:-lts}"
    local nvm_dir="${NVM_DIR:-$HOME/.nvm}"

    apt_ensure_installed curl

    if [[ ! -d "${nvm_dir}" ]]; then
        log_info "安装 nvm..."
        net_download \
            "https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh" \
            "/tmp/nvm-install.sh" || {
            log_error "nvm 安装脚本下载失败（检查网络或使用其他安装方式）"
            return 1
        }
        bash /tmp/nvm-install.sh
    fi

    # 写入 profile
    cat > /etc/profile.d/nvm.sh <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF

    # 当前会话加载
    export NVM_DIR="${nvm_dir}"
    # shellcheck source=/dev/null
    [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

    log_info "安装 Node.js (${version})..."
    if [[ "${version}" == "lts" ]]; then
        nvm install --lts
        nvm alias default 'lts/*'
    else
        nvm install "${version}"
        nvm alias default "${version}"
    fi

    nvm use default
}

# NodeSource 官方 deb 包方式
_node_install_nodesource() {
    local version="${UBINIT_NODE_VERSION:-lts}"
    # lts 对应的大版本
    local major="20"
    [[ "${version}" =~ ^[0-9]+$ ]] && major="${version}"
    [[ "${version}" == "lts" ]]    && major="20"
    [[ "${version}" == "current" ]] && major="22"

    log_info "从 NodeSource 安装 Node.js ${major}.x..."

    net_download \
        "https://deb.nodesource.com/setup_${major}.x" \
        "/tmp/nodesource_setup.sh" || return 1

    bash /tmp/nodesource_setup.sh
    apt_install nodejs
}

# apt 方式（版本可能较旧）
_node_install_apt() {
    log_info "使用 apt 安装 Node.js..."
    apt_install nodejs npm
}

module_install() {
    log_section "Node.js 环境配置"

    if [[ "${UBINIT_NODE_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_NODE_ENABLE=false）"
        return 0
    fi

    local method="${UBINIT_NODE_METHOD:-nvm}"

    case "${method}" in
        nvm)        _node_install_nvm        || return 1 ;;
        nodesource) _node_install_nodesource || return 1 ;;
        apt)        _node_install_apt        || return 1 ;;
        *)
            log_error "未知安装方式: ${method}（支持: nvm/nodesource/apt）"
            return 1
            ;;
    esac

    # 配置 npm 镜像
    if util_cmd_exists npm; then
        npm config set registry https://registry.npmmirror.com 2>/dev/null || true
        log_debug "npm 镜像已设置为 npmmirror"
    fi

    # 可选全局包
    if util_cmd_exists npm; then
        [[ "${UBINIT_NODE_YARN:-false}"  == "true" ]] && npm install -g yarn  2>/dev/null || true
        [[ "${UBINIT_NODE_PNPM:-false}"  == "true" ]] && npm install -g pnpm  2>/dev/null || true
    fi

    local ver
    ver="$(node --version 2>/dev/null || echo '未知')"
    log_success "Node.js 环境就绪: ${ver}"
    return 0
}

module_uninstall() {
    local method="${UBINIT_NODE_METHOD:-nvm}"

    case "${method}" in
        nvm)
            rm -rf "${HOME}/.nvm"
            rm -f /etc/profile.d/nvm.sh
            ;;
        nodesource|apt)
            apt_purge nodejs npm 2>/dev/null || true
            ;;
    esac

    log_success "Node.js 环境已卸载"
}
