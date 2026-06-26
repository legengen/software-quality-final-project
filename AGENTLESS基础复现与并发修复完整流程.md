# AGENTLESS 基础复现与并发代码修复完整流程

本文档用于说明本项目从“复现 AGENTLESS 使用 LLM 自动修复 SWE-bench 代码缺陷”到“新增自定义并发缺陷并让 LLM 修复”的完整流程。文档面向课程作业提交与后续复跑，重点解释每一步的目的、输入输出、关键命令和结果判断方式。

## 1. 项目整体目标

本项目分为两个阶段：

1. 基础复现阶段：在本地 WSL + Docker 环境中运行 AGENTLESS，对 SWE-bench Lite 中 5 个 Astropy 基础案例执行定位、修复和官方测试评测。
2. 并发修复扩展阶段：新增一个自定义并发缺陷项目，将其包装成 SWE-bench 风格 case，让 AGENTLESS 调用 LLM 生成补丁，并用本地 evaluator 验证并发 bug 是否被修复。

两个阶段的共同核心是：

- case 表示一个缺陷修复任务，不等于一个代码文件；
- LLM 根据 issue/problem statement、仓库结构和代码上下文生成补丁；
- 补丁采用 unified diff 形式；
- 评测脚本应用补丁并运行测试；
- 测试通过才认为该 case resolved。

## 2. 关键目录和文件

项目根目录：

```text
/home/legengen/software-quality-final-project
```

主要目录如下：

```text
Agentless/                                      AGENTLESS 源码、适配代码、结果和评测日志
Agentless/resources/lite5/                     5 个 SWE-bench Lite 基础案例数据
Agentless/results/deepseek-v4pro-lite5/        DeepSeek 基础案例定位和修复输出
Agentless/logs/run_evaluation/                 SWE-bench Docker 官方评测日志
Agentless/resources/custom_concurrency/        自定义并发 case 数据和结构快照
Agentless/results/custom_concurrency/          自定义并发 case 评测报告
benchmarks/concurrent_counter/                 自定义并发缺陷样例项目
scripts/generate_custom_concurrency_case.py    生成自定义并发 case 资源
scripts/evaluate_custom_concurrency.py         本地评测自定义并发补丁
```

主要文档如下：

```text
AGENTLESS复现最终报告.md
AGENTLESS复现实验记录.md
AGENTLESS复跑说明.md
AGENTLESS自定义并发案例说明.md
AGENTLESS基础复现与并发修复完整流程.md
```

## 3. 基础概念说明

### 3.1 一个 case 是什么

在 SWE-bench / AGENTLESS 中，一个 case 是一个真实缺陷修复任务，通常对应一个 GitHub issue 或 PR。一个 case 至少包含：

- `instance_id`：案例编号，例如 `astropy__astropy-14995`；
- `repo`：目标仓库，例如 `astropy/astropy`；
- `base_commit`：修复前的代码版本；
- `problem_statement`：问题描述；
- `test_patch`：用于暴露 bug 的测试补丁；
- `FAIL_TO_PASS`：修复前失败、修复后应通过的测试；
- `PASS_TO_PASS`：修复前后都应通过的回归测试。

一个 case 可能只修改一个代码文件，也可能修改多个代码文件。它不是“一个文件”，而是“一个软件缺陷修复任务”。

### 3.2 AI 生成的补丁是什么

AGENTLESS 最终会把 LLM 输出处理成 unified diff，也就是 Git 常见的 `.diff` / `.patch` 格式，例如：

```diff
diff --git a/astropy/io/fits/fitsrec.py b/astropy/io/fits/fitsrec.py
--- a/astropy/io/fits/fitsrec.py
+++ b/astropy/io/fits/fitsrec.py
@@ -1261,7 +1261,7 @@ class FITS_rec(np.recarray):
-            output_field.replace(encode_ascii('E'), encode_ascii('D'))
+            output_field[:] = output_field.replace(encode_ascii('E'), encode_ascii('D'))
```

其中：

