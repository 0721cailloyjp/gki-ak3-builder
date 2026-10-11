#!/usr/bin/env bash
# ============================================================================
# apply-extras.sh —— 应用「附加内核功能」（BBG / 网络增强 / ZRAM LZ4KD）
#
# 用法：
#   bash scripts/apply-extras.sh <feature> <kernel_version> [kern_root]
#     feature        : bbg | networking | zram
#     kernel_version : 5.10 | 5.15 | 6.1 | 6.6 | 6.12 | 6.18
#     kern_root      : 内核源码根（默认 .）
#   bash scripts/apply-extras.sh list          # 打印支持矩阵（调试用）
#
# 设计要点（与 apply-tweaks.sh 保持一致）：
#   * set -uo pipefail，【刻意不用 -e】：单个功能失败不应拖垮整体构建。
#   * 支持矩阵来自 config/kernel-extras.json，脚本内【不硬编码】KMI 判断。
#   * 补丁先 dry-run，失败则跳过并 warning，绝不把半个补丁留在树里。
#   * 每个功能结束都写一份 .extras-state/<feature>.state 供后续步骤判断。
#
# 退出码：0 = 成功或被正常跳过；非 0 仅用于「脚本自身用法错误」。
# ============================================================================

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_JSON="${EXTRAS_JSON:-$HERE/../config/kernel-extras.json}"

FEATURE="${1:-}"
KV="${2:-}"
KERN_ROOT="${3:-.}"

PY="${PYTHON_BIN:-python3}"

# ---------------------------------------------------------------------------
# 从 JSON 里取某功能的字段（避免依赖 jq）
#   query <json> <feature> <dotted.path>
# ---------------------------------------------------------------------------
extras_query() {
  local json="$1" feat="$2" path="$3"
  "$PY" - "$json" "$feat" "$path" <<'PYEOF'
import json, sys

json_path, feat, dotted = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)

item = None
for e in data.get("extras", []):
    if e.get("id") == feat:
        item = e
        break
if item is None:
    print("")
    sys.exit(0)

cur = item
for part in dotted.split("."):
    if isinstance(cur, dict) and part in cur:
        cur = cur[part]
    else:
        print("")
        sys.exit(0)

if isinstance(cur, (dict, list)):
    print(json.dumps(cur, ensure_ascii=False))
else:
    print(cur)
PYEOF
}

# 查询 kmi_support 里某内核版本的支持状态
#   返回值：p|true | p|false | p|partial | p|all | p|（空=未声明）
support_of() {
  local feat="$1" kv="$2"
  "$PY" - "$ROOT_JSON" "$feat" "$kv" <<'PYEOF'
import json, sys

json_path, feat, kv = sys.argv[1], sys.argv[2], sys.argv[3]
try:
    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    print("")
    sys.exit(0)

for e in data.get("extras", []):
    if e.get("id") == feat:
        sup = e.get("kmi_support", {})
        break
else:
    print("")
    sys.exit(0)

if sup.get("all") is True:
    print("all")
    sys.exit(0)

v = sup.get(kv, None)
if v is True or v == "true":
    print("true")
elif v is False or v == "false":
    print("false")
elif isinstance(v, str):
    print(v)
else:
    print("")
PYEOF
}

STATE_DIR="${EXTRAS_STATE_DIR:-$PWD/.extras-state}"
mkdir -p "$STATE_DIR"

write_state() {
  # write_state <feature> <applied:true/false> <reason>
  printf 'applied=%s\nreason=%s\nkv=%s\n' "$2" "$3" "${KV:-}" > "$STATE_DIR/$1.state"
  echo "    [state] $1 -> applied=$2 ($3)"
}

# ---------------------------------------------------------------------------
list_matrix() {
  if [ ! -f "$ROOT_JSON" ]; then
    echo "::error::找不到 $ROOT_JSON"; exit 1
  fi
  echo "附加功能支持矩阵（来自 $ROOT_JSON）："
  "$PY" - "$ROOT_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
kvs = ["5.10", "5.15", "6.1", "6.6", "6.12", "6.18"]
print("  %-14s %-18s %s" % ("id", "input", " ".join("%6s" % k for k in kvs)))
for e in data.get("extras", []):
    sup = e.get("kmi_support", {})
    cells = []
    for k in kvs:
        if sup.get("all") is True:
            cells.append("  yes ")
        else:
            v = sup.get(k)
            if v is True:
                cells.append("  yes ")
            elif v == "partial":
                cells.append(" part ")
            elif v is False:
                cells.append("  no  ")
            else:
                cells.append("  -   ")
    print("  %-14s %-18s %s" % (e.get("id", "?"), e.get("input", "?"), " ".join(cells)))
PYEOF
}

