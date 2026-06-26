#!/usr/bin/env bash
set -euo pipefail

export AGENTLESS_ROOT="${AGENTLESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$AGENTLESS_ROOT"

if [[ ! -d ".venv-agentless" ]]; then
  echo "Missing .venv-agentless. Create/install dependencies before running." >&2
  exit 1
fi

source ".venv-agentless/bin/activate"
export PYTHONPATH="$AGENTLESS_ROOT${PYTHONPATH:+:$PYTHONPATH}"

export MODEL="${MODEL:-gpt-4o-mini-2024-07-18}"
export BACKEND="${BACKEND:-openai}"
export DATASET="${DATASET:-$AGENTLESS_ROOT/resources/lite5/swebench_lite5.json}"
export EVAL_DATASET="${EVAL_DATASET:-$AGENTLESS_ROOT/resources/lite5/swebench_lite5.json}"
export SMOKE_DATASET="${SMOKE_DATASET:-$AGENTLESS_ROOT/resources/lite5/swebench_lite5_smoke.json}"
export RESULTS="${RESULTS:-results/swe-bench-lite-5-gpt4omini}"
export NUM_THREADS="${NUM_THREADS:-2}"
export NUM_WORKERS="${NUM_WORKERS:-2}"
export TIMEOUT="${TIMEOUT:-1200}"

IDS_DEFAULT=(
  "astropy__astropy-12907"
  "astropy__astropy-14182"
  "astropy__astropy-14365"
  "astropy__astropy-14995"
  "astropy__astropy-6938"
)

if [[ -n "${IDS:-}" ]]; then
  read -r -a IDS_ARR <<< "$IDS"
else
  IDS_ARR=("${IDS_DEFAULT[@]}")
fi

run_docker() {
  if docker version >/dev/null 2>&1; then
    "$@"
  else
    sg docker -c "$(printf '%q ' "$@")"
  fi
}

need_openai_key() {
  if [[ "$BACKEND" == "openai" && -z "${OPENAI_API_KEY:-}" ]]; then
    echo "OPENAI_API_KEY is required for LLM calls." >&2
    exit 2
  fi
}

mkdir -p "$RESULTS"