- `diff --git` 表示修改的文件；
- `---` 是修改前文件；
- `+++` 是修改后文件；
- `@@` 是修改发生的位置；
- `-` 开头是删除行；
- `+` 开头是新增行；
- 其他行是上下文。

### 3.3 Docker 的作用

Docker 不负责生成补丁，它负责评测补丁。

在基础复现阶段，SWE-bench harness 会为目标项目创建隔离环境：

- checkout 到指定 `base_commit`；
- 应用 LLM 生成的 patch；
- 安装对应依赖；
- 运行 `FAIL_TO_PASS` 和 `PASS_TO_PASS` 测试；
- 输出 `resolved: true/false`。

这样做的目的是保证评测尽量接近官方环境，避免本机 Python 包版本影响结果。

### 3.4 DeepSeek 生成补丁依据什么

DeepSeek V4 Pro High 不是直接看测试结果随意修改，而是根据 AGENTLESS 提供的上下文生成补丁。上下文主要来自：

1. problem statement：问题描述；
2. repository structure：仓库结构；
3. file-level localization 结果：模型认为要改哪些文件；
4. related-level localization 结果：相关类、函数或方法；
5. fine-grain localization 结果：具体代码行；
6. repair 阶段拼接出的代码上下文。

然后 AGENTLESS 将模型输出的 `edit_file(...)` 或 diff 内容后处理为 unified diff，再交给评测环境运行测试。

## 4. 基础复现阶段：SWE-bench Lite 5 个案例

### 4.1 环境准备

进入 AGENTLESS 项目：

```bash
cd /home/legengen/software-quality-final-project/Agentless
source .venv-agentless/bin/activate
export PYTHONPATH=$PWD
```

如果 WSL 是非镜像网络，并且需要走 Windows 主机代理，先配置代理：

```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
PROXY="http://${HOST_IP}:40558"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"
```

配置 DeepSeek API key。不要把真实 key 写入文件，只放在当前 shell 环境变量中：

```bash
export OPENAI_API_KEY='你的 DeepSeek API key'
```

确认 Docker 可用：

```bash
docker version
```

### 4.2 本项目对 AGENTLESS 做过的适配

为了在本地完成复现，已经完成以下改动：

- 增加 DeepSeek backend 与 `deepseek-v4-pro` 模型选项；
- repair 增加 `--max_tokens` 参数，避免输出预算不足；
- 增加本地 JSON dataset 加载能力；
- SWE-bench Docker build 支持代理环境变量；
- 后处理器支持解析 keyword 参数形式的 `edit_file(...)`；
- 增加复跑脚本和结果记录。

相关代码主要在：

```text
Agentless/agentless/util/model.py
Agentless/agentless/util/dataset.py
Agentless/agentless/repair/repair.py
Agentless/agentless/util/postprocess_data.py
Agentless/scripts/
```

### 4.3 基础案例数据

本次基础复现使用 5 个 Astropy case：

| instance_id | 简要问题 | 结果 |
| --- | --- | --- |
| `astropy__astropy-12907` | modeling separability | resolved |
| `astropy__astropy-14182` | RST `header_rows` | unresolved |
| `astropy__astropy-14365` | QDP command case | unresolved |
| `astropy__astropy-14995` | NDData mask propagation | resolved |
| `astropy__astropy-6938` | FITS D exponent writeback | resolved |

基础数据位于：

```text
Agentless/resources/lite5/swebench_lite5.json
```

单 case 数据位于：

```text
Agentless/resources/lite5/swebench_lite5_14182.json
Agentless/resources/lite5/swebench_lite5_14365.json
Agentless/resources/lite5/swebench_lite5_14995.json
Agentless/resources/lite5/swebench_lite5_6938.json
Agentless/resources/lite5/swebench_lite5_smoke.json
```

### 4.4 AGENTLESS 官方式修复流程

每个 case 的主流程如下：

```text
problem statement
    -> file-level localization
    -> related-level localization
    -> fine-grain localization
    -> repair
    -> postprocess to unified diff
    -> SWE-bench Docker evaluation
```

