#!/usr/bin/env bash
# =============================================================================
# fetch-manager.sh — 自动获取 KSU 系列 root 管理器 APK
#
# 支持两种来源（由 config/root-solutions.json 配置驱动）：
#   (a) Actions artifact：如 MoeSU 的 build-manager.yml → artifact "manager"
#   (b) GitHub Release 资产：如 KernelSU / SukiSU / KernelSU-Next 直接发 Release
#
# 用法：
#   ROOT_SOLUTION=moesu bash scripts/fetch-manager.sh
#
# 环境变量：
#   GITHUB_TOKEN       必填（CI 里用 secrets.GITHUB_TOKEN）
#   ROOT_SOLUTION      方案 id，见 config/root-solutions.json（默认 moesu）
#   SOLUTION_CONFIG    配置路径（默认 config/root-solutions.json）
#   GH_API_PROXY       可选，HTTP 代理
#   MANAGER_REF        可选，优先对齐的 commit sha
#   MANAGER_NEED_VER   可选，要求的最低 versionCode
#   MANAGER_OUTDIR     可选，输出目录（默认 ./manager-artifacts）
# =============================================================================
set -euo pipefail

ROOT_SOLUTION="${ROOT_SOLUTION:-moesu}"
SOLUTION_CONFIG="${SOLUTION_CONFIG:-config/root-solutions.json}"
MANAGER_OUTDIR="${MANAGER_OUTDIR:-manager-artifacts}"
MANAGER_REF="${MANAGER_REF:-}"
MANAGER_NEED_VER="${MANAGER_NEED_VER:-}"

PY="${PYTHON_BIN:-python3}"

CURL=(curl -sSL --retry 3 --retry-delay 2 --retry-all-errors --max-time 120)
if [ -n "${GH_API_PROXY:-}" ]; then
  CURL+=(-x "$GH_API_PROXY")
fi

log()  { echo "==> $*"; }
warn() { echo "::warning::$*"; }

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "::error::GITHUB_TOKEN 未设置"
  exit 1
fi

AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28")

# --- 0) 读取方案配置 ---------------------------------------------------------
if [ ! -f "$SOLUTION_CONFIG" ]; then
  echo "::error::找不到方案配置 $SOLUTION_CONFIG"
  exit 1
fi

CONF="$("$PY" - "$SOLUTION_CONFIG" "$ROOT_SOLUTION" <<'PYEOF'
import json, sys
cfg_path, want = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfg_path, encoding="utf-8"))
for s in cfg.get("solutions", []):
    if s.get("id") == want:
        m = s.get("manager", {}) or {}
        print("\t".join([
            s.get("id", ""),
            s.get("name", ""),
            s.get("repo", ""),
            m.get("repo", ""),
            m.get("workflow", ""),
            m.get("artifact_name", ""),
            ",".join(m.get("package_whitelist", []) or []),
            m.get("release_asset_pattern", ""),
            "1" if m.get("fetch") else "0",
        ]))
        sys.exit(0)
sys.exit(f"unknown solution id: {want}")
PYEOF
)"

IFS=$'\t' read -r S_ID S_NAME S_REPO M_REPO M_WORKFLOW M_ARTIFACT M_PKGS M_RELPAT M_FETCH <<< "$CONF"

log "方案      : $S_NAME ($S_ID)"
log "源码仓库  : $S_REPO"
log "Manager   : repo=$M_REPO workflow=${M_WORKFLOW:-<无>} artifact=${M_ARTIFACT:-<无>}"
log "已知包名  : $M_PKGS"

