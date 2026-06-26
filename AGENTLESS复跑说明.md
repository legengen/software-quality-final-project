# AGENTLESS 复跑说明

## 1. 基础环境

进入项目目录：

```bash
cd /home/legengen/software-quality-final-project/Agentless
source .venv-agentless/bin/activate
```

配置 WSL 到 Windows 主机代理：

```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
PROXY="http://${HOST_IP}:40558"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"
```

配置 DeepSeek API key：

```bash
export OPENAI_API_KEY='你的 DeepSeek API key'
```

## 2. 单实例官方评测复跑

以 `astropy__astropy-6938` 为例：

```bash
PYTHONPATH=$PWD python -m swebench.harness.run_evaluation   --dataset_name resources/lite5/swebench_lite5_6938.json   --predictions_path results/deepseek-v4pro-lite5/6938/repair_4096/output_0_processed.jsonl   --max_workers 1   --run_id deepseek-v4pro-6938-rerun
```

其他实例替换 dataset 与 predictions 路径即可：

| 实例 | dataset | predictions |
| --- | --- | --- |
| `14182` | `resources/lite5/swebench_lite5_14182.json` | `results/deepseek-v4pro-lite5/14182/repair_cleaned_4096/output_0_processed.manual.jsonl` |
| `14365` | `resources/lite5/swebench_lite5_14365.json` | `results/deepseek-v4pro-lite5/14365/repair_4096/output_0_processed.jsonl` |
| `14995` | `resources/lite5/swebench_lite5_14995.json` | `results/deepseek-v4pro-lite5/14995/repair_4096/output_0_processed.jsonl` |
| `6938` | `resources/lite5/swebench_lite5_6938.json` | `results/deepseek-v4pro-lite5/6938/repair_4096/output_0_processed.jsonl` |

`12907` 使用早前烟测结果：

```bash
PYTHONPATH=$PWD python -m swebench.harness.run_evaluation   --dataset_name resources/lite5/swebench_lite5_smoke.json   --predictions_path results/deepseek-v4pro-smoke/repair_cached_4096/output_0_processed.jsonl   --max_workers 1   --run_id deepseek-v4pro-12907-rerun
```

## 3. 从定位到补丁完整复跑模板

以 `14365` 为例，完整流程如下：

```bash
PYTHONPATH=$PWD python agentless/fl/localize.py   --file_level --target_id astropy__astropy-14365   --output_folder results/deepseek-v4pro-lite5/14365/file_level_4096   --num_threads 1 --skip_existing   --model deepseek-v4-pro --backend deepseek   --dataset resources/lite5/swebench_lite5.json

PYTHONPATH=$PWD python agentless/fl/localize.py   --related_level --target_id astropy__astropy-14365   --output_folder results/deepseek-v4pro-lite5/14365/related_elements   --top_n 3 --compress   --start_file results/deepseek-v4pro-lite5/14365/file_level_4096/loc_outputs.jsonl   --num_threads 1 --skip_existing   --model deepseek-v4-pro --backend deepseek   --dataset resources/lite5/swebench_lite5.json

PYTHONPATH=$PWD python agentless/fl/localize.py   --fine_grain_line_level --target_id astropy__astropy-14365   --output_folder results/deepseek-v4pro-lite5/14365/edit_locations   --top_n 3 --num_samples 1   --start_file results/deepseek-v4pro-lite5/14365/related_elements/loc_outputs.jsonl   --num_threads 1 --skip_existing   --model deepseek-v4-pro --backend deepseek   --dataset resources/lite5/swebench_lite5.json

PYTHONPATH=$PWD python agentless/repair/repair.py   --loc_file results/deepseek-v4pro-lite5/14365/edit_locations/loc_outputs.jsonl   --target_id astropy__astropy-14365   --output_folder results/deepseek-v4pro-lite5/14365/repair_4096   --top_n 3 --context_window 20 --max_tokens 4096 --max_samples 1   --gen_and_process --num_threads 1   --model deepseek-v4-pro --backend deepseek   --dataset resources/lite5/swebench_lite5.json
```

## 4. 查看结果

SWE-bench 汇总报告：

```bash
cat agentless.deepseek-v4pro-14995.json
```

单实例详细测试报告：

```bash
cat logs/run_evaluation/deepseek-v4pro-14995/agentless/astropy__astropy-14995/report.json
```

实际评测 patch：

```bash
cat logs/run_evaluation/deepseek-v4pro-14995/agentless/astropy__astropy-14995/patch.diff
```

## 5. 注意事项

- 不要把 API key 写入文件；只通过环境变量传入。
- Docker 网络失败时，先确认 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY` 是否指向 WSL 默认网关的 `40558` 端口。
- `14182` 的标准 processed 文件为空，使用 `output_0_processed.manual.jsonl` 作为评测输入。
- 若重新生成补丁，会产生新的 LLM 调用并消耗 DeepSeek 余额。
