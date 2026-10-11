#!/usr/bin/env bash
# verify-ak3-zip.sh —— AnyKernel3 ZIP 合规自检
#
# 背景：上游 ksud 已加固 AnyKernel3 ZIP 校验（见 userspace/ksud/ANYKERNEL3.md）。
# 生成一个"刷不进去"的包是最难查的故障之一，所以在 CI 里就把关。
#
# 校验项：
#   1. META-INF/com/google/android/update-binary 恰好 1 个
#   2. 顶层存在 anykernel.sh
#   3. 无重复条目
#   4. 无绝对路径 / ../ 穿越
#   5. 顶层无 module.prop（模块 ZIP 混入）
#   6. update-binary 体积 <= 4 MiB
#
# 用法: verify-ak3-zip.sh <path/to/xxx.zip>
# 退出码: 0 通过 / 1 不合规（并打印具体原因）

set -uo pipefail

ZIP="${1:-}"
if [ -z "$ZIP" ]; then
  echo "::error::用法: $0 <path/to/anykernel3.zip>"
  exit 1
fi
if [ ! -f "$ZIP" ]; then
  echo "::error::找不到文件: $ZIP"
  exit 1
fi

echo "==> AK3 ZIP 合规自检: $ZIP"
ENTRIES="$(unzip -Z1 "$ZIP")" || { echo "::error::不是有效的 zip"; exit 1; }
printf '%s\n' "$ENTRIES" | head -40

# 1) update-binary 恰好 1 个
UBC="$(printf '%s\n' "$ENTRIES" | grep -c '^META-INF/com/google/android/update-binary$' || true)"
echo "update-binary 数量: $UBC"
if [ "$UBC" != "1" ]; then
  echo "::error::update-binary 数量应为 1，实际 $UBC"
  exit 1
fi

# 2) 顶层 anykernel.sh 必须存在
if ! printf '%s\n' "$ENTRIES" | grep -qx 'anykernel.sh'; then
  echo "::error::缺少顶层 anykernel.sh"
  exit 1
fi

# 3) 不允许重复条目
DUPS="$(printf '%s\n' "$ENTRIES" | sort | uniq -d || true)"
if [ -n "$DUPS" ]; then
  echo "::error::ZIP 内存在重复条目："
  printf '%s\n' "$DUPS"
  exit 1
fi

# 4) 不允许绝对路径或 ../ 穿越
if printf '%s\n' "$ENTRIES" | grep -qE '^/|(^|/)\.\./'; then
  echo "::error::ZIP 内存在绝对路径或 ../ 穿越条目"
  printf '%s\n' "$ENTRIES" | grep -E '^/|(^|/)\.\./'
  exit 1
fi

# 5) 不允许混入模块 ZIP
if printf '%s\n' "$ENTRIES" | grep -qi '^module\.prop$'; then
  echo "::error::ZIP 顶层出现 module.prop（模块 ZIP 混入）"
  exit 1
fi

# 6) 安装脚本体积 <= 4 MiB
UB_SIZE="$(unzip -l "$ZIP" 'META-INF/com/google/android/update-binary' | awk 'NR>3{print $1}' | head -1)"
echo "update-binary 大小: ${UB_SIZE:-0} bytes"
if [ -n "$UB_SIZE" ] && [ "$UB_SIZE" -gt 4194304 ]; then
  echo "::error::update-binary 超过 4 MiB（$UB_SIZE bytes）"
  exit 1
fi

echo "OK: AK3 ZIP 通过合规自检"
