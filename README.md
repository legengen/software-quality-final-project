# AGENTLESS 自动程序修复复现与并发缺陷扩展

本仓库是软件质量课程项目，用于复现 AGENTLESS 使用大语言模型修复代码缺陷的流程，并在此基础上扩展一个自定义并发缺陷修复案例。

项目分为两部分：

1. 基础复现：使用 AGENTLESS + DeepSeek V4 Pro High 在 SWE-bench Lite 的 5 个 Astropy 案例上完成定位、补丁生成和评测。
2. 并发扩展：构造 `ConcurrentCounter` 线程竞态缺陷，将其包装成 SWE-bench 风格 case，并用 AGENTLESS 的定位与 repair 流程生成修复补丁。

## 当前结果

基础 SWE-bench Lite 子集复现结果：

| case | 状态 | 说明 |
| --- | --- | --- |
| `astropy__astropy-12907` | resolved | DeepSeek repair 通过 |
| `astropy__astropy-14182` | resolved | 测试反馈迭代修复 |
| `astropy__astropy-14365` | resolved | 测试反馈迭代修复 |
| `astropy__astropy-14995` | resolved | DeepSeek repair 通过 |
| `astropy__astropy-6938` | resolved | DeepSeek repair 通过 |

汇总：5 个基础案例全部完成官方 SWE-bench Docker 评测，结果为 `5 resolved / 0 unresolved`。

自定义并发案例：

- 缺陷位置：`benchmarks/concurrent_counter/concurrent_counter/counter.py`
- 缺陷类型：多线程读-改-写竞态，`increment()` 未使用锁保护共享状态
- 评测方式：本地 evaluator 复制项目、应用模型补丁，并重复运行 pytest
- 关键指标：`resolved`、`stable_resolved`、`pass_rate`、`patch_risk`

## 仓库结构

```text
.
├── Agentless/                         # AGENTLESS 源码、运行脚本、模型输出和评测结果
│   ├── agentless/                     # AGENTLESS 核心代码
│   ├── resources/custom_concurrency/  # 自定义并发 case 数据和项目结构快照
│   ├── results/                       # 模型输出与评测结果
│   └── scripts/                       # 官方/项目运行脚本
├── benchmarks/concurrent_counter/     # 自定义并发缺陷项目
├── scripts/                           # 项目自定义工具脚本
│   ├── generate_custom_concurrency_case.py
│   ├── evaluate_custom_concurrency.py
│   ├── normalize_custom_concurrency_locs.py
│   ├── run_concurrency_repair_demo.sh
│   └── demo_recording.sh
└── docs/                              # 两份说明文档：基础复现、并发修复与创新点
```

## 基础复现流程

基础复现使用 AGENTLESS 的典型流程：

```text
issue / problem_statement
  -> file-level localization
  -> related-level localization
  -> fine-grain localization
  -> repair
  -> SWE-bench Docker evaluation
```

本项目接入 DeepSeek V4 Pro High 作为 OpenAI-compatible LLM 后端。基础案例复现说明位于：

```text
docs/1-基础案例复现说明.md
```

## 并发修复流程

自定义并发案例位于：

```text
benchmarks/concurrent_counter/
```

核心缺陷是 `ConcurrentCounter.increment()` 中的共享变量更新没有同步：

```python
old_value = self._value
time.sleep(0.00001)
self._value = old_value + amount
```

多个线程可能读取相同旧值并覆盖彼此的更新，导致最终计数小于期望值。

并发流程在 AGENTLESS 基础上增加了三个轻量改动：

- `--concurrency_hint`：repair prompt 增加并发语义提示，强调共享状态、临界区和锁覆盖范围。
- `--repeat N`：evaluator 多轮运行 pytest，用 `pass_rate` 和 `stable_resolved` 判断补丁稳定性。
- `patch_risk`：对补丁做轻量静态检查，识别是否使用锁、是否只改测试、是否新增 sleep 等风险。

## 运行并发修复演示

录屏或演示时推荐运行：

```bash
cd /home/legengen/software-quality-final-project
export OPENAI_API_KEY=你的DeepSeek_API_Key
REPEAT=10 scripts/run_concurrency_repair_demo.sh
```

脚本会执行：

```text
生成自定义并发 case
  -> file-level localization
  -> related-level localization
  -> fine-grain localization
  -> 定位结果规范化
  -> DeepSeek repair
  -> evaluator 多轮 pytest 评测
```

默认输出目录会自动带时间戳，例如：

```text
Agentless/results/custom_concurrency/counter_live_demo_20260627-142500/
```

关键输出文件：

```text
file_level/loc_outputs.jsonl
related_elements/loc_outputs.jsonl
edit_locations/loc_outputs.jsonl
edit_locations/loc_outputs.normalized.jsonl
repair/output_0_processed.jsonl
evaluation_report.json
```

如果只想快速试跑，可以减少重复测试次数：

```bash
REPEAT=2 scripts/run_concurrency_repair_demo.sh
```

## 常用命令

生成自定义并发 case：

```bash
python3 scripts/generate_custom_concurrency_case.py
```

评测 gold patch：

```bash
python3 scripts/evaluate_custom_concurrency.py \
  --dataset Agentless/resources/custom_concurrency/concurrency_cases.json \
  --predictions Agentless/resources/custom_concurrency/gold_patch.jsonl \
  --benchmark-root benchmarks/concurrent_counter \
  --output Agentless/results/custom_concurrency/gold_evaluation_report.json \
  --repeat 10
```

查看基础复现说明：

```bash
cat docs/1-基础案例复现说明.md
```

## 注意事项

- `Agentless/results/custom_concurrency/counter_live_demo_*` 是录屏或现场运行产生的结果目录，通常不需要提交。
- `Agentless/.venv-agentless/`、`Agentless/logs/`、`__pycache__/`、`.pytest_cache/` 等属于本地环境或缓存，不应提交。
- `deepseek-v4-pro` 不是 tiktoken 内置模型名，首次运行时可能需要联网下载 `cl100k_base` tokenizer 缓存。
- 重复运行 AGENTLESS localization 时不要复用同一个输出目录，否则会因为已有 `loc_outputs.jsonl` 被拒绝覆盖。

## 参考

- AGENTLESS 官方仓库：https://github.com/OpenAutoCoder/Agentless
- SWE-bench：https://www.swebench.com/
