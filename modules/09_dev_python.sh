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

module_check() { command -v python3 &>/dev/null; }

# apt 方式安装
_python_install_apt() {
    log_info "使用 apt 安装 Python3..."
    apt_ensure_installed python3 python3-dev build-essential

    [[ "${UBINIT_PYTHON_PIP:-true}"  == "true" ]] && \
        apt_ensure_installed python3-pip python3-setuptools python3-wheel

    [[ "${UBINIT_PYTHON_VENV:-true}" == "true" ]] && \
        apt_ensure_installed python3-venv

    # 创建 python 软链接（若不存在）
    if ! util_cmd_exists python && util_cmd_exists python3; then
        ln -sf "$(command -v python3)" /usr/local/bin/python
    fi
}

# pyenv 方式安装
_python_install_pyenv() {
    log_info "使用 pyenv 安装 Python ${UBINIT_PYTHON_VERSION:-3.12.0}..."

    # 安装构建依赖
    apt_install make build-essential libssl-dev zlib1g-dev libbz2-dev \
        libreadline-dev libsqlite3-dev wget curl llvm libncurses5-dev \
        xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

    local pyenv_root="${HOME}/.pyenv"

    if [[ ! -d "${pyenv_root}" ]]; then
        log_info "下载并安装 pyenv..."
        net_download "https://pyenv.run" "/tmp/pyenv-install.sh" || {
            log_error "pyenv 安装脚本下载失败"
            return 1
        }
        bash /tmp/pyenv-install.sh
    else
        log_info "pyenv 已存在: ${pyenv_root}"
    fi

    # 写入 profile
    cat > /etc/profile.d/pyenv.sh <<'EOF'
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF

    # 当前会话加载 pyenv
    export PYENV_ROOT="${pyenv_root}"
    export PATH="${PYENV_ROOT}/bin:${PATH}"
    eval "$(pyenv init -)" 2>/dev/null || true

    local version="${UBINIT_PYTHON_VERSION:-3.12.0}"
    log_info "安装 Python ${version}（耗时较长，请耐心等待）..."
    pyenv install -s "${version}"
    pyenv global "${version}"
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
