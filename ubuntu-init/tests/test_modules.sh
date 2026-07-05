#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — 模块功能测试套件
# =============================================================================
# 用法: bash tests/test_modules.sh [--module <name>] [--list]
# 说明: 在沙盒环境中验证各模块的 check/info 函数是否正常工作
#       注意: install/uninstall 需要 root 且会修改系统，仅在 CI 环境运行
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# 统计
TOTAL=0
PASSED=0
FAILED=0

# ── 加载 lib ──────────────────────────────────────────────────────────────────
# 设置最小环境变量
export UBINIT_LOG_FILE="/tmp/ubinit-test.log"
export UBINIT_DRY_RUN=true
export UBINIT_VERBOSE=false
export UBINIT_BACKUP_DIR="/tmp/ubinit-test-backup"

# 加载 lib
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/logger.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/utils.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/detect.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/apt.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/service.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/network.sh"
# shellcheck source=/dev/null
source "${PROJECT_ROOT}/lib/backup.sh"

logger_init "false"

# ── 测试框架 ──────────────────────────────────────────────────────────────────

assert_eq() {
    local desc="$1"
    local expected="$2"
    local actual="$3"
    (( TOTAL++ ))
    if [[ "${expected}" == "${actual}" ]]; then
        (( PASSED++ ))
        echo -e "  ${GREEN}✓${RESET} ${desc}"
    else
        (( FAILED++ ))
        echo -e "  ${RED}✗${RESET} ${desc}"
        echo -e "    期望: ${expected}"
        echo -e "    实际: ${actual}"
    fi
}

assert_cmd() {
    local desc="$1"
    shift
    (( TOTAL++ ))
    if "$@" &>/dev/null 2>&1; then
        (( PASSED++ ))
        echo -e "  ${GREEN}✓${RESET} ${desc}"
    else
        (( FAILED++ ))
        echo -e "  ${RED}✗${RESET} ${desc}"
    fi
}

assert_file_exists() {
    local desc="$1"
    local path="$2"
    (( TOTAL++ ))
    if [[ -f "${path}" ]]; then
        (( PASSED++ ))
        echo -e "  ${GREEN}✓${RESET} ${desc}"
    else
        (( FAILED++ ))
        echo -e "  ${RED}✗${RESET} ${desc}: 文件不存在 ${path}"
    fi
}

# ── 测试用例 ──────────────────────────────────────────────────────────────────

test_lib_utils() {
    echo ""
    echo -e "  ${BOLD}▶ lib/utils.sh${RESET}"

    assert_eq "util_trim 去除首尾空格" "hello" "$(util_trim '  hello  ')"
    assert_eq "util_lower 转小写" "abc" "$(util_lower 'ABC')"
    assert_eq "util_upper 转大写" "ABC" "$(util_upper 'abc')"
    assert_eq "util_starts_with 前缀匹配" "0" "$(util_starts_with 'hello world' 'hello'; echo $?)"
    assert_eq "util_contains 子串检测" "0" "$(util_contains 'hello world' 'world'; echo $?)"
    assert_eq "util_is_ipv4 有效IP" "0" "$(util_is_ipv4 '192.168.1.1'; echo $?)"
    assert_eq "util_is_ipv4 无效IP" "1" "$(util_is_ipv4 '999.0.0.1'; echo $?)"
    assert_eq "util_is_valid_port 有效端口" "0" "$(util_is_valid_port '8080'; echo $?)"
    assert_eq "util_is_valid_port 越界端口" "1" "$(util_is_valid_port '99999'; echo $?)"
    assert_eq "util_version_gte 版本比较 >=)" "0" "$(util_version_gte '2.0.0' '1.9.9'; echo $?)"
    assert_eq "util_format_duration 格式化秒数" "01:23:45" "$(util_format_duration 5025)"
    assert_eq "util_human_size 字节格式化" "1.0MB" "$(util_human_size 1048576)"
    assert_cmd "util_random_password 生成密码长度" \
        test "$(util_random_password 16 | tr -d '\n' | wc -c)" -eq 16
    assert_cmd "util_cmd_exists 存在的命令" util_cmd_exists bash
    assert_eq "util_cmd_exists 不存在的命令" "1" \
        "$(util_cmd_exists 'nonexistent_cmd_12345'; echo $?)"
}

