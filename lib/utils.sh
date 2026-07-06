#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 通用工具函数库
# =============================================================================
# 文件     : lib/utils.sh
# 说明     : 字符串处理、数组操作、系统校验、通用辅助函数
#           : 无副作用，可被任意模块 source
# 依赖     : lib/logger.sh（log_* 函数）
# =============================================================================

# =============================================================================
# 1. 字符串工具
# =============================================================================

# 去除字符串首尾空白
# 参数: $1=字符串
# 输出: 处理后的字符串
util_trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"  # 去前空白
    s="${s%"${s##*[![:space:]]}"}"  # 去尾空白
    echo "${s}"
}

# 将字符串转为小写
# 参数: $1=字符串
util_lower() {
    echo "${1,,}"
}

# 将字符串转为大写
# 参数: $1=字符串
util_upper() {
    echo "${1^^}"
}

# 检查字符串是否以指定前缀开头
# 参数: $1=字符串 $2=前缀
# 返回: 0=是  1=否
util_starts_with() {
    [[ "${1}" == "${2}"* ]]
}

# 检查字符串是否以指定后缀结尾
# 参数: $1=字符串 $2=后缀
util_ends_with() {
    [[ "${1}" == *"${2}" ]]
}

# 检查字符串是否包含子串
# 参数: $1=字符串 $2=子串
util_contains() {
    [[ "${1}" == *"${2}"* ]]
}

# 将字符串按分隔符分割为数组（print，非 eval）
# 参数: $1=字符串 $2=分隔符（默认逗号）
# 输出: 每行一个元素
util_split() {
    local str="$1"
    local sep="${2:-,}"
    local IFS="${sep}"
    # shellcheck disable=SC2206
    local -a parts=( ${str} )
    printf '%s\n' "${parts[@]}"
}

# 将逗号分隔的字符串转为数组（写入 nameref）
# 参数: $1=目标数组名（nameref）  $2=逗号分隔字符串
util_csv_to_array() {
    local -n _arr="$1"
    local csv="$2"
    local IFS=','
    # shellcheck disable=SC2206
    _arr=( ${csv} )
}

# 重复字符 N 次
# 参数: $1=字符 $2=次数
util_repeat_char() {
    local char="$1"
    local n="$2"
    # 使用 %s 避免 char 含 % 时的格式化注入
    printf '%s%.0s' "${char}" $(seq 1 "${n}")
}

# =============================================================================
# 2. 版本比较
# =============================================================================

# 比较两个版本号（语义化版本）
# 参数: $1=版本A  $2=版本B
# 返回: 0=A>=B  1=A<B
util_version_gte() {
    # 将版本号按 . 分割后逐段比较
    local IFS=.
    # shellcheck disable=SC2206
    local -a va=( ${1} ) vb=( ${2} )
    local i
    for (( i=0; i<${#vb[@]}; i++ )); do
        local a="${va[$i]:-0}"
        local b="${vb[$i]:-0}"
        (( a < b )) && return 1
        (( a > b )) && return 0
    done
    return 0
}

# =============================================================================
# 3. 文件与目录工具
# =============================================================================

# 确保目录存在（mkdir -p + 权限）
# 参数: $1=路径 $2=权限（可选，八进制）$3=所有者（可选，user:group）
util_ensure_dir() {
    local path="$1"
    local mode="${2:-}"
    local owner="${3:-}"

    if [[ ! -d "${path}" ]]; then
        mkdir -p "${path}" || {
            log_error "无法创建目录: ${path}"
            return 1
        }
    fi

    [[ -n "${mode}" ]]  && chmod "${mode}" "${path}"
    [[ -n "${owner}" ]] && chown "${owner}" "${path}"
    return 0
}

# 安全写入文件（原子写入，先写 .tmp 再移动）
# 参数: $1=目标文件  $2=内容
util_write_file() {
    local dest="$1"
    local content="$2"
    local tmp="${dest}.ubinit.tmp"

    util_ensure_dir "$(dirname "${dest}")"
    printf '%s' "${content}" > "${tmp}" || {
        log_error "无法写入临时文件: ${tmp}"
        return 1
    }
    mv -f "${tmp}" "${dest}" || {
        log_error "无法移动文件: ${tmp} → ${dest}"
        rm -f "${tmp}"
        return 1
    }
}

# 检查文件是否包含指定行（精确匹配）
# 参数: $1=文件  $2=行内容
util_file_has_line() {
    grep -qxF "$2" "$1" 2>/dev/null
}

# 追加行到文件（若行不存在）
# 参数: $1=文件  $2=行内容
util_append_line() {
    local file="$1"
    local line="$2"

    util_file_has_line "${file}" "${line}" && return 0
    echo "${line}" >> "${file}" || {
        log_error "无法追加到文件: ${file}"
        return 1
    }
}

# 在文件中替换/新增配置行（key=value 或 key value 形式）
# 参数: $1=文件  $2=键  $3=值  $4=分隔符（默认 =）
util_set_config() {
    local file="$1"
    local key="$2"
    local value="$3"
    local sep="${4:-=}"

    util_ensure_dir "$(dirname "${file}")"

    if grep -qE "^#?[[:space:]]*${key}[[:space:]]*${sep}" "${file}" 2>/dev/null; then
        sed -i "s|^#\?[[:space:]]*${key}[[:space:]]*${sep}.*|${key}${sep}${value}|" "${file}"
    else
        echo "${key}${sep}${value}" >> "${file}"
    fi
}

# =============================================================================
# 4. 命令检测
# =============================================================================

# 检查命令是否存在
# 参数: $1=命令名
# 返回: 0=存在  1=不存在
util_cmd_exists() {
    command -v "$1" &>/dev/null
}

# 检查多个命令是否全部存在
# 参数: $@=命令名列表
# 返回: 0=全存在  1=有缺失
util_cmds_exist() {
    local missing=()
    local cmd
    for cmd in "$@"; do
        util_cmd_exists "${cmd}" || missing+=("${cmd}")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_debug "缺少命令: ${missing[*]}"
        return 1
    fi
    return 0
}

# 获取命令版本号（第一行第一个类似版本的字符串）
# 参数: $1=命令  $2=版本参数（默认 --version）
util_cmd_version() {
    local cmd="$1"
    local flag="${2:---version}"
    "${cmd}" "${flag}" 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1
}

# =============================================================================
# 5. 服务与进程
# =============================================================================

# 检查服务是否正在运行
# 参数: $1=服务名（systemd unit）
util_service_running() {
    systemctl is-active --quiet "$1" 2>/dev/null
}

# 检查端口是否被监听
# 参数: $1=端口号
util_port_listening() {
    ss -tlnp 2>/dev/null | grep -q ":${1}\b" || \
    netstat -tlnp 2>/dev/null | grep -q ":${1}\b"
}

# =============================================================================
# 6. 数字与单位
# =============================================================================

# 将字节数转为人类可读格式（KB/MB/GB）
# 参数: $1=字节数
util_human_size() {
    local bytes="$1"
    if   (( bytes >= 1073741824 )); then
        printf "%.1fGB" "$(echo "scale=1; ${bytes}/1073741824" | bc 2>/dev/null || echo 0)"
    elif (( bytes >= 1048576 )); then
        printf "%.1fMB" "$(echo "scale=1; ${bytes}/1048576" | bc 2>/dev/null || echo 0)"
    elif (( bytes >= 1024 )); then
        printf "%.1fKB" "$(echo "scale=1; ${bytes}/1024" | bc 2>/dev/null || echo 0)"
    else
        printf "%dB" "${bytes}"
    fi
}

# 将 "4G"/"2048M" 类字符串解析为 MB 数
# 参数: $1=大小字符串（如 2G, 512M, 1024K）
util_parse_size_mb() {
    local s="${1^^}"
    local n="${s//[^0-9]/}"
    case "${s: -1}" in
        G) echo $(( n * 1024 ))  ;;
        M) echo "${n}"           ;;
        K) echo $(( n / 1024 ))  ;;
        *) echo "${n}"           ;;
    esac
}

