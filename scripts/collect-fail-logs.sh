#!/usr/bin/env bash
# ============================================================================
# collect-fail-logs.sh —— 编译失败时收集关键信息并打包
#
# 用法：
#   bash scripts/collect-fail-logs.sh <out_dir> <log_file> [more_log...]
#
# 收集内容：
#   summary.txt         构建配置摘要（方案 / KMI / 分支 / 各功能开关 / 版本）
#   kernel-release.txt  内核 release 字符串（若已生成）
#   disk-usage.txt      磁盘占用
#   ccache-stats.txt    ccache 命中统计
#   tail-*.log          各编译日志的最后 400 行（足够定位报错）
#
# 设计要点：
#   * 绝不因收集失败而退出（所有子命令都兜 || true）。
#   * 输出目录里再放一个 artifact-name.txt，方便上传步骤取名。
# ============================================================================

set -uo pipefail

OUT_DIR="${1:-$PWD/build-logs}"
shift || true
MAIN_LOG="${1:-}"
shift || true
MORE_LOGS=("$@")

mkdir -p "$OUT_DIR"

# ---------------------------------------------------------------------------
# 1) 构建配置摘要
# ---------------------------------------------------------------------------
{
  echo "==================== 构建失败摘要 ===================="
  echo "时间(UTC)     : $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "仓库          : ${GITHUB_REPOSITORY:-<未知>}"
  echo "提交          : ${GITHUB_SHA:-<未知>}"
  echo "工作流        : ${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  echo
  echo "--- 构建参数 ---"
  echo "构建模式      : ${E_MODE:-${BUILD_MODE:-<未知>}}"
  echo "root 方案     : ${E_SOL:-${ROOT_SOLUTION:-<未知>}}"
  echo "KMI           : ${E_KMI:-${KMI:-<未知>}}"
  echo "AOSP 分支     : ${E_BRANCH:-${KERNEL_BRANCH:-<未知>}}"
  echo "源码 ref      : ${E_REF:-${SOLUTION_REF:-<配置默认>}}"
  echo "SUSFS         : ${E_SUSFS:-${ENABLE_SUSFS:-<未知>}}"
  echo "内核调优      : ${E_TWEAKS:-${KERNEL_TWEAKS:-<未知>}}"
  echo
  echo "--- 附加功能 ---"
  echo "BBG 防格机    : ${E_BBG:-${FEATURE_BBG:-<未知>}}"
  echo "网络增强      : ${E_NET:-${FEATURE_NETWORKING:-<未知>}}"
  echo "ZRAM LZ4KD    : ${E_ZRAM:-${FEATURE_ZRAM_LZ4:-<未知>}}"
  echo "KPM           : ${E_KPM:-${FEATURE_KPM:-<未知>}}"
  echo
  echo "--- 内核 / root 源码版本 ---"
  if [ -f KSU_INFO.txt ]; then cat KSU_INFO.txt; else echo "KSU_INFO.txt: <无>"; fi
  if [ -f GKI_INFO.txt ]; then cat GKI_INFO.txt; else echo "GKI_INFO.txt: <无>"; fi
  echo
  echo "--- 工具链 ---"
  echo "clang         : $(clang --version 2>/dev/null | head -1 || echo '<无>')"
  echo "ld.lld        : $(ld.lld --version 2>/dev/null | head -1 || echo '<无>')"
  echo "LLVM_MAKE_ARGS: ${LLVM_MAKE_ARGS:-<未设置>}"
  echo "nproc         : $(nproc 2>/dev/null || echo '?')"
  echo "====================================================="
} > "$OUT_DIR/summary.txt" 2>&1 || true

# ---------------------------------------------------------------------------
# 2) 内核 release（可能已生成）
# ---------------------------------------------------------------------------
if [ -d gki ]; then
  ( cd gki && make ARCH=arm64 ${LLVM_MAKE_ARGS:-LLVM=1} -s kernelrelease 2>&1 ) \
    > "$OUT_DIR/kernel-release.txt" 2>&1 || true
fi

# ---------------------------------------------------------------------------
# 3) 磁盘占用
# ---------------------------------------------------------------------------
df -h . > "$OUT_DIR/disk-usage.txt" 2>&1 || true
du -sh "$PWD"/* 2>/dev/null >> "$OUT_DIR/disk-usage.txt" 2>&1 || true

# ---------------------------------------------------------------------------
# 4) ccache 统计
# ---------------------------------------------------------------------------
ccache -s > "$OUT_DIR/ccache-stats.txt" 2>&1 || true

# ---------------------------------------------------------------------------
# 5) 编译日志尾部
# ---------------------------------------------------------------------------
collect_tail() {
  local f="$1" idx="$2"
  [ -f "$f" ] || return 0
  local total
  total="$(wc -l < "$f" 2>/dev/null || echo 0)"
  {
    echo "### 源日志: $f （共 $total 行）"
    echo "### 下面是最后 400 行"
    echo "-----------------------------------------------------"
    tail -n 400 "$f"
  } > "$OUT_DIR/tail-${idx}.log" 2>&1 || true
}

idx=1
[ -n "$MAIN_LOG" ] && { collect_tail "$MAIN_LOG" "$idx"; idx=$((idx + 1)); }
for f in "${MORE_LOGS[@]:-}"; do
  [ -n "$f" ] || continue
  collect_tail "$f" "$idx"; idx=$((idx + 1))
done

# 兜底：若一个日志都没收到，扫一下 build-logs 目录
if [ "$idx" -eq 1 ]; then
  for f in $(ls -1 build-logs/*.log 2>/dev/null | head -5); do
    collect_tail "$f" "$idx"; idx=$((idx + 1))
  done
fi

# ---------------------------------------------------------------------------
# 6) 失败标志（供上传步骤判断）
# ---------------------------------------------------------------------------
printf 'failed=true\n' > "$OUT_DIR/.failed"

echo "已收集失败日志到 $OUT_DIR："
ls -la "$OUT_DIR" || true
echo "打包内容预览："
head -40 "$OUT_DIR/summary.txt" 2>/dev/null || true

exit 0