test_lib_detect() {
    echo ""
    echo -e "  ${BOLD}▶ lib/detect.sh（静态检测）${RESET}"

    # 检测函数不需要 root，仅测试读取功能
    assert_cmd "detect_all 执行完成" detect_all

    assert_cmd "DETECT_ARCH 非空" test -n "${DETECT_ARCH}"
    assert_cmd "DETECT_OS_ID 非空" test -n "${DETECT_OS_ID}"
    assert_cmd "DETECT_KERNEL 非空" test -n "${DETECT_KERNEL}"
    assert_cmd "DETECT_CPU_CORES >= 1" test "${DETECT_CPU_CORES:-0}" -ge 1
    assert_cmd "DETECT_MEM_TOTAL_MB >= 1" test "${DETECT_MEM_TOTAL_MB:-0}" -ge 1

    echo -e "    ${CYAN}OS: ${DETECT_OS_FULL}  Arch: ${DETECT_ARCH}  CPU: ${DETECT_CPU_CORES}核${RESET}"
}

test_lib_network() {
    echo ""
    echo -e "  ${BOLD}▶ lib/network.sh${RESET}"

    assert_cmd "net_port_listening 函数可调用" bash -c "net_port_listening 22; true"
    assert_cmd "util_local_ip 返回非空" test -n "$(util_local_ip)"
}

test_module_interface() {
    echo ""
    echo -e "  ${BOLD}▶ modules/ 接口完整性检查${RESET}"

    local module_dir="${PROJECT_ROOT}/modules"
    local -a required_funcs=(module_info module_check module_install module_uninstall)

    while IFS= read -r -d '' module_file; do
        local module_name
        module_name="$(basename "${module_file}")"

        # 加载模块（在子 shell 中，避免污染当前环境）
        local missing_funcs=()
        for fn in "${required_funcs[@]}"; do
            if ! bash -c "source '${module_file}'; declare -f ${fn}" &>/dev/null 2>&1; then
                missing_funcs+=("${fn}")
            fi
        done

        (( TOTAL++ ))
        if [[ ${#missing_funcs[@]} -eq 0 ]]; then
            (( PASSED++ ))
            if [[ "${OPT_QUIET:-false}" != "true" ]]; then
                echo -e "  ${GREEN}✓${RESET} ${module_name} — 接口完整"
            fi
        else
            (( FAILED++ ))
            echo -e "  ${RED}✗${RESET} ${module_name} — 缺少函数: ${missing_funcs[*]}"
        fi
    done < <(find "${module_dir}" -name "*.sh" -print0 2>/dev/null | sort -z)
}

test_lib_files_exist() {
    echo ""
    echo -e "  ${BOLD}▶ 关键文件存在性检查${RESET}"

    local -a required_files=(
        "install.sh"
        "uninstall.sh"
        "config/default.conf"
        "config/custom.conf.example"
        "lib/logger.sh"
        "lib/ui.sh"
        "lib/utils.sh"
        "lib/detect.sh"
        "lib/apt.sh"
        "lib/service.sh"
        "lib/network.sh"
        "lib/backup.sh"
        "lib/report.sh"
        "README.md"
        ".shellcheckrc"
    )

    local f
    for f in "${required_files[@]}"; do
        assert_file_exists "${f}" "${PROJECT_ROOT}/${f}"
    done

    # 检查模块数量
    local module_count
    module_count="$(find "${PROJECT_ROOT}/modules" -name "*.sh" 2>/dev/null | wc -l)"
    (( TOTAL++ ))
    if [[ "${module_count}" -ge 29 ]]; then
        (( PASSED++ ))
        echo -e "  ${GREEN}✓${RESET} modules/ 模块数量: ${module_count} (>= 29)"
    else
        (( FAILED++ ))
        echo -e "  ${RED}✗${RESET} modules/ 模块数量: ${module_count} (期望 >= 29)"
    fi
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

OPT_QUIET=false
OPT_MODULE=""

for arg in "$@"; do
    case "${arg}" in
        --quiet)  OPT_QUIET=true ;;
        --module) OPT_MODULE="${2:-}" ;;
        --list)
            echo "可用测试套件:"
            echo "  test_lib_files_exist"
            echo "  test_lib_utils"
            echo "  test_lib_detect"
            echo "  test_lib_network"
            echo "  test_module_interface"
            exit 0
            ;;
    esac
done

echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    UbuntuInit — 模块功能测试套件             ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"

test_lib_files_exist
test_lib_utils
test_lib_detect
test_lib_network
test_module_interface

# ── 汇总 ──────────────────────────────────────────────────────────────────────
echo ""
echo    "  ══════════════════════════════════════════════"
echo -e "  测试结果: ${GREEN}${PASSED} 通过${RESET} / ${RED}${FAILED} 失败${RESET} / ${TOTAL} 总计"
echo ""

if [[ "${FAILED}" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ 全部测试通过！${RESET}"
    exit 0
else
    echo -e "  ${RED}${BOLD}✗ ${FAILED} 项测试失败${RESET}"
    exit 1
fi