# ---------------------------------------------------------------------------
# 通用：下载一个 raw 文件
#   fetch_raw <repo> <ref> <path> <out>
# ---------------------------------------------------------------------------
fetch_raw() {
  local repo="$1" ref="$2" path="$3" out="$4"
  local url="https://raw.githubusercontent.com/$repo/$ref/$path"
  if curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors --connect-timeout 20 \
       "$url" -o "$out"; then
    # 防假阴性：raw 被代理拦截时可能返回空文件
    if [ ! -s "$out" ] || [ "$(wc -c < "$out")" -lt 200 ]; then
      echo "    [warn] $url 下载过小（$(wc -c < "$out" 2>/dev/null || echo 0) B），视为失败"
      rm -f "$out"
      return 1
    fi
    return 0
  fi
  return 1
}

# 通用：dry-run 后再应用补丁
#   apply_patch <patch_file> <workdir>
apply_patch() {
  local pf="$1" wd="$2"
  if [ ! -f "$pf" ]; then
    echo "    [warn] 补丁不存在: $pf"
    return 1
  fi
  if patch -p1 --dry-run -d "$wd" < "$pf" >/dev/null 2>&1; then
    patch -p1 --forward --no-backup-if-mismatch -d "$wd" < "$pf" && return 0
    echo "    [warn] 补丁 $pf 应用阶段失败"
    return 1
  fi
  echo "    [warn] 补丁 $pf dry-run 未通过（源码结构可能不匹配），跳过"
  return 2
}

# 通用：安全的 defconfig 追加/覆盖（幂等）
#   set_defconfig <defconfig> <KEY> <VALUE>
set_defconfig() {
  local dc="$1" key="$2" val="$3"
  if grep -qE "^$key=" "$dc" 2>/dev/null; then
    sed -i "s|^$key=.*|$key=$val|g" "$dc"
  elif grep -qE "^# $key is not set" "$dc" 2>/dev/null; then
    sed -i "s|^# $key is not set|$key=$val|g" "$dc"
  else
    echo "$key=$val" >> "$dc"
  fi
}