以 `astropy__astropy-14365` 为例，完整命令如下。

第一步，文件级定位：

```bash
PYTHONPATH=$PWD python agentless/fl/localize.py \
  --file_level \
  --target_id astropy__astropy-14365 \
  --output_folder results/deepseek-v4pro-lite5/14365/file_level_4096 \
  --num_threads 1 \
  --skip_existing \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/lite5/swebench_lite5.json
```

第二步，相关元素定位：

```bash
PYTHONPATH=$PWD python agentless/fl/localize.py \
  --related_level \
  --target_id astropy__astropy-14365 \
  --output_folder results/deepseek-v4pro-lite5/14365/related_elements \
  --top_n 3 \
  --compress \
  --start_file results/deepseek-v4pro-lite5/14365/file_level_4096/loc_outputs.jsonl \
  --num_threads 1 \
  --skip_existing \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/lite5/swebench_lite5.json
```

第三步，细粒度行级定位：

```bash
PYTHONPATH=$PWD python agentless/fl/localize.py \
  --fine_grain_line_level \
  --target_id astropy__astropy-14365 \
  --output_folder results/deepseek-v4pro-lite5/14365/edit_locations \
  --top_n 3 \
  --num_samples 1 \
  --start_file results/deepseek-v4pro-lite5/14365/related_elements/loc_outputs.jsonl \
  --num_threads 1 \
  --skip_existing \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/lite5/swebench_lite5.json
```

第四步，生成修复补丁：

```bash
PYTHONPATH=$PWD python agentless/repair/repair.py \
  --loc_file results/deepseek-v4pro-lite5/14365/edit_locations/loc_outputs.jsonl \
  --target_id astropy__astropy-14365 \
  --output_folder results/deepseek-v4pro-lite5/14365/repair_4096 \
  --top_n 3 \
  --context_window 20 \
  --max_tokens 4096 \
  --max_samples 1 \
  --gen_and_process \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/lite5/swebench_lite5.json
```

repair 输出中最关键的是：

```text
output.jsonl                  原始模型输出
output_0_processed.jsonl      后处理后的 SWE-bench patch
repair_logs/                  repair prompt 和响应日志
```

### 4.5 官方 SWE-bench Docker 评测

评测 `astropy__astropy-6938`：

```bash
PYTHONPATH=$PWD python -m swebench.harness.run_evaluation \
  --dataset_name resources/lite5/swebench_lite5_6938.json \
  --predictions_path results/deepseek-v4pro-lite5/6938/repair_4096/output_0_processed.jsonl \
  --max_workers 1 \
  --run_id deepseek-v4pro-6938-rerun
```

其他 case 替换 dataset 和 predictions：

| case | dataset | predictions |
| --- | --- | --- |
| `12907` | `resources/lite5/swebench_lite5_smoke.json` | `results/deepseek-v4pro-smoke/repair_cached_4096/output_0_processed.jsonl` |
| `14182` | `resources/lite5/swebench_lite5_14182.json` | `results/deepseek-v4pro-lite5/14182/repair_cleaned_4096/output_0_processed.manual.jsonl` |
| `14365` | `resources/lite5/swebench_lite5_14365.json` | `results/deepseek-v4pro-lite5/14365/repair_4096/output_0_processed.jsonl` |
| `14995` | `resources/lite5/swebench_lite5_14995.json` | `results/deepseek-v4pro-lite5/14995/repair_4096/output_0_processed.jsonl` |
| `6938` | `resources/lite5/swebench_lite5_6938.json` | `results/deepseek-v4pro-lite5/6938/repair_4096/output_0_processed.jsonl` |

查看汇总报告：

```bash
cat agentless.deepseek-v4pro-14995.json
```

查看单实例详细报告：

```bash
cat logs/run_evaluation/deepseek-v4pro-14995/agentless/astropy__astropy-14995/report.json
```

查看实际评测 patch：

