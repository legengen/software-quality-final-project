#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
AGENTLESS_ROOT="$ROOT/Agentless"
PYTEST_PYTHON="${PYTEST_PYTHON:-$(command -v python3)}"
MODEL="${MODEL:-deepseek-v4-pro}"
BACKEND="${BACKEND:-deepseek}"
INSTANCE_ID="${INSTANCE_ID:-local_concurrency__counter-0001}"
DATASET="${DATASET:-resources/custom_concurrency/concurrency_cases.json}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULTS="${RESULTS:-results/custom_concurrency/counter_live_demo_$RUN_ID}"
REPEAT="${REPEAT:-10}"
SLEEP_SECONDS="${SLEEP_SECONDS:-1}"

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

summarize_evaluation() {
  "$PYTEST_PYTHON" - "$1" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
summary = data["summary"]
result = data["results"][0]
risk = result["patch_risk"]

print(
    f"summary: total={summary['total']}, resolved={summary['resolved']}, "
    f"unresolved={summary['unresolved']}, stable_resolved={summary['stable_resolved']}, "
    f"average_pass_rate={summary['average_pass_rate']}"
)
print(
    f"case: {result['instance_id']}, repeat={result['repeat']}, "
    f"passed_runs={result['passed_runs']}, failed_runs={result['failed_runs']}, "
    f"pass_rate={result['pass_rate']}"
)
print(
    f"patch_risk: level={risk['risk_level']}, uses_lock={risk['uses_lock']}, "
    f"guards_increment={risk['guards_increment']}, guards_reset={risk['guards_reset']}"
)
if risk["risk_reasons"]:
    print("risk_reasons:")
    for reason in risk["risk_reasons"]:
        print(f"- {reason}")
PY
}

show_prediction_patch() {
  "$PYTEST_PYTHON" - "$1" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
if not rows:
    raise SystemExit("no prediction rows found")
patch = rows[0].get("model_patch") or rows[0].get("patch") or ""
print(patch.strip() or "<empty patch>")
PY
}

cd "$ROOT"

section "AGENTLESS 自定义并发代码修复演示"
printf 'project root: %s\n' "$ROOT"
printf 'model: %s, backend: %s, repeat: %s\n' "$MODEL" "$BACKEND" "$REPEAT"
printf 'results: Agentless/%s\n' "$RESULTS"

if [[ ! -d "$AGENTLESS_ROOT/.venv-agentless" ]]; then
  printf 'Missing virtual environment: %s\n' "$AGENTLESS_ROOT/.venv-agentless" >&2
  exit 1
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  printf 'OPENAI_API_KEY is required for the live DeepSeek repair demo.\n' >&2
  printf 'Example:\n' >&2
  printf '  export OPENAI_API_KEY=<your-deepseek-api-key>\n' >&2
  exit 2
fi
pause

section "1. 展示并发缺陷代码"
run_step sed -n '1,120p' benchmarks/concurrent_counter/concurrent_counter/counter.py
pause

section "2. 生成 SWE-bench 风格自定义 case 和项目结构快照"
run_step "$PYTEST_PYTHON" scripts/generate_custom_concurrency_case.py
run_step find Agentless/resources/custom_concurrency -maxdepth 3 -type f
pause

section "3. 初始化 AGENTLESS 环境"
cd "$AGENTLESS_ROOT"
source .venv-agentless/bin/activate
export PYTHONPATH="$AGENTLESS_ROOT${PYTHONPATH:+:$PYTHONPATH}"
export PROJECT_FILE_LOC="$AGENTLESS_ROOT/resources/custom_concurrency/project_structures"
mkdir -p "$RESULTS"
printf 'PROJECT_FILE_LOC=%s\n' "$PROJECT_FILE_LOC"
printf 'DATASET=%s\n' "$DATASET"
pause

section "4. File-level localization"
run_step python agentless/fl/localize.py \
  --file_level \
  --target_id "$INSTANCE_ID" \
  --output_folder "$RESULTS/file_level" \
  --num_threads 1 \
  --model "$MODEL" \
  --backend "$BACKEND" \
  --dataset "$DATASET"
run_step sed -n '1,3p' "$RESULTS/file_level/loc_outputs.jsonl"
pause

section "5. Related-level localization"
run_step python agentless/fl/localize.py \
  --related_level \
  --target_id "$INSTANCE_ID" \
  --output_folder "$RESULTS/related_elements" \
  --top_n 3 \
  --compress \
  --start_file "$RESULTS/file_level/loc_outputs.jsonl" \
  --num_threads 1 \
  --model "$MODEL" \
  --backend "$BACKEND" \
  --dataset "$DATASET"
run_step sed -n '1,3p' "$RESULTS/related_elements/loc_outputs.jsonl"
pause

section "6. Fine-grain localization"
run_step python agentless/fl/localize.py \
  --fine_grain_line_level \
  --target_id "$INSTANCE_ID" \
  --output_folder "$RESULTS/edit_locations" \
  --top_n 3 \
  --num_samples 1 \
  --start_file "$RESULTS/related_elements/loc_outputs.jsonl" \
  --num_threads 1 \
  --model "$MODEL" \
  --backend "$BACKEND" \
  --dataset "$DATASET"
run_step sed -n '1,3p' "$RESULTS/edit_locations/loc_outputs.jsonl"

run_step "$PYTEST_PYTHON" "$ROOT/scripts/normalize_custom_concurrency_locs.py" \
  --input "$RESULTS/edit_locations/loc_outputs.jsonl" \
  --output "$RESULTS/edit_locations/loc_outputs.normalized.jsonl"
run_step sed -n '1,3p' "$RESULTS/edit_locations/loc_outputs.normalized.jsonl"
pause

section "7. Repair: DeepSeek 生成并发修复补丁"
run_step python agentless/repair/repair.py \
  --loc_file "$RESULTS/edit_locations/loc_outputs.normalized.jsonl" \
  --target_id "$INSTANCE_ID" \
  --output_folder "$RESULTS/repair" \
  --top_n 3 \
  --context_window 20 \
  --max_tokens 4096 \
  --max_samples 1 \
  --concurrency_hint \
  --gen_and_process \
  --num_threads 1 \
  --model "$MODEL" \
  --backend "$BACKEND" \
  --dataset "$DATASET"

printf '\n生成的模型补丁:\n'
show_prediction_patch "$RESULTS/repair/output_0_processed.jsonl"
pause

section "8. 评测模型补丁"
run_step "$PYTEST_PYTHON" "$ROOT/scripts/evaluate_custom_concurrency.py" \
  --dataset "$DATASET" \
  --predictions "$RESULTS/repair/output_0_processed.jsonl" \
  --benchmark-root "$ROOT/benchmarks/concurrent_counter" \
  --output "$RESULTS/evaluation_report.json" \
  --python "$PYTEST_PYTHON" \
  --repeat "$REPEAT"

summarize_evaluation "$RESULTS/evaluation_report.json"
pause

section "演示结束"
printf '输出目录: %s/%s\n' "$AGENTLESS_ROOT" "$RESULTS"
printf '关键文件:\n'
printf '%s\n' "- $RESULTS/file_level/loc_outputs.jsonl"
printf '%s\n' "- $RESULTS/related_elements/loc_outputs.jsonl"
printf '%s\n' "- $RESULTS/edit_locations/loc_outputs.jsonl"
printf '%s\n' "- $RESULTS/edit_locations/loc_outputs.normalized.jsonl"
printf '%s\n' "- $RESULTS/repair/output_0_processed.jsonl"
printf '%s\n' "- $RESULTS/evaluation_report.json"
