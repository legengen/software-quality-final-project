#!/usr/bin/env bash
set -euo pipefail

AGENTLESS_ROOT="${AGENTLESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$AGENTLESS_ROOT/.." && pwd)}"
PYTEST_PYTHON="${PYTEST_PYTHON:-$(command -v python)}"

cd "$AGENTLESS_ROOT"

if [[ ! -d ".venv-agentless" ]]; then
  echo "Missing .venv-agentless. Create/install dependencies before running." >&2
  exit 1
fi

source ".venv-agentless/bin/activate"
export PYTHONPATH="$AGENTLESS_ROOT${PYTHONPATH:+:$PYTHONPATH}"
export PROJECT_FILE_LOC="$AGENTLESS_ROOT/resources/custom_concurrency/project_structures"

MODEL="${MODEL:-deepseek-v4-pro}"
BACKEND="${BACKEND:-deepseek}"
INSTANCE_ID="${INSTANCE_ID:-local_concurrency__counter-0001}"
DATASET="${DATASET:-resources/custom_concurrency/concurrency_cases.json}"
RESULTS="${RESULTS:-results/custom_concurrency/counter}"
RUN_LLM="${RUN_LLM:-0}"
REPEAT="${REPEAT:-10}"

python "$PROJECT_ROOT/scripts/generate_custom_concurrency_case.py"

mkdir -p "$RESULTS"

python "$PROJECT_ROOT/scripts/evaluate_custom_concurrency.py" \
  --dataset "$DATASET" \
  --predictions "resources/custom_concurrency/gold_patch.jsonl" \
  --benchmark-root "$PROJECT_ROOT/benchmarks/concurrent_counter" \
  --output "results/custom_concurrency/gold_evaluation_report.json" \
  --python "$PYTEST_PYTHON" \
  --repeat "$REPEAT"

if [[ "$RUN_LLM" != "1" ]]; then
  echo "Gold evaluation completed. Set RUN_LLM=1 to run LLM localization and repair."
  exit 0
fi

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY is required when RUN_LLM=1." >&2
  exit 2
fi

python agentless/fl/localize.py \
  --file_level \
  --target_id "$INSTANCE_ID" \
  --output_folder "$RESULTS/file_level" \
  --num_threads 1 \
  --model "$MODEL" \
  --backend "$BACKEND" \
  --dataset "$DATASET"

python agentless/fl/localize.py \
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

python agentless/fl/localize.py \
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

python agentless/repair/repair.py \
  --loc_file "$RESULTS/edit_locations/loc_outputs.jsonl" \
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

python "$PROJECT_ROOT/scripts/evaluate_custom_concurrency.py" \
  --dataset "$DATASET" \
  --predictions "$RESULTS/repair/output_0_processed.jsonl" \
  --benchmark-root "$PROJECT_ROOT/benchmarks/concurrent_counter" \
  --output "$RESULTS/evaluation_report.json" \
  --python "$PYTEST_PYTHON" \
  --repeat "$REPEAT"
