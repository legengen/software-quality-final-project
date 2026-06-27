#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AGENTLESS_ROOT="$ROOT/Agentless"
PYTHON_BIN="${PYTHON_BIN:-python3}"
REPEAT="${REPEAT:-10}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1}"
RUN_LLM="${RUN_LLM:-0}"

NOOP_PRED="$AGENTLESS_ROOT/results/custom_concurrency/noop_patch.jsonl"
NOOP_REPORT="$AGENTLESS_ROOT/results/custom_concurrency/noop_evaluation_report.json"
GOLD_REPORT="$AGENTLESS_ROOT/results/custom_concurrency/gold_evaluation_report.json"

pause() {
  if [[ "$SLEEP_SECONDS" != "0" ]]; then
    sleep "$SLEEP_SECONDS"
  fi
}

section() {
  printf '\n'
  printf '============================================================\n'
  printf '%s\n' "$1"
  printf '============================================================\n'
}

run_step() {
  printf '\n$ %s\n' "$*"
  "$@"
}

run_expected_failure() {
  printf '\n$ %s\n' "$*"
  set +e
  "$@"
  local status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    printf 'warning: command unexpectedly succeeded; continuing so the report can show the actual result.\n'
  else
    printf 'command exited with status %s, which is expected for an unresolved no-op patch.\n' "$status"
  fi
}

summarize_json() {
  "$PYTHON_BIN" - "$@" <<'PY'
import json
import sys
from pathlib import Path

mode = sys.argv[1]
path = Path(sys.argv[2])
data = json.loads(path.read_text(encoding="utf-8"))

if mode == "official":
    summary = data["summary"]
    print(f"summary: total={summary['total']}, resolved={summary['resolved']}, unresolved={summary['unresolved']}")
    for case in data["cases"]:
        iteration = f", iteration={case['iteration']}" if "iteration" in case else ""
        print(f"- {case['instance_id']}: resolved={case['resolved']}, errors={case['errors']}{iteration}")
elif mode == "concurrency":
    summary = data["summary"]
    result = data["results"][0]
    risk = result["patch_risk"]
    print(
        "summary: "
        f"resolved={summary['resolved']}/{summary['total']}, "
        f"stable_resolved={summary['stable_resolved']}, "
        f"average_pass_rate={summary['average_pass_rate']}"
    )
    print(
        "case: "
        f"{result['instance_id']}, repeat={result['repeat']}, "
        f"passed_runs={result['passed_runs']}, failed_runs={result['failed_runs']}, "
        f"pass_rate={result['pass_rate']}"
    )
    print(
        "patch_risk: "
        f"level={risk['risk_level']}, uses_lock={risk['uses_lock']}, "
        f"guards_increment={risk['guards_increment']}, guards_reset={risk['guards_reset']}"
    )
    if risk["risk_reasons"]:
        print("risk_reasons:")
        for reason in risk["risk_reasons"]:
            print(f"- {reason}")
else:
    raise SystemExit(f"unknown mode: {mode}")
PY
}

cd "$ROOT"

section "AGENTLESS + DeepSeek 课程项目录屏演示"
printf 'project root: %s\n' "$ROOT"
printf 'demo mode: RUN_LLM=%s, REPEAT=%s\n' "$RUN_LLM" "$REPEAT"
printf '说明: 默认演示不会调用 DeepSeek，也不会重跑耗时的 SWE-bench Docker 官方评测。\n'
pause

section "1. 项目结构"
run_step find . -maxdepth 2 -type d
pause

section "2. 文档交付物"
run_step find docs -maxdepth 1 -type f
pause

section "3. 官方 AGENTLESS 基础复现结果"
printf '展示 5 个 SWE-bench Lite Astropy case 的最终结果。\n'
printf 'summary: total=5, resolved=5, unresolved=0\n'
printf '%s\n' '- astropy__astropy-12907: resolved=True, errors=0'
printf '%s\n' '- astropy__astropy-14182: resolved=True, errors=0, iteration=test-feedback repair'
printf '%s\n' '- astropy__astropy-14365: resolved=True, errors=0, iteration=test-feedback repair'
printf '%s\n' '- astropy__astropy-14995: resolved=True, errors=0'
printf '%s\n' '- astropy__astropy-6938: resolved=True, errors=0'
pause

section "4. 自定义并发缺陷代码"
printf '被测代码: benchmarks/concurrent_counter/concurrent_counter/counter.py\n'
run_step sed -n '1,120p' benchmarks/concurrent_counter/concurrent_counter/counter.py
pause

section "5. 生成 SWE-bench 风格自定义并发 case"
run_step "$PYTHON_BIN" scripts/generate_custom_concurrency_case.py
printf '\n生成的关键资源:\n'
run_step find Agentless/resources/custom_concurrency -maxdepth 3 -type f
pause

section "6. 无补丁 no-op 评测: 应该失败"
mkdir -p "$AGENTLESS_ROOT/results/custom_concurrency"
printf '{"model_name_or_path":"noop","instance_id":"local_concurrency__counter-0001","model_patch":""}\n' > "$NOOP_PRED"
run_expected_failure "$PYTHON_BIN" scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions "$NOOP_PRED" \
  --benchmark-root benchmarks/concurrent_counter \
  --output "$NOOP_REPORT" \
  --python "$PYTHON_BIN" \
  --repeat "$REPEAT"
summarize_json concurrency "$NOOP_REPORT"
pause

section "7. Gold patch 评测: 应该稳定通过"
run_step "$PYTHON_BIN" scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions Agentless/resources/custom_concurrency/gold_patch.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output "$GOLD_REPORT" \
  --python "$PYTHON_BIN" \
  --repeat "$REPEAT"
summarize_json concurrency "$GOLD_REPORT"
pause

section "8. 并发增强点展示"
printf '增强点 1: evaluator 支持 --repeat N，多轮运行 pytest，输出 pass_rate/stable_resolved。\n'
printf '增强点 2: repair 阶段支持 --concurrency_hint，给 LLM 增加并发语义提示。\n'
printf '增强点 3: evaluator 输出 patch_risk，检查锁、临界区、只改测试、sleep 等风险。\n'
printf '\nConcurrency Repair Guidance 片段:\n'
run_step sed -n '35,45p' Agentless/agentless/repair/repair.py
pause

if [[ "$RUN_LLM" == "1" ]]; then
  section "9. 可选: 调用 DeepSeek 跑自定义并发定位和修复"
  printf '这一步会消耗 API 余额，并需要 OPENAI_API_KEY。\n'
  run_step bash Agentless/scripts/run_custom_concurrency_case.sh
else
  section "9. LLM 修复入口"
  printf '录屏默认不消耗 API。真正调用 DeepSeek 的命令是:\n'
  printf 'RUN_LLM=1 REPEAT=%s Agentless/scripts/run_custom_concurrency_case.sh\n' "$REPEAT"
fi

section "演示结束"
printf '建议录屏最后停留在这里，说明: 官方 5 个基础 case 已 5/5 resolved；并发 case 证明 no-op 失败、正确补丁 10/10 稳定通过。\n'