```bash
cat logs/run_evaluation/deepseek-v4pro-14995/agentless/astropy__astropy-14995/patch.diff
```

### 4.6 基础复现结果

最终 5 个基础 case 全部完成评测：

| 指标 | 数值 |
| --- | --- |
| 总案例数 | 5 |
| 完成评测 | 5 |
| resolved | 3 |
| unresolved | 2 |
| error | 0 |

成功案例：

- `astropy__astropy-12907`
- `astropy__astropy-14995`
- `astropy__astropy-6938`

未成功案例：

- `astropy__astropy-14182`：模型补丁未完整处理 RST 多行 header 的状态和行偏移；
- `astropy__astropy-14365`：模型补丁只处理了命令大小写，未完整处理数据中 `NO/no` 的语义转换。

这说明基础流程已经跑通，但单样本 repair 仍可能生成局部正确、全局语义不完整的补丁。

## 5. 并发代码修复扩展阶段

### 5.1 为什么需要自定义并发 case

课程作业如果要求“完成并发代码的修复”，仅复现 Astropy 的 5 个普通 bug 不够贴合主题。因此本项目新增了一个自定义并发缺陷项目：

```text
benchmarks/concurrent_counter/
```

该项目很小，便于说明并发 bug、构造稳定测试和展示 LLM 生成补丁。

### 5.2 自定义并发项目设计

核心文件：

```text
benchmarks/concurrent_counter/concurrent_counter/counter.py
```

原始代码中 `ConcurrentCounter.increment()` 故意没有加锁：

```python
old_value = self._value
time.sleep(0.00001)
self._value = old_value + amount
return self._value
```

该代码在单线程下正确，但多线程并发执行时会出现典型的读-改-写竞态：

1. 线程 A 读取旧值 `old_value = 10`；
2. 线程 B 也读取旧值 `old_value = 10`；
3. 线程 A 写回 `11`；
4. 线程 B 也写回 `11`；
5. 实际执行了两次 increment，但结果只增加了 1。

基础项目只保留顺序行为测试：

```text
benchmarks/concurrent_counter/tests/test_counter.py
```

并发失败测试不直接放入基础项目，而是通过 `test_patch` 加入。这与 SWE-bench 的方式一致：base commit 中存在 bug，test patch 用于暴露 bug。

### 5.3 自定义 case 的 SWE-bench 风格资源

自定义 case 数据位于：

```text
Agentless/resources/custom_concurrency/concurrency_cases.json
```

其中关键字段包括：

- `instance_id`: `local_concurrency__counter-0001`
- `repo`: `local/concurrent_counter`
- `base_commit`: `local-concurrency-base`
- `problem_statement`: 并发丢失更新的问题描述；
- `test_patch`: 新增并发失败测试；
- `FAIL_TO_PASS`: 并发测试；
- `PASS_TO_PASS`: 顺序行为回归测试。

AGENTLESS 还需要仓库结构快照：

```text
Agentless/resources/custom_concurrency/project_structures/local_concurrency__counter-0001.json
```

gold patch 位于：

```text
Agentless/resources/custom_concurrency/gold_patch.jsonl
```

gold patch 的作用是验证 evaluator 的正确性：它不是 LLM 结果，而是人工写出的标准修复补丁，用来证明测试能区分 buggy 和 fixed。

### 5.4 生成自定义 case 资源

如果修改了 `benchmarks/concurrent_counter/`，需要重新生成资源：

```bash
python scripts/generate_custom_concurrency_case.py
```

该脚本会生成：

```text
Agentless/resources/custom_concurrency/concurrency_cases.json
Agentless/resources/custom_concurrency/project_structures/local_concurrency__counter-0001.json
Agentless/resources/custom_concurrency/gold_patch.jsonl
```

### 5.5 自定义并发 evaluator

因为 SWE-bench 官方 Docker harness 默认支持的是官方数据集和项目镜像，自定义本地并发项目不直接进入官方 Docker 闭环。因此本项目新增本地 evaluator：