mkdir -p "$MANAGER_OUTDIR"
rm -rf "${MANAGER_OUTDIR:?}"/* 2>/dev/null || true

# 解析 repo（应对 301 改名 → by-id 路径）
resolve_base() {
  local slug="$1" raw id
  raw="$("${CURL[@]}" "${AUTH[@]}" "https://api.github.com/repos/${slug}" 2>/dev/null || true)"
  id="$("$PY" -c 'import sys,json
try:
    print(json.load(sys.stdin).get("id","") or "")
except Exception:
    print("")' <<< "$raw" 2>/dev/null || true)"
  if [ -n "$id" ]; then echo "https://api.github.com/repositories/${id}";
  else echo "https://api.github.com/repos/${slug}"; fi
}

FOUND_APK=""
FOUND_SRC=""

# =============================================================================
# 路径 A：Actions artifact（MoeSU 这类）
# =============================================================================
if [ "$M_FETCH" = "1" ] && [ -n "$M_WORKFLOW" ] && [ -n "$M_ARTIFACT" ]; then
  BASE="$(resolve_base "$M_REPO")"
  log "[A] 查询 ${M_WORKFLOW} 最近成功构建 (base=$BASE)"

  RUNS_JSON="$("${CURL[@]}" "${AUTH[@]}" \
    "${BASE}/actions/workflows/${M_WORKFLOW}/runs?status=success&per_page=10" 2>/dev/null || true)"

  MAP="$("$PY" -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("workflow_runs", []):
    print("\t".join([str(r.get("id","")), str(r.get("head_sha","")),
                     str(r.get("created_at","")), str(r.get("head_branch",""))]))
' <<< "$RUNS_JSON" 2>/dev/null || true)"

  if [ -n "$MAP" ]; then
    while IFS=$'\t' read -r RUN_ID RUN_SHA RUN_CREATED RUN_BRANCH; do
      [ -n "$RUN_ID" ] || continue
      log "[A] 尝试 run $RUN_ID (sha=${RUN_SHA:0:8}, $RUN_CREATED)"

      ART_JSON="$("${CURL[@]}" "${AUTH[@]}" "${BASE}/actions/runs/${RUN_ID}/artifacts" 2>/dev/null || true)"
      URL="$("$PY" -c '
import sys, json
want = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
best = None
for a in d.get("artifacts", []):
    if a.get("expired"):
        continue
    n = a.get("name") or ""
    if n == want:
        best = a
        break
    if best is None and want.lower() in n.lower():
        best = a
if best:
    print(best.get("archive_download_url", ""))
' "$M_ARTIFACT" <<< "$ART_JSON" 2>/dev/null || true)"

      if [ -z "$URL" ]; then
        warn "[A] run $RUN_ID 无 '$M_ARTIFACT' artifact，换下一个"
        continue
      fi

      LDIR="$MANAGER_OUTDIR/run-$RUN_ID"
      mkdir -p "$LDIR"
      if ! "${CURL[@]}" "${AUTH[@]}" -o "$LDIR/m.zip" "$URL"; then
        warn "[A] run $RUN_ID 下载失败，换下一个"; rm -rf "$LDIR"; continue
      fi
      if ! unzip -oq "$LDIR/m.zip" -d "$LDIR/unz" 2>/dev/null; then
        warn "[A] run $RUN_ID 解压失败，换下一个"; rm -rf "$LDIR"; continue
      fi
      rm -f "$LDIR/m.zip"

      FOUND_APK="$(find "$LDIR/unz" -type f -name '*.apk' ! -name '*debug*' | head -n 1 || true)"
      [ -n "$FOUND_APK" ] || FOUND_APK="$(find "$LDIR/unz" -type f -name '*.apk' | head -n 1 || true)"
      if [ -z "$FOUND_APK" ]; then
        warn "[A] run $RUN_ID 内无 apk，换下一个"; rm -rf "$LDIR"; continue
      fi
      FOUND_SRC="actions:run-$RUN_ID sha=${RUN_SHA:0:8}"
      log "[A] 拿到 APK: $(basename "$FOUND_APK")"
      break
    done <<< "$MAP"
  else
    warn "[A] 未取到 ${M_WORKFLOW} 的成功构建记录"
  fi
fi

# =============================================================================
# 路径 B：GitHub Release 资产
# =============================================================================
if [ -z "$FOUND_APK" ]; then
  BASE="$(resolve_base "$M_REPO")"
  log "[B] 回退：查询 $M_REPO 最新 Release"

  REL="$("${CURL[@]}" "${AUTH[@]}" "${BASE}/releases/latest" 2>/dev/null || true)"

  DL="$("$PY" -c '
import sys, json
pat = sys.argv[1] or "*.apk"
import fnmatch
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cands = []
for a in d.get("assets", []):
    n = a.get("name") or ""
    if fnmatch.fnmatch(n, pat) or n.lower().endswith(".apk"):
        # 优先 arm64-v8a / release，避免 debug
        score = 0
        nl = n.lower()
        if "debug" in nl: score -= 100
        if "arm64" in nl or "universal" in nl: score += 10
        if "release" in nl: score += 5
        cands.append((score, n, a.get("browser_download_url","")))
cands.sort(reverse=True)
if cands:
    print("\t".join([cands[0][1], cands[0][2]]))
    print(d.get("tag_name",""), file=sys.stderr)
' "$M_RELPAT" <<< "$REL" 2>/dev/null || true)"

    if [ -n "$DL" ]; then
      RNAME="${DL%%$'\t'*}"; RURL="${DL#*$'\t'}"
      log "[B] 资产: $RNAME"
      LDIR="$MANAGER_OUTDIR/release"
      mkdir -p "$LDIR"
      if "${CURL[@]}" "${AUTH[@]}" -o "$LDIR/$RNAME" "$RURL"; then
        FOUND_APK="$LDIR/$RNAME"
        FOUND_SRC="release:$RNAME"
      else
        warn "[B] Release 资产下载失败"
      fi
    else
      warn "[B] 未在 Release 中找到 APK 资产"
    fi
fi

if [ -z "$FOUND_APK" ]; then
  echo "::warning::$S_NAME 未获取到 Manager APK（两种来源都失败）"
  echo "::warning::内核包仍然可用；Manager 请到 $S_REPO 手动下载"
  exit 0
fi

# =============================================================================
# 归一化命名 + 版本解析
# =============================================================================
BASENAME="$(basename "$FOUND_APK")"

VER="$(printf '%s' "$BASENAME" | sed -nE 's/^.*_v?([^_]+)_([0-9]+)(-[A-Za-z0-9_]+)?\.apk$/\1/p')"
VC="$(printf '%s' "$BASENAME"  | sed -nE 's/^.*_v?([^_]+)_([0-9]+)(-[A-Za-z0-9_]+)?\.apk$/\2/p')"
[ -n "$VER" ] || VER="unknown"
[ -n "$VC" ]  || VC="0"

SAFE_VER="$(printf '%s' "$VER" | tr -c 'A-Za-z0-9._-' '_')"
SAFE_NAME="$(printf '%s' "$S_NAME" | tr -c 'A-Za-z0-9._-' '_')"
OUT_APK="$MANAGER_OUTDIR/${SAFE_NAME}-Manager-${SAFE_VER}-${VC}.apk"
cp -f "$FOUND_APK" "$OUT_APK"

log "Manager 版本      : $VER"
log "Manager versionCode: $VC"
log "来源              : $FOUND_SRC"
log "输出              : $OUT_APK"

if [ -n "$MANAGER_NEED_VER" ] && [ "$VC" != "0" ]; then
  if [ "$VC" -lt "$MANAGER_NEED_VER" ] 2>/dev/null; then
    echo "::error::Manager versionCode $VC 低于要求 $MANAGER_NEED_VER"
    exit 1
  fi
  log "versionCode 校验通过 ($VC >= $MANAGER_NEED_VER)"
fi

if [ -n "$MANAGER_REF" ] && [ -n "$FOUND_SRC" ]; then
  case "$FOUND_SRC" in
    *"${MANAGER_REF:0:7}"*) log "Manager 与内核源码同 commit，版本严格对齐" ;;
  esac
fi

{
  echo "apk_path=$OUT_APK"
  echo "apk_name=$(basename "$OUT_APK")"
  echo "manager_version=$VER"
  echo "manager_version_code=$VC"
  echo "manager_source=$FOUND_SRC"
  echo "manager_pkg_whitelist=$M_PKGS"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

find "$MANAGER_OUTDIR" -type f -name '*.apk' -print
echo "OK"
