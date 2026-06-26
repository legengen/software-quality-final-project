# AGENTLESS 自定义并发案例说明

本文档说明如何把课程要求中的“并发代码修复”加入当前 AGENTLESS 复现流程。

## 1. 案例设计

自定义项目位于 `benchmarks/concurrent_counter/`。其中 `ConcurrentCounter.increment()` 故意存在共享状态竞态：

- 多个线程可能同时读取相同的旧值；
- 每个线程再写回 `old_value + amount`；
- 因此并发累加会丢失更新。

基础项目只包含顺序行为回归测试。并发失败测试通过 SWE-bench 风格的 `test_patch` 提供，资源文件位于：

- `Agentless/resources/custom_concurrency/concurrency_cases.json`
- `Agentless/resources/custom_concurrency/project_structures/local_concurrency__counter-0001.json`
- `Agentless/resources/custom_concurrency/gold_patch.jsonl`

## 2. 生成资源

如果修改了样例项目，重新生成 case 资源：

```bash
python scripts/generate_custom_concurrency_case.py
```

## 3. 运行 AGENTLESS 定位与修复

推荐先运行默认脚本验证自定义 case 和 gold patch，不会调用 LLM：

```bash
Agentless/scripts/run_custom_concurrency_case.sh
```

确认需要消耗 LLM API 时，再设置 `RUN_LLM=1`：

```bash
RUN_LLM=1 Agentless/scripts/run_custom_concurrency_case.sh
```

下面是拆开的手动流程。

```bash
cd Agentless
source .venv-agentless/bin/activate
export PYTHONPATH=$PWD
export PROJECT_FILE_LOC=$PWD/resources/custom_concurrency/project_structures
export OPENAI_API_KEY='你的 DeepSeek API key'

PYTHONPATH=$PWD python agentless/fl/localize.py \
  --file_level \
  --target_id local_concurrency__counter-0001 \
  --output_folder results/custom_concurrency/counter/file_level \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/custom_concurrency/concurrency_cases.json

PYTHONPATH=$PWD python agentless/fl/localize.py \
  --related_level \
  --target_id local_concurrency__counter-0001 \
  --output_folder results/custom_concurrency/counter/related_elements \
  --top_n 3 \
  --compress \
  --start_file results/custom_concurrency/counter/file_level/loc_outputs.jsonl \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/custom_concurrency/concurrency_cases.json

PYTHONPATH=$PWD python agentless/fl/localize.py \
  --fine_grain_line_level \
  --target_id local_concurrency__counter-0001 \
  --output_folder results/custom_concurrency/counter/edit_locations \
  --top_n 3 \
  --num_samples 1 \
  --start_file results/custom_concurrency/counter/related_elements/loc_outputs.jsonl \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/custom_concurrency/concurrency_cases.json

PYTHONPATH=$PWD python agentless/repair/repair.py \
  --loc_file results/custom_concurrency/counter/edit_locations/loc_outputs.jsonl \
  --target_id local_concurrency__counter-0001 \
  --output_folder results/custom_concurrency/counter/repair \
  --top_n 3 \
  --context_window 20 \
  --max_tokens 4096 \
  --max_samples 1 \
  --gen_and_process \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/custom_concurrency/concurrency_cases.json
```

## 4. 本地评测

评测 LLM 生成的补丁：

```bash
python ../scripts/evaluate_custom_concurrency.py \
  --dataset resources/custom_concurrency/concurrency_cases.json \
  --predictions results/custom_concurrency/counter/repair/output_0_processed.jsonl \
  --benchmark-root ../benchmarks/concurrent_counter \
  --output results/custom_concurrency/counter/evaluation_report.json \
  --python "$(command -v python)"
```

评测 gold patch：

```bash
python scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions Agentless/resources/custom_concurrency/gold_patch.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output Agentless/results/custom_concurrency/gold_evaluation_report.json
```

预期结果是 `resolved: 1/1`。

如果在 AGENTLESS 虚拟环境中执行 evaluator，而该环境没有安装 pytest，需要用 `--python` 指向一个已安装 pytest 的 Python 解释器。