```text
scripts/evaluate_custom_concurrency.py
```

它的流程是：

1. 读取自定义 dataset；
2. 读取 AGENTLESS 或 gold 生成的 predictions JSONL；
3. 复制 `benchmarks/concurrent_counter/` 到临时目录；
4. 初始化 Git 仓库；
5. 应用 `test_patch`；
6. 应用模型 patch；
7. 运行 pytest；
8. 输出 `resolved / unresolved` 报告。

evaluator 支持两种 patch 路径：

- `concurrent_counter/counter.py`
- `concurrent_counter/concurrent_counter/counter.py`

这是为了兼容 AGENTLESS 仓库结构快照中可能带顶层项目目录的情况。

### 5.6 验证自定义并发 case 是否可靠

先验证基础项目的顺序测试：

```bash
cd /home/legengen/software-quality-final-project/benchmarks/concurrent_counter
python -m pytest -q
```

预期：

```text
2 passed
```

再验证 no-op 补丁。no-op 表示不修复，只应用并发测试，应该失败：

```bash
python scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions /tmp/custom_concurrency_noop.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output Agentless/results/custom_concurrency/noop_evaluation_report.json
```

当前项目已保存 no-op 评测结果：

```text
Agentless/results/custom_concurrency/noop_evaluation_report.json
```

结果为：

```text
total: 1
resolved: 0
unresolved: 1
```

再验证 gold patch，应该通过：

```bash
python scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions Agentless/resources/custom_concurrency/gold_patch.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output Agentless/results/custom_concurrency/gold_evaluation_report.json
```

当前项目已保存 gold 评测结果：

```text
Agentless/results/custom_concurrency/gold_evaluation_report.json
```

结果为：

```text
total: 1
resolved: 1
unresolved: 0
```

这证明自定义并发测试是有效的：不修复会失败，正确修复会通过。

### 5.7 一键运行自定义并发流程

项目提供脚本：

```text
Agentless/scripts/run_custom_concurrency_case.sh
```

默认运行不会调用 LLM，只会重新生成资源并验证 gold patch：

```bash
Agentless/scripts/run_custom_concurrency_case.sh
```

如果要真正调用 DeepSeek 让 LLM 修复并发 bug：

```bash
export OPENAI_API_KEY='你的 DeepSeek API key'
RUN_LLM=1 Agentless/scripts/run_custom_concurrency_case.sh
```

脚本内部会执行：

1. 生成自定义 case 资源；
2. 设置 `PROJECT_FILE_LOC`，让 AGENTLESS 读取本地结构快照；
3. file-level localization；
4. related-level localization；
5. fine-grain localization；
6. repair；
7. 用 `evaluate_custom_concurrency.py` 评测 LLM patch。

### 5.8 手动运行自定义并发 LLM 修复

进入 AGENTLESS：

```bash
cd /home/legengen/software-quality-final-project/Agentless
source .venv-agentless/bin/activate
export PYTHONPATH=$PWD
export PROJECT_FILE_LOC=$PWD/resources/custom_concurrency/project_structures
export OPENAI_API_KEY='你的 DeepSeek API key'
```

文件级定位：

```bash
PYTHONPATH=$PWD python agentless/fl/localize.py \
  --file_level \
  --target_id local_concurrency__counter-0001 \
  --output_folder results/custom_concurrency/counter/file_level \
  --num_threads 1 \
  --model deepseek-v4-pro \
  --backend deepseek \
  --dataset resources/custom_concurrency/concurrency_cases.json
```

相关元素定位：

```bash
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
```

细粒度定位：

```bash
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
```

生成补丁：

```bash
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

评测 LLM 补丁：

```bash
python ../scripts/evaluate_custom_concurrency.py \
  --dataset resources/custom_concurrency/concurrency_cases.json \
  --predictions results/custom_concurrency/counter/repair/output_0_processed.jsonl \
  --benchmark-root ../benchmarks/concurrent_counter \
  --output results/custom_concurrency/counter/evaluation_report.json \
  --python "$(command -v python)"
