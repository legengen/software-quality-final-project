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
  --concurrency_hint \
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
  --python "$(command -v python)" \
  --repeat 10
```

评测 gold patch：

```bash
python scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions Agentless/resources/custom_concurrency/gold_patch.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output Agentless/results/custom_concurrency/gold_evaluation_report.json \
  --repeat 10
```

预期结果是 `resolved: 1/1`，`stable_resolved: 1/1`，`average_pass_rate: 1.0`。

如果在 AGENTLESS 虚拟环境中执行 evaluator，而该环境没有安装 pytest，需要用 `--python` 指向一个已安装 pytest 的 Python 解释器。

## 5. 本项目加入的轻量创新点

围绕并发代码修复，本项目增加了三个小改进：

- 并发稳定性评测：`--repeat N` 多次运行 pytest，用 `pass_rate` 和 `stable_resolved` 判断补丁是否稳定。
- 并发语义增强提示：repair 使用 `--concurrency_hint`，提醒 LLM 关注共享状态、读-改-写、锁覆盖和顺序行为。
- 补丁风险检查：evaluator 输出 `patch_risk`，检查是否使用锁、是否保护 `increment/reset`、是否只改测试等。

当前保存结果：

| patch | repeat | pass_rate | stable_resolved | risk_level |
| --- | --- | --- | --- | --- |
| no-op | 10 | 0.0 | false | high |
| gold | 10 | 1.0 | true | low |
