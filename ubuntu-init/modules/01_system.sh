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
    log_info "安装基础工具包..."
    apt_ensure_installed \
        ca-certificates curl gnupg lsb-release \
        software-properties-common apt-transport-https \
        bash-completion dbus systemd-timesyncd
}

# 配置时区
_system_set_timezone() {
    local tz="${UBINIT_SYSTEM_TIMEZONE:-}"
    [[ -z "${tz}" ]] && return 0

    if ! timedatectl list-timezones 2>/dev/null | grep -q "^${tz}$"; then
        log_warning "无效时区: ${tz}，跳过"
        return 0
    fi

    timedatectl set-timezone "${tz}" && \
        log_success "时区已设置: ${tz}"
}

# 配置 NTP
_system_set_ntp() {
    local ntp_servers="${UBINIT_SYSTEM_NTP_SERVERS:-}"
    [[ -z "${ntp_servers}" ]] && return 0

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

    systemctl restart systemd-timesyncd 2>/dev/null || true
    timedatectl set-ntp true
    log_success "NTP 已配置: ${ntp_servers}"
}

# 配置 Locale
_system_set_locale() {
    local locale="${UBINIT_SYSTEM_LOCALE:-}"
    [[ -z "${locale}" ]] && return 0

    apt_ensure_installed locales
    locale-gen "${locale}" 2>/dev/null || true
    update-locale LANG="${locale}" LC_ALL="${locale}" 2>/dev/null || true
    log_success "Locale 已设置: ${locale}"
}

# 配置 Hostname
_system_set_hostname() {
    local hostname="${UBINIT_SYSTEM_HOSTNAME:-}"
    [[ -z "${hostname}" ]] && return 0

    local old_hostname
    old_hostname="$(hostname -s)"

    hostnamectl set-hostname "${hostname}" 2>/dev/null || \
        echo "${hostname}" > /etc/hostname

    # 更新 /etc/hosts
    if ! grep -q "${hostname}" /etc/hosts; then
        sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${hostname}/" /etc/hosts
        grep -q "127.0.1.1" /etc/hosts || \
            echo "127.0.1.1	${hostname}" >> /etc/hosts
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