```

如果 AGENTLESS 虚拟环境没有安装 pytest，需要用 `--python` 指向已安装 pytest 的解释器。

## 6. 两个阶段的区别

| 项目 | 基础 SWE-bench 复现 | 自定义并发修复 |
| --- | --- | --- |
| case 来源 | SWE-bench Lite Astropy | 本地构造 |
| 目标 | 复现论文/官方流程 | 满足课程并发修复要求 |
| 被修项目 | Astropy | `concurrent_counter` |
| 测试来源 | SWE-bench 官方 FAIL_TO_PASS / PASS_TO_PASS | 自定义 pytest 测试 |
| 评测方式 | SWE-bench Docker harness | 本地 evaluator + pytest |
| 是否使用 LLM | 是 | 默认 gold 验证不使用，`RUN_LLM=1` 时使用 |
| resolved 判断 | 官方 report | evaluator report |

基础阶段证明 AGENTLESS + DeepSeek 的端到端流程能跑通；并发阶段证明同一套定位和 repair 思路可以迁移到课程指定的并发缺陷修复任务。

## 7. 常见问题

### 7.1 Docker 网络失败怎么办

先配置 WSL 到主机代理：

```bash
HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
PROXY="http://${HOST_IP}:40558"
export HTTP_PROXY="$PROXY"
export HTTPS_PROXY="$PROXY"
export ALL_PROXY="$PROXY"
```

然后重新运行 Docker build 或 SWE-bench evaluation。

### 7.2 为什么自定义并发 case 不直接用 SWE-bench 官方 Docker

SWE-bench 官方 Docker harness 对官方 benchmark 项目有完整镜像、依赖和测试规范。自定义本地小项目如果要进入官方 harness，需要额外实现项目映射、镜像构建和 spec 适配。当前课程作业更需要证明“LLM 能修复并发代码”，因此使用本地 evaluator 更直接、稳定、可解释。

如果后续必须使用 Docker，也可以把 `benchmarks/concurrent_counter` 封装成 Docker 镜像，在 evaluator 中用 Docker 运行 pytest。这属于下一阶段增强，不影响当前流程。

### 7.3 为什么默认脚本不直接调用 LLM

调用 LLM 会消耗 API 余额。`Agentless/scripts/run_custom_concurrency_case.sh` 默认只验证 gold patch，确认资源和评测逻辑正常。只有显式设置：

```bash
RUN_LLM=1
```

脚本才会执行 localization 和 repair。

### 7.4 如何判断 LLM 是否真的修好了并发 bug

看 evaluator 输出：

```text
Agentless/results/custom_concurrency/counter/evaluation_report.json
```

如果：

```json
{
  "summary": {
    "total": 1,
    "resolved": 1,
    "unresolved": 0
  }
}
```

则说明 LLM patch 应用成功，新增并发测试和回归测试均通过。

## 8. 当前已完成的成果

基础复现：

- 5 个 SWE-bench Lite Astropy case 全部完成评测；
- 3 个 resolved；
- 2 个 unresolved；
- 0 个 error。

并发扩展：

- 已新增 `ConcurrentCounter` 并发竞态缺陷；
- 已生成 SWE-bench 风格自定义 case；
- 已实现本地 evaluator；
- 已验证 no-op patch 为 unresolved；
- 已验证 gold patch 为 resolved；
- 已提供一键脚本用于后续调用 LLM 修复。

## 9. 提交与远程仓库

远程仓库：

```text
git@github.com:legengen/software-quality-final-project.git
```

本项目已经按合适粒度提交：

- 文档类提交；
- AGENTLESS 适配代码提交；
- 基础复现实验结果提交；
- 自定义并发 benchmark 提交；
- 自定义并发 case 资源和评测结果提交；
- 并发流程说明提交。

后续如果继续修改，应继续按粒度拆分 commit，例如：

- 修改被测并发项目；
- 修改 evaluator；
- 新增 LLM 运行结果；
- 更新报告或文档。
