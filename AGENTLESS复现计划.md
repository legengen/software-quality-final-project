# AGENTLESS 官方流程复现计划

## Summary

- 目标：使用 `OpenAutoCoder/Agentless` 官方流程，在 `SWE-bench Lite` 上跑 5 个固定样例，复现 `localization -> repair -> patch validation/selection -> SWE-bench evaluation`。
- 复现配置：`gpt-4o-mini-2024-07-18`，保留官方采样规模：4 组 edit locations × 每组 10 个 patch，共 40 个候选补丁；reproduction test 也生成 40 个样本。
- 数据集：`princeton-nlp/SWE-bench_Lite`。
- 固定样例：
  - `sqlfluff__sqlfluff-1625`
  - `sqlfluff__sqlfluff-2419`
  - `sqlfluff__sqlfluff-1733`
  - `sqlfluff__sqlfluff-1517`
  - `sqlfluff__sqlfluff-1763`
- 参考资料：
  - 论文 PDF：https://arxiv.org/pdf/2407.01489
  - Agentless README：https://raw.githubusercontent.com/OpenAutoCoder/Agentless/main/README_swebench.md
  - SWE-bench README：https://raw.githubusercontent.com/swe-bench/SWE-bench/main/README.md
  - SWE-bench Lite 数据集：https://huggingface.co/datasets/princeton-nlp/SWE-bench_Lite

## Key Changes

- 不改 Agentless 官方算法；只在本地新增复现实验目录、运行脚本、记录文档和结果文件。
- 使用 WSL 本地路径 `/home/legengen/software-quality-final-project/Agentless`，避免在 `/mnt/g` 下跑 Docker、依赖安装和大量 I/O。
- 安装 Conda 环境：

```bash
conda create -n agentless python=3.11
conda activate agentless
pip install -r requirements.txt
export PYTHONPATH=$(pwd)
```

- 使用 `OPENAI_API_KEY` 调 OpenAI-compatible 官方 OpenAI backend。
- embedding 检索继续使用官方默认 `text-embedding-3-small`。
- 最终公共产物是 SWE-bench prediction 格式的 `all_preds.jsonl`，每行包含：
  - `model_name_or_path`
  - `instance_id`
  - `model_patch`

## Implementation Plan

1. 环境预检

   - 确认 Docker 可运行。
   - 确认磁盘空间尽量满足 SWE-bench 推荐的约 120GB。
   - 确认 `git`、`curl` 可用。
   - 若 Conda 缺失，安装 Miniconda 或 Mambaforge。

2. 克隆并固定官方代码

```bash
git clone https://github.com/OpenAutoCoder/Agentless.git
cd Agentless
git checkout v1.5.0
```

若 `v1.5.0` tag 不可用，则记录实际 commit hash。

3. 准备官方预处理结构

   - 下载官方预处理结构包 `swebench_lite_repo_structure.zip`。
   - 解压后设置 `PROJECT_FILE_LOC`。
   - 如果下载失败，则使用官方代码现场 checkout/preprocess。

4. 定义固定变量

```bash
export MODEL=gpt-4o-mini-2024-07-18
export BACKEND=openai
export DATASET=princeton-nlp/SWE-bench_Lite
export RESULTS=results/swe-bench-lite-5-gpt4omini
export IDS="sqlfluff__sqlfluff-1625 sqlfluff__sqlfluff-2419 sqlfluff__sqlfluff-1733 sqlfluff__sqlfluff-1517 sqlfluff__sqlfluff-1763"
```

5. Localization

   - 对 5 个 `target_id` 循环执行官方 file-level localization。
   - 执行 irrelevant-folder localization。
   - 执行 embedding retrieval。
   - 执行 `combine.py` 合并定位结果。
   - 执行 related-level localization。
   - 执行 fine-grain edit-location sampling。
   - 执行 `--merge`，产出 4 个 `loc_merged_{i}-{i}_outputs.jsonl`。

6. Repair

   - 对 4 个 merged localization 文件分别运行 `agentless/repair/repair.py`。
   - 固定参数：

```bash
--top_n 3
--context_window 10
--max_samples 10
--loc_interval
--cot
--diff_format
--gen_and_process
--model $MODEL
--backend $BACKEND
```

7. Patch validation

   - 使用 `run_regression_tests.py --instance_ids $IDS` 生成 passing tests。
   - 使用 `select_regression_tests.py --instance_ids $IDS` 过滤 regression tests。
   - 对 4 × 10 个 processed patch 文件分别跑 regression test。

8. Reproduction tests

   - 对 5 个样例循环运行 `generate_reproduction_tests.py --max_samples 40`。
   - 执行 40 个 reproduction test 候选在原始 repo 上的验证。
   - 执行 `--select` 得到每个 issue 的最终 reproduction test。
   - 对 4 × 10 个 patch 文件跑 reproduction test。

9. Rerank

   - 运行 `agentless/repair/rerank.py`。
   - 输入 patch folders：
     - `repair_sample_1`
     - `repair_sample_2`
     - `repair_sample_3`
     - `repair_sample_4`
   - 固定参数：

```bash
--num_samples 40
--deduplicate
--regression
--reproduction
--output_file $RESULTS/all_preds.jsonl
```

10. Final evaluation

使用 SWE-bench harness 评测 `all_preds.jsonl`：

```bash
python -m swebench.harness.run_evaluation \
  --dataset_name princeton-nlp/SWE-bench_Lite \
  --predictions_path $RESULTS/all_preds.jsonl \
  --instance_ids $IDS \
  --max_workers 2 \
  --run_id agentless-lite-5-gpt4omini
```

11. 结果记录

   - 保存 `all_preds.jsonl`。
   - 保存 `evaluation_results/`。
   - 保存各阶段 logs。
   - 记录每阶段 token/cost 统计。
   - 汇总 5 个样例的 resolved/failed 表格。

## Test Plan

- 冒烟测试：先用 `--predictions_path gold --dataset_name princeton-nlp/SWE-bench_Lite --instance_ids sqlfluff__sqlfluff-1625` 验证 Docker/SWE-bench harness 可用。
- 阶段检查：localization 输出应有 5 行。
- Repair 检查：每个 sample folder 应有 10 个 processed JSONL，每个 JSONL 应覆盖 5 个 `instance_id`。
- 验证检查：regression/reproduction result JSONL 均生成。
- Prediction 检查：`all_preds.jsonl` 必须正好 5 行，且 patch 字段格式可被 SWE-bench harness 读取。
- 成功标准：
  - 完整流程无未处理异常。
  - 最终 evaluation 产出 resolved count。
  - 报告中说明 resolved 数、失败样例、API 成本、与论文 GPT-4o/300 样例设置的差异。

## Assumptions

- 使用官方流程子集，不追求复现论文 300 个 SWE-bench Lite 的 32.00% 总体结果。
- 使用 `gpt-4o-mini-2024-07-18` 是成本优化，结果不能直接等同论文默认 `gpt-4o-2024-05-13`。
- 若某个样例因 Docker 镜像或依赖问题无法评测，不替换样例；记录为环境失败，保证样例选择不被结果驱动。
