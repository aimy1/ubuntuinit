#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块: 系统基础配置
# =============================================================================
# 文件     : modules/01_system.sh
# 说明     : APT更新升级、时区、NTP、Locale、Hostname
# 配置变量 : UBINIT_SYSTEM_*（见 config/default.conf）
# 依赖     : lib/logger.sh  lib/apt.sh  lib/utils.sh
# =============================================================================

module_info() {
    echo "name:        system"
    echo "description: APT更新、时区、NTP、Locale、Hostname"
}

# 始终重新执行（各子步骤内部幂等）
module_check() { return 1; }

# 安装基础软件包
_system_install_base_pkgs() {
    local -a pkgs=(
        ca-certificates curl gnupg lsb-release
        software-properties-common apt-transport-https
        bash-completion dbus systemd-timesyncd
    )

    log_info "检查基础工具包..."
    local missing=()
    for pkg in "${pkgs[@]}"; do
        if ! dpkg -l "${pkg}" &>/dev/null; then
            missing+=("${pkg}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log_debug "所有基础包已安装"
        return 0
    fi

    log_info "安装缺失的包: ${missing[*]}"
    apt_ensure_installed "${missing[@]}"
}

# 配置时区
_system_set_timezone() {
    local tz="${UBINIT_SYSTEM_TIMEZONE:-}"
    [[ -z "${tz}" ]] && return 0

    # 验证时区有效性
    if ! timedatectl list-timezones 2>/dev/null | grep -q "^${tz}$"; then
        log_warning "无效时区: ${tz}，跳过"
        return 0
    fi

    # 检查当前时区
    local current_tz
    current_tz="$(timedatectl show -p Timezone --value 2>/dev/null || echo '')"
    if [[ "${current_tz}" == "${tz}" ]]; then
        log_debug "时区已是: ${tz}"
        return 0
    fi

    # 设置时区
    if timedatectl set-timezone "${tz}"; then
        log_success "时区已设置: ${tz}"
    else
        log_error "设置时区失败: ${tz}"
        return 1
    fi
}

# 配置 NTP
_system_set_ntp() {
    local ntp_servers="${UBINIT_SYSTEM_NTP_SERVERS:-}"
    [[ -z "${ntp_servers}" ]] && return 0

    # 检查 systemd-timesyncd 是否可用
    if ! systemctl list-unit-files systemd-timesyncd.service &>/dev/null; then
        log_warning "systemd-timesyncd 不可用，跳过 NTP 配置"
        return 0
    fi

    # 写入 timesyncd.conf
    backup_file /etc/systemd/timesyncd.conf system
    cat > /etc/systemd/timesyncd.conf <<EOF
[Time]
NTP=${ntp_servers}
FallbackNTP=ntp.ubuntu.com
RootDistanceMaxSec=5
PollIntervalMinSec=32
PollIntervalMaxSec=2048
EOF

    # 重启并启用服务
    if ! systemctl restart systemd-timesyncd 2>/dev/null; then
        log_warning "重启 systemd-timesyncd 失败"
    fi

    if ! timedatectl set-ntp true 2>/dev/null; then
        log_warning "启用 NTP 失败"
    fi

    # 验证服务状态
    sleep 1
    if systemctl is-active --quiet systemd-timesyncd; then
        log_success "NTP 已配置: ${ntp_servers}"
    else
        log_warning "NTP 服务未正常运行，但配置已保存"
    fi
}

# 配置 Locale
_system_set_locale() {
    local locale="${UBINIT_SYSTEM_LOCALE:-}"
    [[ -z "${locale}" ]] && return 0

    # 检查当前 locale
    local current_locale
    current_locale="$(locale 2>/dev/null | grep '^LANG=' | cut -d= -f2 || echo '')"
    if [[ "${current_locale}" == "${locale}" ]]; then
        log_debug "Locale 已是: ${locale}"
        return 0
    fi

    apt_ensure_installed locales

    # 生成 locale
    if ! locale-gen "${locale}" 2>/dev/null; then
        log_error "生成 locale 失败: ${locale}"
        return 1
    fi

    # 更新系统 locale
    if ! update-locale LANG="${locale}" LC_ALL="${locale}" 2>/dev/null; then
        log_error "更新 locale 配置失败"
        return 1
    fi

    log_success "Locale 已设置: ${locale}"
}

# 配置 Hostname
_system_set_hostname() {
    local hostname="${UBINIT_SYSTEM_HOSTNAME:-}"
    [[ -z "${hostname}" ]] && return 0

    local old_hostname
    old_hostname="$(hostname -s)"

    # 检查是否已经是目标 hostname
    if [[ "${old_hostname}" == "${hostname}" ]]; then
        log_debug "Hostname 已是: ${hostname}"
        return 0
    fi

    # 设置 hostname
    if ! hostnamectl set-hostname "${hostname}" 2>/dev/null; then
        # 降级方案
        if ! echo "${hostname}" > /etc/hostname 2>/dev/null; then
            log_error "设置 hostname 失败"
            return 1
        fi
    fi

    # 更新 /etc/hosts
    if ! grep -q "${hostname}" /etc/hosts; then
        # 尝试替换现有条目
        if grep -q "127.0.1.1" /etc/hosts; then
            sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${hostname}/" /etc/hosts
        else
            # 添加新条目
            echo "127.0.1.1	${hostname}" >> /etc/hosts
        fi
    fi

    log_success "Hostname 已设置: ${old_hostname} → ${hostname}"
}

module_install() {
    log_section "系统基础配置"

    # 安装基础包
    _system_install_base_pkgs

    # APT 更新
    [[ "${UBINIT_SYSTEM_APT_UPDATE:-true}" == "true" ]] && apt_update

    # APT 升级
    [[ "${UBINIT_SYSTEM_APT_UPGRADE:-true}" == "true" ]] && apt_upgrade

    # 清理
    [[ "${UBINIT_SYSTEM_AUTOREMOVE:-true}" == "true" ]] && apt_autoremove
    [[ "${UBINIT_SYSTEM_AUTOCLEAN:-true}" == "true" ]]  && apt_autoclean

    # 系统配置
    _system_set_timezone
    _system_set_ntp
    _system_set_locale
    _system_set_hostname

    log_success "系统基础配置完成"
    return 0
}

module_uninstall() {
    log_info "系统基础配置模块不执行卸载（防止破坏系统环境）"
    return 0
}