# ===========================================================================
# 功能 1：BBG 防格机
# ===========================================================================
do_bbg() {
  echo "==> [BBG] Baseband-guard 防格机补丁"
  local sup
  sup="$(support_of bbg "$KV")"
  if [ -z "$sup" ] || [ "$sup" = "false" ]; then
    echo "::notice::BBG 在 $KV 上不受支持（kmi_support 未声明），跳过。"
    write_state bbg false "kmi-unsupported"
    return 0
  fi

  if [ ! -d "$KERN_ROOT/security" ] && [ ! -d "$KERN_ROOT/common/security" ]; then
    echo "    [warn] 找不到 security/ 目录，跳过 BBG"
    write_state bbg false "no-security-dir"
    return 0
  fi

  # 上游 setup.sh 必须在 kernel 树根跑（它会自己判断 security/ 还是 common/security/）
  if [ -f "$KERN_ROOT/setup.sh" ]; then
    echo "    [warn] kernel 树里已有 setup.sh，BBG 会覆盖它，先备份"
    cp -f "$KERN_ROOT/setup.sh" "$KERN_ROOT/setup.sh.bak.extras" 2>/dev/null || true
  fi

  local bbg_sh="/tmp/bbg_setup.sh"
  if ! fetch_raw "vc-teahouse/Baseband-guard" "main" "setup.sh" "$bbg_sh"; then
    echo "::warning::BBG setup.sh 下载失败，跳过"
    write_state bbg false "download-failed"
    return 0
  fi

  echo "    [1/3] 执行上游 setup.sh（clone + 软链 + Makefile/Kconfig 注入）"
  ( cd "$KERN_ROOT" && sh "$bbg_sh" ) || {
    echo "::warning::BBG setup.sh 执行失败，跳过"
    write_state bbg false "setup-failed"
    return 0
  }

  # 定位 defconfig
  local dc=""
  for cand in "arch/arm64/configs/gki_defconfig" "common/arch/arm64/configs/gki_defconfig"; do
    if [ -f "$KERN_ROOT/$cand" ]; then dc="$KERN_ROOT/$cand"; break; fi
  done
  if [ -z "$dc" ]; then
    echo "::warning::找不到 gki_defconfig，跳过 BBG 配置写入"
    write_state bbg false "no-defconfig"
    return 0
  fi

  echo "    [2/3] 写 CONFIG_BBG=y -> $dc"
  set_defconfig "$dc" "CONFIG_BBG" "y"

  # 把 baseband_guard 追加进 CONFIG_LSM（幂等；已存在则不重复）
  echo "    [3/3] 追加 baseband_guard 到 CONFIG_LSM"
  if grep -qE "^CONFIG_LSM=" "$dc"; then
    if ! grep -E "^CONFIG_LSM=" "$dc" | grep -q "baseband_guard"; then
      sed -i "s|^CONFIG_LSM=\(.*\)\"|CONFIG_LSM=\1,baseband_guard\"|" "$dc"
    fi
    grep -E "^CONFIG_LSM=" "$dc"
  else
    # defconfig 里没有显式 CONFIG_LSM —— 追加一条
    echo 'CONFIG_LSM="landlock,lockdown,yama,loadpin,safesetid,selinux,smack,tomoyo,apparmor,bpf,baseband_guard"' >> "$dc"
    echo "    已追加默认 CONFIG_LSM"
  fi

  # 若框架要求改 security/Kconfig 的 LSM default（老 AOSP 风格），做一下幂等处理
  local sk="$KERN_ROOT/common/security/Kconfig"
  [ -f "$sk" ] || sk="$KERN_ROOT/security/Kconfig"
  if [ -f "$sk" ]; then
    "$PY" - "$sk" <<'PYEOF' || true
import re, sys
p = sys.argv[1]
s = open(p, encoding="utf-8", errors="replace").read()
if "baseband_guard" in s:
    sys.exit(0)
# 在 config LSM 块内的 default "..." 串里补 baseband_guard
def repl(m):
    return m.group(0).replace(m.group(1), m.group(1) + ",baseband_guard", 1)
new, n = re.subn(r'(?m)^(\s*default\s+")([^"]*selinux[^"]*)(")', repl, s, count=1)
if n:
    open(p, "w", encoding="utf-8").write(new)
    print("    security/Kconfig LSM default 已追加 baseband_guard")
else:
    print("    security/Kconfig 未找到含 selinux 的 default 行，跳过（CONFIG_LSM 已处理）")
PYEOF
  fi

  test -e "$KERN_ROOT/security/baseband-guard" -o -e "$KERN_ROOT/common/security/baseband-guard" \
    || echo "    [warn] 未找到 security/baseband-guard 软链，BBG 可能不生效"

  write_state bbg true "ok"
}

