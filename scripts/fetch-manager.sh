#!/usr/bin/env bash
# =============================================================================
# fetch-manager.sh — 自动获取 FolkSU 官方最新 Manager APK
#
# 背景：FolkSU 的 Manager 是独立 APK，发布在官方仓库的 Actions artifact 里，
#       不在 Release 中。每次构建内核都需要配套的 Manager（版本 / versionCode
#       要和内核里的 KSU UAPI 对齐，否则管理器会提示"需要更新内核"）。
#
# 做法（与上游 LingLuo17 / BakaSU 同一套路，但按 FolkSU 实际命名适配）：
#   1. 查 Build Manager workflow 最近的成功构建（按时间倒序）
#   2. 找到名为 manager 的 artifact，下载 zip
#   3. 解出 *.apk，按 commit sha / 构建时间做匹配打分
#   4. 输出 apk 路径、版本、versionCode 到 GITHUB_OUTPUT（若在 CI 中）
#
# FolkSU 实测命名示例：
#   FolkSU_v0.1.0-beta3-5-g49819d2c_32792-release.apk
#   └─ 版本 ─────┘ └sha8┘ └versionCode┘
#
# 环境变量：
#   GITHUB_TOKEN       必填，用于 GitHub API（CI 里用 secrets.GITHUB_TOKEN）
#   GH_API_PROXY       可选，HTTP 代理
#   MANAGER_REPO       可选，默认 LyraVoid/FolkSU
#   MANAGER_WORKFLOW   可选，默认 build-manager.yml
#   MANAGER_REF        可选，优先匹配的 commit sha（一般传内核用的 folksu_ref）
#   MANAGER_NEED_VER   可选，要求的最低 versionCode；低于此值报错
#   MANAGER_OUTDIR     可选，输出目录，默认 ./manager-artifacts
# =============================================================================
set -euo pipefail

MANAGER_REPO="${MANAGER_REPO:-LyraVoid/FolkSU}"
MANAGER_WORKFLOW="${MANAGER_WORKFLOW:-build-manager.yml}"
MANAGER_OUTDIR="${MANAGER_OUTDIR:-manager-artifacts}"
MANAGER_REF="${MANAGER_REF:-}"
MANAGER_NEED_VER="${MANAGER_NEED_VER:-}"

CURL=(curl -sSL --retry 3 --retry-delay 2 --retry-all-errors)
if [ -n "${GH_API_PROXY:-}" ]; then
  CURL+=(-x "$GH_API_PROXY")
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  echo "::error::GITHUB_TOKEN 未设置"
  exit 1
fi

API="https://api.github.com/repos/${MANAGER_REPO}"
AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28")

log() { echo "==> $*"; }
warn() { echo "::warning::$*"; }

# --- 解析 repo name（API 可能 301 到 by-id 路径）-----------------------------
resolve_api() {
  local raw
  raw="$("${CURL[@]}" "${AUTH[@]}" "$API" || true)"
  local id
  id="$(printf '%s' "$raw" | python3 -c 'import sys,json
try:
    d=json.load(sys.stdin)
    print(d.get("id","") or "")
except Exception:
    print("")' 2>/dev/null || true)"
  if [ -n "$id" ]; then
    echo "https://api.github.com/repositories/${id}"
  else
    echo "$API"
  fi
}

BASE="$(resolve_api)"
log "repo API base: $BASE"

