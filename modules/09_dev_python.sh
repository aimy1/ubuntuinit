#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Python 环境
# =============================================================================
# 文件     : modules/09_dev_python.sh
# 说明     : 安装 Python3（apt 或 pyenv），配置 pip 国内镜像
# 配置变量 : UBINIT_PYTHON_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        python"
    echo "description: Python 3 环境（apt/pyenv 方式）"
}

module_check() {
    # 检查 python3 命令是否存在
    if ! command -v python3 &>/dev/null; then
        return 1
    fi

    # 检查版本是否符合要求
    local required_version="${UBINIT_PYTHON_VERSION:-3.10}"
    local current_version
    current_version="$(python3 --version 2>/dev/null | awk '{print $2}' | cut -d. -f1,2)"

    if [[ -z "${current_version}" ]]; then
        return 1
    fi

    # 简单版本比较（检查主版本号）
    local required_major="${required_version%%.*}"
    local current_major="${current_version%%.*}"

    if [[ "${current_major}" -lt "${required_major}" ]]; then
        return 1
    fi

    return 0
}

# apt 方式安装
_python_install_apt() {
    log_info "使用 apt 安装 Python3..."
    
    # 安装核心包
    log_debug "安装核心包: python3 python3-dev build-essential"
    if ! apt_ensure_installed python3 python3-dev build-essential; then
        log_error "Python3 核心包安装失败"
        return 1
    fi

    # 安装 pip 和相关工具
    if [[ "${UBINIT_PYTHON_PIP:-true}" == "true" ]]; then
        log_debug "安装 pip 工具: python3-pip python3-setuptools python3-wheel"
        if ! apt_ensure_installed python3-pip python3-setuptools python3-wheel; then
            log_warning "pip 工具安装失败，可能影响包管理功能"
        fi
    fi

    # 安装 venv 支持
    if [[ "${UBINIT_PYTHON_VENV:-true}" == "true" ]]; then
        log_debug "安装 venv 支持: python3-venv"
        if ! apt_ensure_installed python3-venv; then
            log_warning "python3-venv 安装失败，虚拟环境功能可能不可用"
        fi
    fi

    # 创建 python 软链接（若不存在）
    if ! util_cmd_exists python && util_cmd_exists python3; then
        log_info "创建 python 软链接..."
        if ! ln -sf "$(command -v python3)" /usr/local/bin/python; then
            log_warning "创建 python 软链接失败"
        else
            log_debug "python 软链接已创建: /usr/local/bin/python -> $(command -v python3)"
        fi
    fi

    # 验证安装
    if command -v python3 &>/dev/null; then
        local version
        version="$(python3 --version 2>&1)"
        log_success "Python3 安装成功: ${version}"
    else
        log_error "Python3 安装验证失败"
        return 1
    fi

    return 0
}

# pyenv 方式安装
_python_install_pyenv() {
    log_info "使用 pyenv 安装 Python ${UBINIT_PYTHON_VERSION:-3.12.0}..."

    # 安装构建依赖
    log_debug "安装构建依赖..."
    if ! apt_install make build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev \
        xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev; then
        log_error "构建依赖安装失败"
        return 1
    fi

    local pyenv_root="${HOME}/.pyenv"

    # 安装 pyenv（如果不存在）
    if [[ ! -d "${pyenv_root}" ]]; then
        log_info "下载并安装 pyenv..."
        if ! net_download "https://pyenv.run" "/tmp/pyenv-install.sh"; then
            log_error "pyenv 安装脚本下载失败"
            return 1
        fi
        
        log_debug "执行 pyenv 安装脚本..."
        if ! bash /tmp/pyenv-install.sh; then
            log_error "pyenv 安装失败"
            rm -f /tmp/pyenv-install.sh
            return 1
        fi
        rm -f /tmp/pyenv-install.sh
        log_success "pyenv 安装完成"
    else
        log_info "pyenv 已存在: ${pyenv_root}"
    fi

    # 写入 profile
    log_debug "配置 pyenv 环境变量..."
    cat > /etc/profile.d/pyenv.sh <<'EOF'
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF

    # 当前会话加载 pyenv
    export PYENV_ROOT="${pyenv_root}"
    export PATH="${PYENV_ROOT}/bin:${PATH}"
    
    if ! eval "$(pyenv init -)" 2>/dev/null; then
        log_warning "pyenv 初始化失败，可能需要重新登录"
    fi

    # 安装指定的 Python 版本
    local version="${UBINIT_PYTHON_VERSION:-3.12.0}"
    log_info "安装 Python ${version}（耗时较长，请耐心等待）..."
    
    if ! pyenv install -s "${version}"; then
        log_error "Python ${version} 安装失败"
        return 1
    fi
    
    log_info "设置 Python ${version} 为全局版本..."
    if ! pyenv global "${version}"; then
        log_error "设置全局 Python 版本失败"
        return 1
    fi

    # 验证安装
    if pyenv version &>/dev/null; then
        log_success "Python ${version} 通过 pyenv 安装成功"
    else
        log_error "Python 安装验证失败"
        return 1
    fi

    return 0
}

# 配置 pip 镜像源
_python_configure_pip() {
    util_ensure_dir "${HOME}/.pip"
    cat > "${HOME}/.pip/pip.conf" <<'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
timeout = 30
EOF
    log_debug "pip 镜像已配置为清华源"
}

module_install() {
    log_section "Python 环境配置"

    if [[ "${UBINIT_PYTHON_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_PYTHON_ENABLE=false）"
        return 0
    fi

    local method="${UBINIT_PYTHON_METHOD:-apt}"

    case "${method}" in
        apt)   _python_install_apt  ;;
        pyenv) _python_install_pyenv ;;
        *)
            log_error "未知安装方式: ${method}（支持: apt / pyenv）"
            return 1
            ;;
    esac

    # 配置 pip 镜像
    _python_configure_pip

    local ver
    ver="$(python3 --version 2>/dev/null || echo '未知')"
    log_success "Python 环境就绪: ${ver}"
    return 0
}

module_uninstall() {
    local method="${UBINIT_PYTHON_METHOD:-apt}"

    case "${method}" in
        apt)
            apt_purge python3 python3-pip python3-venv python3-dev 2>/dev/null || true
            rm -f /usr/local/bin/python
            ;;
        pyenv)
            rm -rf "${HOME}/.pyenv"
            rm -f /etc/profile.d/pyenv.sh
            ;;
    esac

    rm -f "${HOME}/.pip/pip.conf"
    log_success "Python 环境已卸载"
}