# =============================================================================
# 7. 输入校验
# =============================================================================

# 校验字符串是否为合法的 IPv4 地址
# 参数: $1=字符串
util_is_ipv4() {
    local ip="$1"
    local regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    [[ "${ip}" =~ ${regex} ]] || return 1
    local IFS=.
    # shellcheck disable=SC2206
    local -a parts=( ${ip} )
    local p
    for p in "${parts[@]}"; do
        (( p < 0 || p > 255 )) && return 1
    done
    return 0
}

# 校验端口号是否合法（1-65535）
# 参数: $1=端口号
util_is_valid_port() {
    local port="$1"
    [[ "${port}" =~ ^[0-9]+$ ]] || return 1
    (( port >= 1 && port <= 65535 ))
}

# 校验用户名是否合法（字母数字下划线，3-32位）
# 参数: $1=用户名
util_is_valid_username() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]{2,31}$ ]]
}

# =============================================================================
# 8. 执行控制
# =============================================================================

# 带超时的命令执行
# 参数: $1=超时秒数 $2..=命令及参数
# 返回: 命令退出码，超时返回 124
util_run_timeout() {
    local timeout_s="$1"
    shift
    timeout "${timeout_s}" "$@"
}

# 带重试的命令执行
# 参数: $1=最大重试次数 $2=重试间隔(s) $3..=命令
# 返回: 0=成功  1=全部失败
util_run_retry() {
    local max_tries="$1"
    local interval="$2"
    shift 2
    local i=1

    while (( i <= max_tries )); do
        "$@" && return 0
        log_debug "命令失败 (${i}/${max_tries})，${interval}s 后重试: $*"
        (( i++ ))
        sleep "${interval}"
    done

    log_error "命令在 ${max_tries} 次尝试后仍失败: $*"
    return 1
}

# dry-run 安全包装：UBINIT_DRY_RUN=true 时只打印命令不执行
# 参数: $@=命令
util_run() {
    if [[ "${UBINIT_DRY_RUN:-false}" == "true" ]]; then
        log_debug "[DRY-RUN] 跳过执行: $*"
        return 0
    fi
    "$@"
}

# =============================================================================
# 9. 杂项
# =============================================================================

# 生成随机密码（字母+数字，默认 16 位）
# 参数: $1=长度（默认 16）
util_random_password() {
    local len="${1:-16}"
    # 使用 printf 避免 head -c 截断后末尾可能无换行的问题
    # tr 生成字符流，head -c 精确截取，不额外输出换行
    tr -dc 'A-Za-z0-9@#%^&*' < /dev/urandom 2>/dev/null | head -c "${len}"
    printf '\n'
}

# 获取本机主 IP 地址
util_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || \
    ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $7}' || \
    echo "Unknown"
}

# 格式化秒数为 时:分:秒
# 参数: $1=秒数
util_format_duration() {
    local secs="$1"
    printf '%02d:%02d:%02d' \
        "$(( secs / 3600 ))" \
        "$(( (secs % 3600) / 60 ))" \
        "$(( secs % 60 ))"
}
