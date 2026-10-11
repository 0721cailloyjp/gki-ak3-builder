#!/usr/bin/env bash
# resolve-features.sh —— 解析「方案可选内核功能」并输出 TSV 决策表
#
# 为什么单独成脚本：workflow 的 `run: |` 块里内联多行 python 会破坏 YAML
# 块标量缩进（Python 代码顶格写 → YAML ScannerError）。抽出来既安全又可复用。
#
# 输入（环境变量）：
#   SOL_OPT_JSON    —— config/root-solutions.json 里该方案的 kernel_features.optional
#                      的 JSON 单行文本（由 resolve-solution.sh 输出）
#   FEAT_KPM        —— workflow 输入 feature_kpm（"true"/"false"）
#
# 输出（stdout，每行一个功能）：
#   <符号名>|<是否开启 true/false>|<风险等级>|<来源说明>
#
# 本地调试可直跑：
#   SOL_OPT_JSON='{"KPM":{"default":false,"risk":"high"}}' FEAT_KPM=true bash resolve-features.sh

set -uo pipefail

PY="${PYTHON_BIN:-python3}"

"$PY" - <<'PYEOF'
import json
import os
import sys

raw = os.environ.get("SOL_OPT_JSON", "") or "{}"
try:
    opt = json.loads(raw)
    if not isinstance(opt, dict):
        opt = {}
except Exception:
    opt = {}

# workflow 输入 → 符号名映射。新增可选功能时在这里加一行。
feature_input = {
    "KPM": os.environ.get("FEAT_KPM", "false") == "true",
}

for name, meta in opt.items():
    if not isinstance(meta, dict):
        meta = {}
    if name in feature_input:
        want = feature_input[name]
        source = "workflow 输入"
    else:
        want = bool(meta.get("default", False))
        source = "配置 default"
    risk = meta.get("risk", "?")
    print("%s|%s|%s|%s" % (name, "true" if want else "false", risk, source))
PYEOF
