#!/usr/bin/env bash
# ============================================================================
# apply-tweaks.sh —— 按档位把 kernel-tweaks.json 里的调优项写进 .config
#
# 用法：
#   bash scripts/apply-tweaks.sh <level> [config_path] [json_path]
#     level       : none | safe | smart
#     config_path : 默认 ./.config
#     json_path   : 默认 ./config/kernel-tweaks.json
#
# 设计要点：
#   * 只做「存在性检查 + 逐项应用」，不存在的配置项跳过并计数，绝不中断构建。
#   * 不使用 set -e，因为单条 scripts/config 失败不应终止整体流程。
#   * 环境变量 GITHUB_STEP_SUMMARY 存在时输出 markdown 摘要表。
# ============================================================================

set -uo pipefail

LEVEL="${1:-none}"
CONFIG="${2:-./.config}"
TWEAKS_JSON="${3:-./config/kernel-tweaks.json}"

echo "=============================================="
echo " 内核调优档位 : $LEVEL"
echo " 目标 .config : $CONFIG"
echo " 调优清单     : $TWEAKS_JSON"
echo "=============================================="

if [ "$LEVEL" = "none" ]; then
  echo "档位为 none —— 保持 AOSP GKI 原样，不做任何调优。"
  exit 0
fi

if [ ! -f "$CONFIG" ]; then
  echo "::error::$CONFIG 不存在，请先执行 make gki_defconfig"
  exit 1
fi

if [ ! -f "$TWEAKS_JSON" ]; then
  echo "::error::找不到调优清单 $TWEAKS_JSON，跳过调优。"
  exit 0
fi

# ---------------------------------------------------------------------------
# 用 python 把 JSON 摊平成 "level<TAB>group<TAB>config<TAB>action<TAB>value" 行
# 这样 bash 侧只做简单字段切分，避免引入 jq 依赖。
# ---------------------------------------------------------------------------
TMP_TSV="$(mktemp)"
trap 'rm -f "$TMP_TSV"' EXIT

python3 - "$TWEAKS_JSON" "$LEVEL" > "$TMP_TSV" <<'PYEOF'
import json, sys

json_path, level = sys.argv[1], sys.argv[2]
with open(json_path, encoding="utf-8") as f:
    data = json.load(f)

if level == "none":
    sys.exit(0)

if level == "safe":
    levels = ["safe"]
elif level == "smart":
    # smart 档在 safe 之上叠加
    levels = ["safe", "smart"]
else:
    print("unknown-level", file=sys.stderr)
    sys.exit(2)

for lvl in levels:
    for item in data.get(lvl, []):
        group = str(item.get("group", "-")).replace("\t", " ")
        cfg = str(item.get("config", "")).strip()
        act = str(item.get("action", "enable")).strip()
        val = str(item.get("value", "")).replace("\t", " ")
        why = str(item.get("why", "")).replace("\t", " ")
        risk = str(item.get("risk", "-")).replace("\t", " ")
        if not cfg:
            continue
        print("\t".join([lvl, group, cfg, act, val, risk, why]))
PYEOF

if [ ! -s "$TMP_TSV" ]; then
  echo "::warning::档位 '$LEVEL' 未解析出任何调优项。"
  exit 0
fi

# ---------------------------------------------------------------------------
# 逐项应用
# ---------------------------------------------------------------------------
TOTAL=0; OK=0; SKIP=0; FAIL=0
declare -A GROUP_OK GROUP_SKIP

SUMMARY_ROWS=""

while IFS=$'\t' read -r lvl group cfg act val risk why; do
  [ -n "$cfg" ] || continue
  TOTAL=$((TOTAL + 1))

  # 配置项是否存在（在 .config 里出现过，或者 Kconfig 树里认这个符号）
  # scripts/config 对不存在的符号会静默忽略，因此先查 .config 是否含该符号。
  if ! grep -qE "^(# )?CONFIG_${cfg}[= ]" "$CONFIG"; then
    # 从未出现过 —— 该 KMI 没有这个选项，跳过
    printf '  [跳过] %-34s (本内核无此项)\n' "$cfg"
    SKIP=$((SKIP + 1))
    GROUP_SKIP["$group"]=$(( ${GROUP_SKIP["$group"]:-0} + 1 ))
    continue
  fi

  case "$act" in
    enable)
      if scripts/config --file "$CONFIG" -e "$cfg"; then
        printf '  [启用] %-34s %s\n' "$cfg" "$why"
        OK=$((OK + 1))
        GROUP_OK["$group"]=$(( ${GROUP_OK["$group"]:-0} + 1 ))
      else
        printf '  [失败] %-34s\n' "$cfg"
        FAIL=$((FAIL + 1))
      fi
      ;;
    disable)
      if scripts/config --file "$CONFIG" -d "$cfg"; then
        printf '  [关闭] %-34s %s\n' "$cfg" "$why"
        OK=$((OK + 1))
        GROUP_OK["$group"]=$(( ${GROUP_OK["$group"]:-0} + 1 ))
      else
        printf '  [失败] %-34s\n' "$cfg"
        FAIL=$((FAIL + 1))
      fi
      ;;
    set)
      if [ -z "$val" ]; then
        printf '  [跳过] %-34s (set 但缺 value)\n' "$cfg"
        SKIP=$((SKIP + 1))
        continue
      fi
      if scripts/config --file "$CONFIG" --set-val "$cfg" "$val"; then
        printf '  [设为] %-34s = %-6s %s\n' "$cfg" "$val" "$why"
        OK=$((OK + 1))
        GROUP_OK["$group"]=$(( ${GROUP_OK["$group"]:-0} + 1 ))
      else
        printf '  [失败] %-34s\n' "$cfg"
        FAIL=$((FAIL + 1))
      fi
      ;;
    *)
      printf '  [跳过] %-34s (未知 action: %s)\n' "$cfg" "$act"
      SKIP=$((SKIP + 1))
      ;;
  esac
done < "$TMP_TSV"

echo "----------------------------------------------"
echo " 调优汇总：共 $TOTAL 项 / 应用 $OK / 跳过 $SKIP / 失败 $FAIL"

# ---------------------------------------------------------------------------
# GitHub Actions 步骤摘要
# ---------------------------------------------------------------------------
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### 内核调优档位：\`$LEVEL\`"
    echo
    echo "| 分组 | 已应用 | 本内核不支持 |"
    echo "|---|---|---|"
    for g in "${!GROUP_OK[@]}"; do
      echo "| $g | ${GROUP_OK[$g]} | ${GROUP_SKIP[$g]:-0} |"
    done
    for g in "${!GROUP_SKIP[@]}"; do
      [ -n "${GROUP_OK[$g]:-}" ] || echo "| $g | 0 | ${GROUP_SKIP[$g]} |"
    done
    echo
    echo "> 共 $TOTAL 项，应用 **$OK**，跳过 $SKIP，失败 $FAIL"
    echo "> 跳过项表示当前 KMI 的 Kconfig 里不存在该符号，属正常现象。"
    echo
  } >> "$GITHUB_STEP_SUMMARY"
fi

# 有失败也不中断构建 —— 调优属锦上添花，不该拖垮主流程
if [ "$FAIL" -gt 0 ]; then
  echo "::warning::有 $FAIL 项调优未能应用，但不影响构建继续。"
fi

exit 0
