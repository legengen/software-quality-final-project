#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/agentless_lite5_env.sh"

echo "Python: $(python --version)"
echo "SWE-bench: $(python - <<'PY'
import importlib.metadata as m
print(m.version("swebench"))
PY
)"
echo "Docker:"
run_docker docker version --format '{{.Client.Version}} client / {{.Server.Version}} server'

echo "Running one gold-prediction SWE-bench smoke test..."
run_docker python -m swebench.harness.run_evaluation \
  --dataset_name "$SMOKE_DATASET" \
  --split test \
  --predictions_path gold \
  --instance_ids "${IDS_ARR[0]}" \
  --max_workers 1 \
  --timeout "$TIMEOUT" \
  --run_id "agentless-lite5-gold-smoke"

echo "Smoke test completed."
