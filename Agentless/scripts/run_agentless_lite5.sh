#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/agentless_lite5_env.sh"
need_openai_key

echo "Running Agentless official SWE-bench Lite 5-instance workflow"
echo "Results: $RESULTS"
echo "Model: $MODEL"
echo "Dataset: $DATASET"
printf 'Instances:\n'
printf '  %s\n' "${IDS_ARR[@]}"

run_for_ids() {
  local desc="$1"
  shift
  echo
  echo "== $desc =="
  for id in "${IDS_ARR[@]}"; do
    echo "-- $id"
    "$@" --target_id "$id"
  done
}

run_for_ids "File-level localization" \
  python agentless/fl/localize.py \
    --file_level \
    --output_folder "$RESULTS/file_level" \
    --num_threads "$NUM_THREADS" \
    --skip_existing \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

run_for_ids "Irrelevant-folder localization" \
  python agentless/fl/localize.py \
    --file_level \
    --irrelevant \
    --output_folder "$RESULTS/file_level_irrelevant" \
    --num_threads "$NUM_THREADS" \
    --skip_existing \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

run_for_ids "Embedding retrieval" \
  python agentless/fl/retrieve.py \
    --index_type simple \
    --filter_type given_files \
    --filter_file "$RESULTS/file_level_irrelevant/loc_outputs.jsonl" \
    --output_folder "$RESULTS/retrievel_embedding" \
    --persist_dir "embedding/swe-bench-lite5-simple" \
    --num_threads "$NUM_THREADS" \
    --dataset "$DATASET"

python agentless/fl/combine.py \
  --retrieval_loc_file "$RESULTS/retrievel_embedding/retrieve_locs.jsonl" \
  --model_loc_file "$RESULTS/file_level/loc_outputs.jsonl" \
  --top_n 3 \
  --output_folder "$RESULTS/file_level_combined"

run_for_ids "Related-element localization" \
  python agentless/fl/localize.py \
    --related_level \
    --output_folder "$RESULTS/related_elements" \
    --top_n 3 \
    --compress_assign \
    --compress \
    --start_file "$RESULTS/file_level_combined/combined_locs.jsonl" \
    --num_threads "$NUM_THREADS" \
    --skip_existing \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

run_for_ids "Fine-grain edit-location localization" \
  python agentless/fl/localize.py \
    --fine_grain_line_level \
    --output_folder "$RESULTS/edit_location_samples" \
    --top_n 3 \
    --compress \
    --temperature 0.8 \
    --num_samples 4 \
    --start_file "$RESULTS/related_elements/loc_outputs.jsonl" \
    --num_threads "$NUM_THREADS" \
    --skip_existing \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

python agentless/fl/localize.py \
  --merge \
  --output_folder "$RESULTS/edit_location_individual" \
  --top_n 3 \
  --num_samples 4 \
  --start_file "$RESULTS/edit_location_samples/loc_outputs.jsonl"

for i in 0 1 2 3; do
  sample=$((i + 1))
  run_for_ids "Repair sample $sample" \
    python agentless/repair/repair.py \
      --loc_file "$RESULTS/edit_location_individual/loc_merged_${i}-${i}_outputs.jsonl" \
      --output_folder "$RESULTS/repair_sample_${sample}" \
      --loc_interval \
      --top_n 3 \
      --context_window 10 \
      --max_samples 10 \
      --cot \
      --diff_format \
      --gen_and_process \
      --num_threads "$NUM_THREADS" \
      --model "$MODEL" \
      --backend "$BACKEND" \
      --dataset "$DATASET"
done

run_docker python agentless/test/run_regression_tests.py \
  --run_id "agentless-lite5-base-regression" \
  --output_file "$RESULTS/passing_tests.jsonl" \
  --num_workers "$NUM_WORKERS" \
  --timeout "$TIMEOUT" \
  --instance_ids "${IDS_ARR[@]}" \
  --dataset "$DATASET"

run_for_ids "Select regression tests" \
  python agentless/test/select_regression_tests.py \
    --output_folder "$RESULTS/selected_regression_tests" \
    --passing_tests "$RESULTS/passing_tests.jsonl" \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

for sample in 1 2 3 4; do
  for processed in "$RESULTS/repair_sample_${sample}"/*_processed.jsonl; do
    [[ -e "$processed" ]] || continue
    base="$(basename "$processed" .jsonl)"
    run_docker python agentless/test/run_regression_tests.py \
      --run_id "agentless-lite5-regression-s${sample}-${base}" \
      --predictions_path "$processed" \
      --regression_tests "$RESULTS/selected_regression_tests/output.jsonl" \
      --num_workers "$NUM_WORKERS" \
      --timeout "$TIMEOUT" \
      --instance_ids "${IDS_ARR[@]}" \
      --dataset "$DATASET"
  done
done

run_for_ids "Generate reproduction tests" \
  python agentless/test/generate_reproduction_tests.py \
    --max_samples 40 \
    --output_folder "$RESULTS/reproduction_tests" \
    --model "$MODEL" \
    --backend "$BACKEND" \
    --dataset "$DATASET"

run_docker python agentless/test/run_reproduction_tests.py \
  --run_id "agentless-lite5-reproduction-original" \
  --test_jsonl "$RESULTS/reproduction_tests/output.jsonl" \
  --num_workers "$NUM_WORKERS" \
  --timeout "$TIMEOUT" \
  --instance_ids "${IDS_ARR[@]}" \
  --dataset "$DATASET"

python agentless/test/generate_reproduction_tests.py \
  --select \
  --output_folder "$RESULTS/reproduction_tests_selected" \
  --start_file "$RESULTS/reproduction_tests/output.jsonl" \
  --dataset "$DATASET"

for sample in 1 2 3 4; do
  for processed in "$RESULTS/repair_sample_${sample}"/*_processed.jsonl; do
    [[ -e "$processed" ]] || continue
    base="$(basename "$processed" .jsonl)"
    run_docker python agentless/test/run_reproduction_tests.py \
      --run_id "agentless-lite5-reproduction-s${sample}-${base}" \
      --predictions_path "$processed" \
      --test_jsonl "$RESULTS/reproduction_tests_selected/output.jsonl" \
      --num_workers "$NUM_WORKERS" \
      --timeout "$TIMEOUT" \
      --instance_ids "${IDS_ARR[@]}" \
      --dataset "$DATASET"
  done
done

python agentless/repair/rerank.py \
  --patch_folder "$RESULTS/repair_sample_1,$RESULTS/repair_sample_2,$RESULTS/repair_sample_3,$RESULTS/repair_sample_4" \
  --num_samples 40 \
  --deduplicate \
  --regression \
  --reproduction \
  --output_file "$RESULTS/all_preds.jsonl"

run_docker python -m swebench.harness.run_evaluation \
  --dataset_name "$EVAL_DATASET" \
  --split test \
  --predictions_path "$RESULTS/all_preds.jsonl" \
  --instance_ids "${IDS_ARR[@]}" \
  --max_workers "$NUM_WORKERS" \
  --timeout "$TIMEOUT" \
  --run_id "agentless-lite5-gpt4omini-final"

echo "Workflow completed: $RESULTS/all_preds.jsonl"
