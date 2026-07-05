#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: Java 环境
# =============================================================================
# 文件     : modules/11_dev_java.sh
# 说明     : 安装 Java JDK（apt/SDKMAN 方式）
# 配置变量 : UBINIT_JAVA_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/network.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        java"
    echo "description: Java JDK 环境（apt/SDKMAN 方式）"
}

module_check() { command -v java &>/dev/null; }

# apt 方式（OpenJDK 或 Eclipse Temurin）
_java_install_apt() {
    local version="${UBINIT_JAVA_VERSION:-21}"
    local dist="${UBINIT_JAVA_DIST:-openjdk}"

    case "${dist}" in
        openjdk)
            log_info "安装 OpenJDK ${version}..."
            apt_install "openjdk-${version}-jdk" "openjdk-${version}-jre-headless"
            ;;
        temurin)
            log_info "安装 Eclipse Temurin JDK ${version}..."
            util_ensure_dir /etc/apt/keyrings

            apt_add_key \
                "https://packages.adoptium.net/artifactory/api/gpg/key/public" \
                "/etc/apt/keyrings/adoptium.asc"

            local codename
            codename="$(. /etc/os-release && echo "${VERSION_CODENAME}")"
            apt_add_source "adoptium.list" \
                "deb [signed-by=/etc/apt/keyrings/adoptium.asc] https://packages.adoptium.net/artifactory/deb ${codename} main"

            apt_update
            apt_install "temurin-${version}-jdk"
            ;;
        *)
            log_warning "未知发行版 ${dist}，回退到 OpenJDK"
            apt_install "openjdk-${version}-jdk"
            ;;
    esac

    # 写入 JAVA_HOME 环境变量
    cat > /etc/profile.d/java.sh <<'JAVA_PROFILE'
if command -v java &>/dev/null; then
    export JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")"
    export PATH="$JAVA_HOME/bin:$PATH"
fi
JAVA_PROFILE
}

# SDKMAN 方式
_java_install_sdkman() {
    local version="${UBINIT_JAVA_VERSION:-21}"

    log_info "安装 SDKMAN..."
    apt_ensure_installed curl zip unzip

    if [[ ! -d "${HOME}/.sdkman" ]]; then
        net_download "https://get.sdkman.io" "/tmp/sdkman-install.sh" || {
            log_error "SDKMAN 安装脚本下载失败"
            return 1
        }
        bash /tmp/sdkman-install.sh
    fi

    # 加载 SDKMAN
    # shellcheck source=/dev/null
    [[ -s "${HOME}/.sdkman/bin/sdkman-init.sh" ]] && \
        source "${HOME}/.sdkman/bin/sdkman-init.sh"

    log_info "通过 SDKMAN 安装 Java ${version}..."
    sdk install java "${version}-open" 2>/dev/null || \
        sdk install java "$(sdk list java | grep "${version}" | head -1 | awk '{print $NF}')"
}

module_install() {
    log_section "Java 环境配置"

    if [[ "${UBINIT_JAVA_ENABLE:-false}" != "true" ]]; then
        log_info "跳过（UBINIT_JAVA_ENABLE=false）"
        return 0
    fi

    local method="${UBINIT_JAVA_METHOD:-apt}"

    case "${method}" in
        apt)    _java_install_apt    || return 1 ;;
        sdkman) _java_install_sdkman || return 1 ;;
        *)
            log_error "未知安装方式: ${method}（支持: apt/sdkman）"
            return 1
            ;;
    esac

    java -version 2>&1 | while IFS= read -r line; do log_success "  ${line}"; done
    return 0
}

module_uninstall() {
    apt_purge "openjdk-*-jdk" "openjdk-*-jre*" "temurin-*-jdk" 2>/dev/null || true
    rm -rf "${HOME}/.sdkman"
    rm -f /etc/profile.d/java.sh
    log_success "Java 环境已卸载"
}