# ===========================================================================
# 功能 2：网络增强（BBRv3 + IPSet + Qdisc + CIFS）
# ===========================================================================
do_networking() {
  echo "==> [网络增强] BBRv3 / IPSet / Qdisc / CIFS"
  local sup
  sup="$(support_of networking "$KV")"
  case "$sup" in
    ""|false)
      echo "::notice::网络增强在 $KV 上不受支持，跳过。"
      write_state networking false "kmi-unsupported"
      return 0
      ;;
  esac

  local repo ref base
  repo="WildKernels/kernel_patches"
  ref="main"
  base="common/bbrv3"

  # 网络增强的补丁以 common/ 为根，因此工作目录是 kernel 树的 common/
  local wd=""
  for cand in "common" "."; do
    if [ -d "$KERN_ROOT/$cand/include/linux" ] || [ -d "$KERN_ROOT/$cand/net" ]; then
      wd="$KERN_ROOT/$cand"; break
    fi
  done
  [ -n "$wd" ] || { echo "    [warn] 找不到内核 common/ 目录"; write_state networking false "no-common"; return 0; }
  echo "    补丁工作目录: $wd"

  local tmp="/tmp/kp-net"; rm -rf "$tmp"; mkdir -p "$tmp"

  # ---- 6.12 属于 partial：先试主补丁，失败就整个跳过 ----
  local partial="false"
  [ "$sup" = "partial" ] && partial="true"

  # ---- 5.10 前置 sysctl 补丁 ----
  if [ "$KV" = "5.10" ]; then
    for pre in sysctl_add_proc_dou8vec_minmax.patch sysctl_fix_data-races_in_proc_dou8vec_minmax.patch; do
      if fetch_raw "$repo" "$ref" "$base/$pre" "$tmp/$pre"; then
        apply_patch "$tmp/$pre" "$wd" && echo "    [+] 前置补丁 $pre 已应用" \
          || { echo "::warning::5.10 前置补丁 $pre 应用失败"; write_state networking false "prereq-failed"; return 0; }
      else
        echo "::warning::5.10 前置补丁 $pre 下载失败"
        write_state networking false "prereq-download-failed"
        return 0
      fi
    done
  fi

  # ---- 主补丁 ----
  local main_patch=""
  case "$KV" in
    5.10) main_patch="0001-net-tcp-backport-BBRv3-to-android12-5.10.patch" ;;
    5.15) main_patch="0001-net-tcp-backport-BBRv3-to-android13-5.15.patch" ;;
    6.1)  main_patch="0001-net-tcp-backport-BBRv3-to-android14-6.1.patch" ;;
    6.6)  main_patch="0001-net-tcp-backport-BBRv3-to-android15-6.6.patch" ;;
    6.12) main_patch="0001-net-tcp-backport-BBRv3-to-android16-6.12.patch" ;;
    *)    main_patch="" ;;
  esac

  local bbr_applied="false"
  if [ -n "$main_patch" ]; then
    if fetch_raw "$repo" "$ref" "$base/$main_patch" "$tmp/$main_patch"; then
      apply_patch "$tmp/$main_patch" "$wd" && bbr_applied="true" \
        || echo "::warning::BBRv3 主补丁应用失败（$KV）"
    else
      echo "::warning::BBRv3 主补丁下载失败（$KV）"
    fi
  fi

  if [ "$partial" = "true" ] && [ "$bbr_applied" != "true" ]; then
    echo "::notice::6.12 的 BBRv3 补丁不可用，本次跳过整个网络增强。"
    write_state networking false "partial-bbr-failed"
    return 0
  fi

  # ---- 写配置（一律走 defconfig，存在性交给后续 cfg_has 复核）----
  local dc=""
  for cand in "arch/arm64/configs/gki_defconfig" "common/arch/arm64/configs/gki_defconfig"; do
    if [ -f "$KERN_ROOT/$cand" ]; then dc="$KERN_ROOT/$cand"; break; fi
  done
  if [ -z "$dc" ]; then
    echo "::warning::找不到 gki_defconfig，跳过网络增强配置写入"
    write_state networking false "no-defconfig"
    return 0
  fi

  echo "    写网络相关配置 -> $dc"
  local n=0
  # IPSet 全家桶 + netfilter + qdisc + cifs（都是 defconfig 层面；不存在的符号
  # 在 olddefconfig 阶段会被 Kconfig 丢弃，不会造成构建失败）
  for key in \
    CONFIG_TCP_CONG_BBR CONFIG_NET_SCH_FQ_CODEL CONFIG_NET_SCH_FQ CONFIG_NET_SCH_CAKE \
    CONFIG_IP_SET CONFIG_IP_SET_BITMAP_IP CONFIG_IP_SET_BITMAP_IPMAC CONFIG_IP_SET_BITMAP_PORT \
    CONFIG_IP_SET_HASH_IP CONFIG_IP_SET_HASH_IPMARK CONFIG_IP_SET_HASH_IPPORT \
    CONFIG_IP_SET_HASH_IPPORTIP CONFIG_IP_SET_HASH_IPPORTNET CONFIG_IP_SET_HASH_IPMAC \
    CONFIG_IP_SET_HASH_MAC CONFIG_IP_SET_HASH_NET CONFIG_IP_SET_HASH_NETNET \
    CONFIG_IP_SET_HASH_NETPORT CONFIG_IP_SET_HASH_NETIFACE CONFIG_IP_SET_LIST_SET \
    CONFIG_NETFILTER_XT_SET CONFIG_CIFS ; do
    set_defconfig "$dc" "$key" "y"
    n=$((n + 1))
  done
  echo "    已写入 $n 项（不存在的符号会在 olddefconfig 阶段被丢弃）"

  write_state networking true "ok(bbr=$bbr_applied)"
}

