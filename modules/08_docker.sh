#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Docker CE
# =============================================================================
# 文件     : modules/08_docker.sh
# 说明     : 安装 Docker CE + Compose Plugin + Buildx，配置镜像加速
# 配置变量 : UBINIT_DOCKER_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/service.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        docker"
    echo "description: Docker CE + Compose Plugin + Buildx + 镜像加速"
}

module_check() {
    # 检查 docker 命令是否存在
    if ! command -v docker &>/dev/null; then
        return 1
    fi

    # 检查 docker 服务是否运行
    if ! systemctl is-active --quiet docker 2>/dev/null; then
        return 1
    fi

    # 检查 docker 版本
    if ! docker version &>/dev/null 2>&1; then
        return 1
    fi

    return 0
}

# 获取 Docker 安装架构标识（Docker 仓库使用的名称）
_docker_arch() {
    case "${DETECT_ARCH:-$(uname -m)}" in
        amd64|x86_64) echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *) echo "amd64" ;;
    esac
}

# 构建镜像加速地址列表
_docker_registry_mirrors() {
    # 用户自定义优先
    if [[ -n "${UBINIT_DOCKER_REGISTRY_MIRRORS:-}" ]]; then
        echo "${UBINIT_DOCKER_REGISTRY_MIRRORS}"
        return
    fi

    case "${UBINIT_DOCKER_REGISTRY_MIRROR_SOURCE:-aliyun}" in
        aliyun)  echo "https://registry.cn-hangzhou.aliyuncs.com" ;;
        tencent) echo "https://mirror.ccs.tencentyun.com" ;;
        *)       echo "" ;;
    esac
}

module_install() {
    log_section "Docker CE 安装"

    if [[ "${UBINIT_DOCKER_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_DOCKER_ENABLE=false）"
        return 0
    fi

    # 检查是否已安装
    if module_check; then
        log_info "Docker 已安装且运行正常，跳过安装"
        return 0
    fi

    local arch
    arch="$(_docker_arch)"
    local codename
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"

    log_info "架构: ${arch}  系统代号: ${codename}"

    # 1. 添加 Docker GPG 密钥
    log_info "添加 Docker GPG 密钥..."
    util_ensure_dir /etc/apt/keyrings
    if ! apt_add_key \
        "https://download.docker.com/linux/ubuntu/gpg" \
        "/etc/apt/keyrings/docker.asc"; then
        log_error "添加 Docker GPG 密钥失败"
        return 1
    fi

    # 2. 添加 Docker APT 源
    log_info "添加 Docker APT 源..."
    if ! apt_add_source "docker.list" \
        "deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${codename} stable"; then
        log_error "添加 Docker APT 源失败"
        return 1
    fi

    # 3. 更新并安装
    log_info "更新 APT 包索引..."
    apt_update || {
        log_error "APT 更新失败"
        return 1
    }

    local -a pkgs=(docker-ce docker-ce-cli containerd.io)
    [[ "${UBINIT_DOCKER_COMPOSE:-true}" == "true" ]] && pkgs+=(docker-compose-plugin)
    [[ "${UBINIT_DOCKER_BUILDX:-true}"  == "true" ]] && pkgs+=(docker-buildx-plugin)

    log_info "安装包: ${pkgs[*]}"
    if ! apt_install "${pkgs[@]}"; then
        log_error "Docker 包安装失败"
        return 1
    fi

    # 4. 配置 daemon.json（镜像加速 + 日志驱动）
    log_info "配置 Docker daemon..."
    util_ensure_dir /etc/docker

    local mirror
    mirror="$(_docker_registry_mirrors)"
    local mirrors_json="[]"
    [[ -n "${mirror}" ]] && mirrors_json="[\"${mirror}\"]"

    cat > /etc/docker/daemon.json <<EOF
{
  "registry-mirrors": ${mirrors_json},
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "exec-opts": ["native.cgroupdriver=systemd"],
  "storage-driver": "overlay2"
}
EOF

    log_debug "daemon.json 已写入"

    # 5. 启动服务
    log_info "启动 Docker 服务..."
    service_daemon_reload || {
        log_warning "systemd daemon 重载失败"
    }

    if [[ "${UBINIT_DOCKER_AUTOSTART:-true}" == "true" ]]; then
        if ! service_enable_start docker; then
            log_error "Docker 服务启动失败"
            return 1
        fi
        service_enable containerd || {
            log_warning "containerd 服务启用失败"
        }
    fi

    # 6. 将用户加入 docker 组
    if [[ "${UBINIT_DOCKER_ADD_USER:-true}" == "true" ]] && \
       [[ -n "${UBINIT_USER_NAME:-}" ]] && \
       id "${UBINIT_USER_NAME}" &>/dev/null; then
        if ! id -nG "${UBINIT_USER_NAME}" | grep -qw docker; then
            log_info "将用户 ${UBINIT_USER_NAME} 加入 docker 组..."
            if ! usermod -aG docker "${UBINIT_USER_NAME}"; then
                log_warning "将用户加入 docker 组失败"
            else
                log_info "用户 ${UBINIT_USER_NAME} 已加入 docker 组（需重新登录生效）"
            fi
        else
            log_debug "用户 ${UBINIT_USER_NAME} 已在 docker 组中"
        fi
    fi

    # 7. 验证安装
    log_info "验证 Docker 安装..."
    sleep 2
    local docker_ver
    docker_ver="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '未知')"

    if [[ "${docker_ver}" == "未知" ]]; then
        log_error "Docker 安装验证失败"
        return 1
    fi

    log_success "Docker CE 安装完成  版本: ${docker_ver}"
    [[ -n "${mirror}" ]] && log_info "镜像加速: ${mirror}"

    return 0
}

module_uninstall() {
    log_warning "卸载 Docker CE（数据目录将被保留，请手动删除 /var/lib/docker）"

    # 停止服务
    log_info "停止 Docker 服务..."
    service_stop docker 2>/dev/null || {
        log_warning "停止 docker 服务失败"
    }
    service_stop containerd 2>/dev/null || {
        log_warning "停止 containerd 服务失败"
    }

    # 卸载包
    log_info "卸载 Docker 包..."
    if ! apt_purge \
        docker-ce docker-ce-cli containerd.io \
        docker-compose-plugin docker-buildx-plugin \
        docker-ce-rootless-extras 2>/dev/null; then
        log_error "Docker 包卸载失败"
        return 1
    fi

    # 清理配置文件
    log_info "清理 Docker 配置..."
    rm -f /etc/apt/sources.list.d/docker.list
    rm -f /etc/apt/keyrings/docker.asc
    rm -f /etc/docker/daemon.json

    # 更新 APT 缓存
    apt_update 2>/dev/null || true

    log_success "Docker 已卸载（数据目录 /var/lib/docker 未删除）"
    return 0
}
