#!/usr/bin/env bash
# =============================================================================
# UbuntuInit — ShellCheck 代码质量检查脚本
# =============================================================================
# 用法: bash tests/shellcheck.sh [--fix] [--quiet]
# 说明: 对项目所有 .sh 文件执行 ShellCheck 静态分析
# =============================================================================

set -euo pipefail

# ── 路径定位 ──────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── 颜色定义 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ── 统计计数器 ────────────────────────────────────────────────────────────────
TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0
WARNINGS=0

# ── 参数解析 ──────────────────────────────────────────────────────────────────
OPT_QUIET=false
OPT_STRICT=false   # strict: 将 WARNING 也视为失败

for arg in "$@"; do
    case "${arg}" in
        --quiet)  OPT_QUIET=true  ;;
        --strict) OPT_STRICT=true ;;
        --help)
            echo "用法: bash tests/shellcheck.sh [--quiet] [--strict]"
            echo "  --quiet   只输出错误，不显示通过的文件"
            echo "  --strict  将 WARNING 也视为失败"
            exit 0
            ;;
    esac
done

# ── 打印横幅 ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}${CYAN}║    UbuntuInit — ShellCheck 代码质量检查      ║${RESET}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════╝${RESET}"
echo ""

# ── 前置检查：确认 ShellCheck 已安装 ─────────────────────────────────────────
if ! command -v shellcheck &>/dev/null; then
    echo -e "${RED}✗ ShellCheck 未安装${RESET}"
    echo ""
    echo "安装方法:"
    echo "  Ubuntu/Debian: sudo apt install shellcheck"
    echo "  macOS:         brew install shellcheck"
    echo "  其他:          https://github.com/koalaman/shellcheck#installing"
    exit 1
fi

SHELLCHECK_VER="$(shellcheck --version | grep 'version:' | awk '{print $2}')"
echo -e "  ShellCheck 版本: ${CYAN}${SHELLCHECK_VER}${RESET}"
echo -e "  项目根目录:      ${CYAN}${PROJECT_ROOT}${RESET}"
echo ""

# ── 收集待检查文件 ────────────────────────────────────────────────────────────
declare -a SHELL_FILES=()

# 主要脚本
for f in \
    "${PROJECT_ROOT}/install.sh" \
    "${PROJECT_ROOT}/uninstall.sh" \
    "${PROJECT_ROOT}/demo_ui.sh"; do
    [[ -f "${f}" ]] && SHELL_FILES+=("${f}")
done

# lib 目录
while IFS= read -r -d '' f; do
    SHELL_FILES+=("${f}")
done < <(find "${PROJECT_ROOT}/lib" -name "*.sh" -print0 2>/dev/null | sort -z)

# modules 目录
while IFS= read -r -d '' f; do
    SHELL_FILES+=("${f}")
done < <(find "${PROJECT_ROOT}/modules" -name "*.sh" -print0 2>/dev/null | sort -z)

# tests 目录（排除自身）
while IFS= read -r -d '' f; do
    [[ "${f}" == "${BASH_SOURCE[0]}" ]] && continue
    SHELL_FILES+=("${f}")
done < <(find "${PROJECT_ROOT}/tests" -name "*.sh" -print0 2>/dev/null | sort -z)

echo -e "  待检查文件: ${BOLD}${#SHELL_FILES[@]} 个${RESET}"
echo ""
echo -e "  ${BOLD}文件名                          状态${RESET}"
echo    "  ──────────────────────────────  ──────────────────────"

# ── ShellCheck 选项 ───────────────────────────────────────────────────────────
# -x : 跟踪 source/. 引用（允许引用外部文件）
# -s bash : 明确指定 bash 语法
# -e SC1091 : 忽略无法解析的 source 文件
SC_OPTS=(-x -s bash -e SC1091)

# ── 执行检查循环 ──────────────────────────────────────────────────────────────
declare -a FAILED_FILES=()
declare -a WARNING_FILES=()

for filepath in "${SHELL_FILES[@]}"; do
    (( TOTAL++ ))

    # 获取相对路径（用于显示）
    local_path="${filepath#"${PROJECT_ROOT}/"}"
    # 对齐显示（左侧最多 32 字符）
    display_name="$(printf '%-32s' "${local_path}")"

    # 执行 shellcheck（捕获退出码）
    sc_output="$(shellcheck "${SC_OPTS[@]}" "${filepath}" 2>&1)"
    sc_exit=$?

    if [[ "${sc_exit}" -eq 0 ]]; then
        (( PASSED++ ))
        if [[ "${OPT_QUIET}" != "true" ]]; then
            echo -e "  ${display_name}  ${GREEN}✓ 通过${RESET}"
        fi
    else
        # 判断是否只有 WARNING（exit=1）还是有 ERROR（exit>=2）
        if echo "${sc_output}" | grep -q "warning:"; then
            (( WARNINGS++ ))
            if [[ "${OPT_STRICT}" == "true" ]]; then
                (( FAILED++ ))
                FAILED_FILES+=("${local_path}")
                echo -e "  ${display_name}  ${YELLOW}⚠ 警告${RESET}"
            else
                echo -e "  ${display_name}  ${YELLOW}⚠ 警告${RESET}"
                WARNING_FILES+=("${local_path}")
            fi
        else
            (( FAILED++ ))
            FAILED_FILES+=("${local_path}")
            echo -e "  ${display_name}  ${RED}✗ 错误${RESET}"
        fi
    fi
done

# ── 汇总报告 ──────────────────────────────────────────────────────────────────
echo ""
echo    "  ══════════════════════════════════════════════"
echo -e "  检查结果汇总:"
echo ""
echo -e "    总计文件:  ${BOLD}${TOTAL}${RESET}"
echo -e "    通过:      ${GREEN}${BOLD}${PASSED}${RESET}"
echo -e "    警告:      ${YELLOW}${BOLD}${WARNINGS}${RESET}"
echo -e "    错误:      ${RED}${BOLD}${FAILED}${RESET}"
echo ""

# 打印失败文件详情
if [[ ${#FAILED_FILES[@]} -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}存在错误的文件：${RESET}"
    for f in "${FAILED_FILES[@]}"; do
        echo -e "    ${RED}✗ ${f}${RESET}"
        # 重新运行以显示详细错误
        echo "  ────────────────────────────────────────────"
        shellcheck "${SC_OPTS[@]}" "${PROJECT_ROOT}/${f}" 2>&1 | \
            sed 's/^/    /' || true
        echo ""
    done
fi

if [[ ${#WARNING_FILES[@]} -gt 0 ]] && [[ "${OPT_QUIET}" != "true" ]]; then
    echo -e "  ${YELLOW}${BOLD}存在警告的文件：${RESET}"
    for f in "${WARNING_FILES[@]}"; do
        echo -e "    ${YELLOW}⚠ ${f}${RESET}"
    done
    echo ""
fi

# ── 最终结论 ──────────────────────────────────────────────────────────────────
echo ""
if [[ "${FAILED}" -eq 0 ]]; then
    echo -e "  ${GREEN}${BOLD}✓ 所有文件通过 ShellCheck 检查！${RESET}"
    echo ""
    exit 0
else
    echo -e "  ${RED}${BOLD}✗ 发现 ${FAILED} 个文件存在问题，请修复后再提交。${RESET}"
    echo ""
    exit 1
fi