# ===========================================================================
# 功能 3：ZRAM LZ4KD 增强
# ===========================================================================
do_zram() {
  echo "==> [ZRAM] LZ4KD / LZ4K 增强"
  local sup
  sup="$(support_of zram_lz4kd "$KV")"
  if [ -z "$sup" ] || [ "$sup" = "false" ]; then
    echo "::notice::ZRAM LZ4KD 在 $KV 上无补丁（上游仅提供 5.10/5.15/6.1/6.6），跳过。"
    write_state zram false "kmi-unsupported"
    return 0
  fi

  local patch_dir
  case "$KV" in
    5.10) patch_dir="other/zram/zram_patch/5.10" ;;
    5.15) patch_dir="other/zram/zram_patch/5.15" ;;
    6.1)  patch_dir="other/zram/zram_patch/6.1" ;;
    6.6)  patch_dir="other/zram/zram_patch/6.6" ;;
    *)    write_state zram false "no-patch-dir"; return 0 ;;
  esac

  local wd=""
  for cand in "common" "."; do
    if [ -d "$KERN_ROOT/$cand/drivers/block/zram" ] || [ -d "$KERN_ROOT/$cand/mm" ]; then
      wd="$KERN_ROOT/$cand"; break
    fi
  done
  [ -n "$wd" ] || { echo "    [warn] 找不到内核 common/ 目录"; write_state zram false "no-common"; return 0; }
  echo "    补丁工作目录: $wd"

  local tmp="/tmp/zram-patch"; rm -rf "$tmp"; mkdir -p "$tmp"
  local applied=0
  for pf in lz4kd.patch; do
    if fetch_raw "ShirkNeko/SukiSU_patch" "main" "$patch_dir/$pf" "$tmp/$pf"; then
      apply_patch "$tmp/$pf" "$wd" && { echo "    [+] $pf 已应用"; applied=$((applied + 1)); } \
        || echo "::warning::ZRAM 补丁 $pf 应用失败"
    else
      echo "::warning::ZRAM 补丁 $pf 下载失败"
    fi
  done

  if [ "$applied" -eq 0 ]; then
    write_state zram false "patch-failed"
    return 0
  fi

  # ---- 把 ZRAM/ZSMALLOC 编入内核 + 设定默认压缩算法 ----
  local dc=""
  for cand in "arch/arm64/configs/gki_defconfig" "common/arch/arm64/configs/gki_defconfig"; do
    if [ -f "$KERN_ROOT/$cand" ]; then dc="$KERN_ROOT/$cand"; break; fi
  done
  if [ -z "$dc" ]; then
    echo "::warning::找不到 gki_defconfig，跳过 ZRAM 配置写入"
    write_state zram false "no-defconfig"
    return 0
  fi

  echo "    ZRAM/ZSMALLOC 改为 =y，默认算法 LZ4KD -> $dc"
  set_defconfig "$dc" "CONFIG_ZRAM" "y"
  set_defconfig "$dc" "CONFIG_ZSMALLOC" "y"
  set_defconfig "$dc" "CONFIG_ZRAM_DEF_COMP_LZ4KD" "y"
  set_defconfig "$dc" "CONFIG_CRYPTO_LZ4" "y"

  # modules.bzl / modules.order 里若把 zram 列为模块，会在 =y 时冲突 —— 移除对应条目
  local mf
  for mf in "$wd/modules.bzl" "$KERN_ROOT/modules.bzl"; do
    if [ -f "$mf" ]; then
      sed -i 's|"drivers/block/zram/zram\.ko",||g; s|"mm/zsmalloc\.ko",||g' "$mf"
      echo "    已清理 $mf 中的 zram/zsmalloc 模块条目"
      break
    fi
  done

  write_state zram true "ok(patches=$applied)"
}

# ===========================================================================
# 分派
# ===========================================================================
case "$FEATURE" in
  list)
    list_matrix
    ;;
  bbg)
    [ -n "$KV" ] || { echo "::error::缺少 kernel_version 参数"; exit 2; }
    do_bbg
    ;;
  networking)
    [ -n "$KV" ] || { echo "::error::缺少 kernel_version 参数"; exit 2; }
    do_networking
    ;;
  zram)
    [ -n "$KV" ] || { echo "::error::缺少 kernel_version 参数"; exit 2; }
    do_zram
    ;;
  "")
    echo "用法: bash scripts/apply-extras.sh <bbg|networking|zram|list> <kv> [kern_root]"
    exit 2
    ;;
  *)
    echo "::error::未知功能 '$FEATURE'"
    exit 2
    ;;
esac

exit 0
