#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Go 语言环境
# =============================================================================
# 文件     : modules/12_dev_go.sh
# 说明     : 从官方下载并安装 Go，配置 GOPROXY 国内加速
# 配置变量 : UBINIT_GO_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        go"
    echo "description: Go 语言环境（官方 tar.gz 安装）"
}

module_check() { command -v go &>/dev/null || [[ -x /usr/local/go/bin/go ]]; }

# 解析 Go 最新版本
_go_latest_version() {
    local ver
    ver="$(net_fetch 'https://golang.google.cn/VERSION?m=text' 5 2>/dev/null | head -1 | tr -d '[:space:]')"
    # 去掉前缀 "go"
    echo "${ver#go}"
}

module_install() {
    log_section "Go 语言环境"

    if [[ "${UBINIT_GO_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_GO_ENABLE=false）"
        return 0
    fi

    # 确定版本
    local version="${UBINIT_GO_VERSION:-latest}"
    if [[ "${version}" == "latest" ]]; then
        log_info "查询 Go 最新版本..."
        version="$(_go_latest_version)"
        if [[ -z "${version}" ]]; then
            log_warning "无法获取最新版本，使用 1.22.5"
            version="1.22.5"
        fi
    fi

    # 确定架构
    local arch
    case "${DETECT_ARCH:-$(uname -m)}" in
        amd64|x86_64) arch="amd64" ;;
        arm64|aarch64) arch="arm64" ;;
        *) arch="amd64" ;;
    esac

    local tarball="go${version}.linux-${arch}.tar.gz"
    local url="https://golang.google.cn/dl/${tarball}"
    local tmp_file="/tmp/${tarball}"

    log_info "下载 Go ${version} (${arch})..."
    net_download "${url}" "${tmp_file}" 120 || {
        log_error "Go 下载失败: ${url}"
        return 1
    }

    # 删除旧版本并解压
    log_info "安装 Go 到 /usr/local/go..."
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${tmp_file}" || {
        log_error "Go 解压失败"
        rm -f "${tmp_file}"
        return 1
    }

    rm -f "${tmp_file}"

    # 写入 profile
    cat > /etc/profile.d/go.sh <<'EOF'
export PATH="$PATH:/usr/local/go/bin"
export GOPATH="$HOME/go"
export GOBIN="$GOPATH/bin"
export PATH="$PATH:$GOBIN"
export GOPROXY="https://goproxy.cn,https://goproxy.io,direct"
export GONOSUMDB="*"
EOF

    # 创建软链接便于当前会话使用
    ln -sf /usr/local/go/bin/go /usr/local/bin/go 2>/dev/null || true
    ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt 2>/dev/null || true

    local ver
    ver="$(/usr/local/go/bin/go version 2>/dev/null)"
    log_success "Go 环境就绪: ${ver}"
    log_info "GOPROXY 已配置为: goproxy.cn"
    return 0
}

module_uninstall() {
    rm -rf /usr/local/go
    rm -f /usr/local/bin/go /usr/local/bin/gofmt
    rm -f /etc/profile.d/go.sh
    log_success "Go 环境已卸载"
}