mkdir -p "$MANAGER_OUTDIR"
rm -rf "${MANAGER_OUTDIR:?}"/* 2>/dev/null || true

# --- 1) 找最近的 manager 构建 -------------------------------------------------
log "查询 ${MANAGER_WORKFLOW} 最近成功构建"
RUNS_JSON="$("${CURL[@]}" "${AUTH[@]}" \
  "${BASE}/actions/workflows/${MANAGER_WORKFLOW}/runs?status=success&per_page=10" || true)"

MAP="$(printf '%s' "$RUNS_JSON" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for r in d.get("workflow_runs", []):
    row = [str(r.get("id","")), str(r.get("head_sha","")),
           str(r.get("created_at","")), str(r.get("head_branch",""))]
    print("\t".join(row))
' 2>/dev/null || true)"

if [ -z "$MAP" ]; then
  echo "::error::未取到 ${MANAGER_WORKFLOW} 的成功构建记录"
  exit 1
fi
echo "$MAP" | while IFS=$'\t' read -r id sha created br; do
  echo "    run $id  sha=${sha:0:8}  branch=$br  $created"
done

# --- 2) 依次尝试，直到拿到可用 APK --------------------------------------------
FOUND_APK=""
FOUND_RUN=""
FOUND_SHA=""

while IFS=$'\t' read -r RUN_ID RUN_SHA RUN_CREATED RUN_BRANCH; do
  [ -n "$RUN_ID" ] || continue
  log "尝试 run $RUN_ID (sha=${RUN_SHA:0:8}, $RUN_CREATED)"

  ART_JSON="$("${CURL[@]}" "${AUTH[@]}" "${BASE}/actions/runs/${RUN_ID}/artifacts" || true)"
  URL="$(printf '%s' "$ART_JSON" | python3 -c '
import sys, json, re
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
cands = []
for a in d.get("artifacts", []):
    if a.get("expired"):
        continue
    n = (a.get("name") or "").lower()
    # FolkSU 官方 artifact 名为 "manager"；兼容其它上游命名
    if n == "manager" or re.search(r"(^|[-_])manager([-_]|$)", n) or "manager-release" in n:
        # 精确优先
        prio = 0 if n == "manager" else 1
        cands.append((prio, a.get("size_in_bytes", 0), a.get("archive_download_url","")))
cands.sort(key=lambda x: (x[0], -x[1]))
if cands:
    print(cands[0][2])
' 2>/dev/null || true)"

  if [ -z "$URL" ]; then
    warn "run $RUN_ID 中没有 manager artifact，换下一个"
    continue
  fi

  LDIR="$MANAGER_OUTDIR/run-$RUN_ID"
  mkdir -p "$LDIR"
  if ! "${CURL[@]}" "${AUTH[@]}" -o "$LDIR/manager.zip" "$URL"; then
    warn "run $RUN_ID artifact 下载失败，换下一个"
    rm -rf "$LDIR"
    continue
  fi

  if ! unzip -oq "$LDIR/manager.zip" -d "$LDIR/unz" 2>/dev/null; then
    warn "run $RUN_ID zip 解压失败，换下一个"
    rm -rf "$LDIR"
    continue
  fi
  rm -f "$LDIR/manager.zip"

  APK="$(find "$LDIR/unz" -type f -name '*.apk' ! -name '*debug*' | head -n 1 || true)"
  if [ -z "$APK" ]; then
    APK="$(find "$LDIR/unz" -type f -name '*.apk' | head -n 1 || true)"
  fi
  if [ -z "$APK" ]; then
    warn "run $RUN_ID 内没有 apk，换下一个"
    rm -rf "$LDIR"
    continue
  fi

  FOUND_APK="$APK"
  FOUND_RUN="$RUN_ID"
  FOUND_SHA="$RUN_SHA"
  log "拿到 APK: $(basename "$APK")"
  break
done <<< "$MAP"

if [ -z "$FOUND_APK" ]; then
  echo "::error::未能在最近 10 次成功构建中找到 FolkSU Manager APK"
  exit 1
fi

# --- 3) 归一化命名 + 解析版本 -------------------------------------------------
BASENAME="$(basename "$FOUND_APK")"

# FolkSU_v0.1.0-beta3-5-g49819d2c_32792-release.apk
#   ver = v0.1.0-beta3-5-g49819d2c ; vc = 32792
VER="$(printf '%s' "$BASENAME" | sed -nE 's/^.*_v?([^_]+)_([0-9]+)(-[A-Za-z0-9_]+)?\.apk$/\1/p')"
VC="$(printf '%s' "$BASENAME"  | sed -nE 's/^.*_v?([^_]+)_([0-9]+)(-[A-Za-z0-9_]+)?\.apk$/\2/p')"
[ -n "$VER" ] || VER="unknown"
[ -n "$VC" ]  || VC="0"

# 统一命名，方便刷机时辨认：FolkSU-Manager-<ver>-<vc>.apk
SAFE_VER="$(printf '%s' "$VER" | tr -c 'A-Za-z0-9._-' '_')"
OUT_APK="$MANAGER_OUTDIR/FolkSU-Manager-${SAFE_VER}-${VC}.apk"
cp -f "$FOUND_APK" "$OUT_APK"

log "Manager 版本    : $VER"
log "Manager versionCode: $VC"
log "来源 run        : $FOUND_RUN (sha=${FOUND_SHA:0:8})"
log "输出            : $OUT_APK"

# --- 4) 版本约束校验 ---------------------------------------------------------
if [ -n "$MANAGER_NEED_VER" ] && [ "$VC" != "0" ]; then
  if [ "$VC" -lt "$MANAGER_NEED_VER" ] 2>/dev/null; then
    echo "::error::Manager versionCode $VC 低于要求 $MANAGER_NEED_VER"
    exit 1
  fi
  log "versionCode 校验通过 ($VC >= $MANAGER_NEED_VER)"
fi

# --- 5) 若 MANAGER_REF 与构建 sha 对齐，给出提示 ------------------------------
if [ -n "$MANAGER_REF" ] && [ -n "$FOUND_SHA" ]; then
  if [ "${FOUND_SHA:0:7}" = "${MANAGER_REF:0:7}" ]; then
    log "Manager 与内核源码同 commit（${FOUND_SHA:0:8}），版本严格对齐"
  else
    warn "Manager sha(${FOUND_SHA:0:8}) 与内核 ref(${MANAGER_REF:0:8}) 不同，可能提示'需要更新内核'"
  fi
fi

# --- 6) 输出 ------------------------------------------------------------------
{
  echo "apk_path=$OUT_APK"
  echo "apk_name=$(basename "$OUT_APK")"
  echo "manager_version=$VER"
  echo "manager_version_code=$VC"
  echo "manager_run_id=$FOUND_RUN"
  echo "manager_sha=$FOUND_SHA"
} >> "${GITHUB_OUTPUT:-/dev/stdout}"

find "$MANAGER_OUTDIR" -type f -name '*.apk' -print
echo "OK"
