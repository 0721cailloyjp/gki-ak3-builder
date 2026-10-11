#!/usr/bin/env bash
# =============================================================================
# resolve-solution.sh — 从 config/root-solutions.json 解析某个 root 方案
#
# 把「多方案差异」集中到一处，workflow 只消费这里输出的键值，不再硬编码任何
# 项目名。这样以后上游再改名 / 再出现新的主流 fork，改 JSON 即可。
#
# 用法：
#   ROOT_SOLUTION=moesu bash scripts/resolve-solution.sh >> "$GITHUB_OUTPUT"
#
# 输出（$GITHUB_OUTPUT 键）：
#   sol_id / sol_name / sol_alias / sol_repo / sol_ref
#   sol_needs_git / sol_uses_github_commits / sol_gh_base / sol_gh_offset
#   sol_version_formula / sol_susfs_compatible
#   sol_always_enable / sol_optional_features   （该方案独有的内核功能开关）
#   mgr_fetch / mgr_repo / mgr_workflow / mgr_artifact / mgr_release_pattern
#   mgr_pkgs
# =============================================================================
set -euo pipefail

ROOT_SOLUTION="${ROOT_SOLUTION:-moesu}"
SOLUTION_CONFIG="${SOLUTION_CONFIG:-config/root-solutions.json}"
PY="${PYTHON_BIN:-python3}"

if [ ! -f "$SOLUTION_CONFIG" ]; then
  echo "::error::找不到方案配置 $SOLUTION_CONFIG"
  exit 1
fi

"$PY" - "$SOLUTION_CONFIG" "$ROOT_SOLUTION" <<'PYEOF'
import json, os, sys

cfg_path, want = sys.argv[1], sys.argv[2]
cfg = json.load(open(cfg_path, encoding="utf-8"))

sol = None
for s in cfg.get("solutions", []):
    if s.get("id") == want:
        sol = s
        break
if sol is None:
    avail = ", ".join(s.get("id", "?") for s in cfg.get("solutions", []))
    sys.stderr.write("::error::未知 root 方案 '%s'，可选：%s\n" % (want, avail))
    sys.exit(1)

m = sol.get("manager") or {}
kf = sol.get("kernel_features") or {}


def b(v):
    return "true" if v else "false"


# 该方案独有的内核功能开关（实测四家 Kconfig 差异）：
#   always_enable —— 该方案存在就开（不存在自动跳过）
#   optional      —— 由 workflow 输入控制，形如 {"KPM": {"default": false, ...}}
always_enable = kf.get("always_enable", []) or []
optional = kf.get("optional", {}) or {}

out = {
    "sol_id": sol.get("id", ""),
    "sol_name": sol.get("name", ""),
    "sol_alias": sol.get("alias", "") or "",
    "sol_repo": sol.get("repo", ""),
    "sol_ref": sol.get("default_ref", "main"),
    "sol_needs_git": b(sol.get("needs_git_history", True)),
    "sol_uses_github_commits": b(sol.get("supports_github_commits_env", False)),
    "sol_gh_base": str(sol.get("github_commits_base", "") or ""),
    "sol_gh_offset": str(sol.get("github_commits_offset", "") or ""),
    "sol_version_formula": sol.get("version_formula", ""),
    "sol_susfs_compatible": b(sol.get("susfs_compatible", True)),
    "sol_stars": str(sol.get("stars", "") or ""),
    "sol_always_enable": ",".join(str(x) for x in always_enable),
    # JSON 单行（无换行），供 workflow 用 python 解析各可选功能的默认值
    "sol_optional_features": json.dumps(optional, ensure_ascii=False, separators=(",", ":")),
    "mgr_fetch": b(m.get("fetch", False)),
    "mgr_repo": m.get("repo", "") or "",
    "mgr_workflow": m.get("workflow", "") or "",
    "mgr_artifact": m.get("artifact_name", "") or "",
    "mgr_release_pattern": m.get("release_asset_pattern", "") or "*.apk",
    "mgr_pkgs": ",".join(m.get("package_whitelist", []) or []),
}

out_file = os.environ.get("GITHUB_OUTPUT", "")
lines = []
for k, v in out.items():
    v = str(v).replace("\n", " ").replace("\r", "")
    lines.append("%s=%s" % (k, v))

text = "\n".join(lines) + "\n"
if out_file:
    with open(out_file, "a", encoding="utf-8") as f:
        f.write(text)
else:
    # 本地调试：没有 GITHUB_OUTPUT 时打到 stdout
    sys.stdout.write(text)
PYEOF
