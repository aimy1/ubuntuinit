#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Rust 环境
# =============================================================================
# 文件     : modules/13_dev_rust.sh
# 说明     : 通过 rustup 安装 Rust 工具链，配置国内镜像加速
# 配置变量 : UBINIT_RUST_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        rust"
    echo "description: Rust 工具链（rustup 安装）"
}

module_check() {
    command -v rustc &>/dev/null || [[ -f "${HOME}/.cargo/bin/rustc" ]]
}

module_install() {
    log_section "Rust 环境配置"

    if [[ "${UBINIT_RUST_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_RUST_ENABLE=false）"
        return 0
    fi

    # 确定安装目标用户
    local target_user="${UBINIT_RUST_USER:-}"
    if [[ -z "${target_user}" ]]; then
        target_user="${SUDO_USER:-root}"
    fi

    log_info "安装目标用户: ${target_user}"

    # 安装构建依赖
    apt_ensure_installed curl build-essential gcc pkg-config libssl-dev

    # 下载 rustup-init.sh
    net_download "https://sh.rustup.rs" "/tmp/rustup-init.sh" 60 || {
        log_error "rustup 安装脚本下载失败"
        return 1
    }
    chmod +x /tmp/rustup-init.sh

    # 设置国内镜像（rsproxy.cn）
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"

    # 执行安装
    if [[ "${target_user}" == "root" ]]; then
        bash /tmp/rustup-init.sh -y --no-modify-path 2>&1 | \
            while IFS= read -r line; do log_debug "rustup: ${line}"; done
    else
        su -c "RUSTUP_DIST_SERVER=https://rsproxy.cn RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup bash /tmp/rustup-init.sh -y --no-modify-path" \
            "${target_user}" 2>&1 | \
            while IFS= read -r line; do log_debug "rustup: ${line}"; done
    fi

    # 写入 profile（全局）
    cat > /etc/profile.d/rust.sh <<'EOF'
# Rust 工具链环境
export PATH="$HOME/.cargo/bin:$PATH"
export RUSTUP_DIST_SERVER="https://rsproxy.cn"
export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
EOF

    # 配置 cargo 镜像源
    local cargo_conf_dir
    if [[ "${target_user}" == "root" ]]; then
        cargo_conf_dir="${HOME}/.cargo"
    else
        cargo_conf_dir="$(getent passwd "${target_user}" | cut -d: -f6)/.cargo"
    fi

    util_ensure_dir "${cargo_conf_dir}"
    cat > "${cargo_conf_dir}/config.toml" <<'EOF'
[source.crates-io]
replace-with = "rsproxy-sparse"

[source.rsproxy-sparse]
registry = "sparse+https://rsproxy.cn/index/"

[net]
git-fetch-with-cli = true
EOF

    rm -f /tmp/rustup-init.sh

    local ver
    if [[ "${target_user}" == "root" ]]; then
        ver="$(rustc --version 2>/dev/null || echo '已安装（需重新登录激活 PATH）')"
    else
        ver="$(su -c "rustc --version" "${target_user}" 2>/dev/null || echo '已安装')"
    fi

    log_success "Rust 环境就绪: ${ver}"
    log_info "cargo 镜像已配置为: rsproxy.cn"
    return 0
}

module_uninstall() {
    local target_user="${UBINIT_RUST_USER:-${SUDO_USER:-root}}"

    if [[ "${target_user}" == "root" ]]; then
        rustup self uninstall -y 2>/dev/null || rm -rf "${HOME}/.rustup" "${HOME}/.cargo"
    else
        su -c "rustup self uninstall -y" "${target_user}" 2>/dev/null || true
        local home
        home="$(getent passwd "${target_user}" | cut -d: -f6)"
        rm -rf "${home}/.rustup" "${home}/.cargo"
    fi

    rm -f /etc/profile.d/rust.sh
    log_success "Rust 环境已卸载"
}
