# AGENTLESS 创新点对比与评价指标说明

本文档用于说明本项目在基础 AGENTLESS 复现流程之上做了哪些小规模改进，并从“原流程局限、具体改动、改动意义、评价指标、当前结果”几个角度进行对比。本文档可直接作为课程报告中“创新点与评价指标”部分的素材。

## 1. 原始流程概述

原始 AGENTLESS 流程可以概括为：

```text
Issue 描述
  -> 文件级定位
  -> 相关元素定位
  -> 细粒度位置定位
  -> LLM 生成补丁
  -> 后处理为 unified diff
  -> 运行测试
  -> resolved / unresolved
```

在 SWE-bench 官方案例中，最后一步通常由 Docker harness 完成。对于本项目新增的自定义并发案例，最后一步由本地 evaluator 完成：

```text
patch
  -> 应用 test_patch
  -> 应用 model_patch
  -> 运行 pytest
  -> 输出 resolved / unresolved
```

这个基础流程已经能完成“让 LLM 生成补丁并用测试判断是否修复”的目标，但对于并发缺陷仍有三个不足：

1. 并发测试受线程调度影响，单次 pytest 结果不够稳定。
2. 通用 repair prompt 没有显式提醒 LLM 关注并发语义。
3. 评测只给出测试结果，缺少对补丁是否符合基本并发修复模式的解释。

因此，本项目围绕并发代码修复加入了三个轻量创新点。

## 2. 创新点一：并发稳定性评测

### 2.1 原流程

原流程只运行一次测试：

```text
patch -> pytest once -> resolved / unresolved
```

这种方式对普通确定性 bug 通常够用，但对并发 bug 不够理想。因为并发缺陷是否暴露，可能取决于线程调度、机器负载和运行时机。单次通过并不一定说明补丁稳定，单次失败也不能展示失败概率。

### 2.2 改动内容

本项目在 `scripts/evaluate_custom_concurrency.py` 中新增 `--repeat N` 参数。评测时对同一个补丁重复运行 pytest，并记录每轮结果。

核心输出字段：

| 字段 | 含义 |
| --- | --- |
| `repeat` | 重复运行次数 |
| `passed_runs` | 通过轮数 |
| `failed_runs` | 失败轮数 |
| `pass_rate` | 通过率，`passed_runs / repeat` |
| `stable_resolved` | 是否每一轮都通过 |

一键脚本 `Agentless/scripts/run_custom_concurrency_case.sh` 中新增环境变量：

```bash
REPEAT="${REPEAT:-10}"
```

默认重复运行 10 次，也可以手动指定：

```bash
REPEAT=20 Agentless/scripts/run_custom_concurrency_case.sh
```

### 2.3 改动意义

该改动把原来的二值评测扩展为稳定性评测。它不是只回答“这次是否通过”，而是回答：

- 补丁是否能在多次并发调度下稳定通过；
- 原始 bug 是否能被稳定暴露；
- LLM 补丁是否只是偶然通过一次；
- 修复结果是否更适合作为并发缺陷修复证据。

对于课程作业来说，这个点和“并发代码修复”主题最贴合，因为它抓住了并发缺陷的非确定性特点。

### 2.4 评价指标

主要指标：

| 指标 | 评价方式 |
| --- | --- |
| `pass_rate` | 越高说明补丁越稳定 |
| `stable_resolved` | true 表示所有重复测试均通过 |
| `failed_runs` | 越低越好，非 0 说明补丁仍有不稳定风险 |

当前实验结果：

| patch | repeat | passed_runs | failed_runs | pass_rate | stable_resolved |
| --- | --- | --- | --- | --- | --- |
| no-op | 10 | 0 | 10 | 0.0 | false |
| gold | 10 | 10 | 0 | 1.0 | true |

结论：

- no-op 补丁 10 次全失败，说明并发测试能稳定暴露原 bug；
- gold 补丁 10 次全通过，说明正确加锁修复能稳定解决问题。

## 3. 创新点二：并发语义增强 Prompt

### 3.1 原流程

原 AGENTLESS repair prompt 是通用代码修复提示。它会给 LLM 问题描述和代码上下文，并要求生成 `edit_file` 命令或 diff，但不会针对并发问题强调：

- 共享可变状态；
- 读-改-写竞态；
- 临界区；
- 锁覆盖范围；
- 顺序行为不能被破坏。

这会导致模型可能只做局部修补，而没有从并发语义上考虑状态保护。

### 3.2 改动内容

本项目在 `Agentless/agentless/repair/repair.py` 中新增 `--concurrency_hint` 参数。启用后，repair 阶段会在 issue 描述后追加并发修复提示：

```text
This issue is about concurrent execution. When proposing the fix, explicitly consider shared mutable state,
read-modify-write sequences, critical sections, and whether all methods that mutate the shared state are
protected consistently. Prefer a minimal synchronization fix that preserves existing sequential behavior.
Do not solve the issue by weakening or deleting tests.
```

自定义并发脚本会自动启用该参数：

```bash
--concurrency_hint
```

基础 SWE-bench 复现不启用该参数，因此不会影响前面 5 个 Astropy 基础案例的原始复现结果。

### 3.3 改动意义

该改动属于 prompt 层的小改进。它的意义在于：

- 把通用程序修复提示变成面向并发缺陷的修复提示；
- 明确提醒模型关注共享状态和临界区；
- 降低模型只修改测试或只做表面修复的概率；
- 让报告中可以体现“针对并发缺陷做了领域适配”。

该创新点不需要大改 AGENTLESS 框架，但能够体现对并发 bug 特性的理解。

### 3.4 评价指标

由于该改动影响的是 LLM 生成阶段，可从以下角度评价：

| 指标 | 评价方式 |
| --- | --- |
| `patch_risk.uses_lock` | 是否使用锁或类似同步机制 |
| `patch_risk.guards_increment` | 是否保护核心读-改-写逻辑 |
| `patch_risk.guards_reset` | 是否保护其他共享状态修改方法 |
| `pass_rate` | 补丁是否在多轮并发测试中稳定通过 |
| `stable_resolved` | 是否所有重复测试均通过 |

如果后续运行真实 LLM，可比较两组结果：

```text
不加 --concurrency_hint 的 LLM patch
加 --concurrency_hint 的 LLM patch
```

对比维度包括是否生成锁、风险等级、通过率和最终稳定性。

## 4. 创新点三：补丁并发风险检查

### 4.1 原流程

原 evaluator 只判断测试是否通过：

```text
pytest pass -> resolved
pytest fail -> unresolved
```

这种方式的问题是解释性较弱。即使补丁通过测试，也不容易看出它是不是合理的并发修复；如果补丁失败，也不容易快速判断失败原因是没加锁、只改测试，还是锁覆盖不完整。

### 4.2 改动内容

本项目在 `scripts/evaluate_custom_concurrency.py` 中新增 `analyze_patch_risk()`，对 patch 做轻量静态分析，并在报告中输出 `patch_risk` 字段。

检查内容包括：

| 检查项 | 含义 |
| --- | --- |
| `changed_source_files` | 是否修改了源文件 |
| `changed_test_files` | 是否修改了测试文件 |
| `uses_lock` | 是否使用 `Lock` / `RLock` 或锁上下文 |
| `uses_context_manager` | 是否使用 `with self._lock` 风格保护临界区 |
| `guards_increment` | 是否保护 `increment()` 中的读-改-写 |
| `guards_reset` | 是否保护 `reset()` 中的共享状态写入 |
| `patches_tests_only` | 是否只修改测试 |
| `adds_sleep` | 是否新增可疑 sleep |
| `risk_level` | 综合风险等级：`low` / `medium` / `high` |
| `risk_reasons` | 风险原因列表 |

### 4.3 改动意义

该改动给评测结果增加了解释性。它不仅回答“补丁是否通过测试”，还回答：

- 补丁是否符合基本并发修复模式；
- 是否真的修改源代码；
- 是否使用同步机制；
- 是否保护了关键共享状态；
- 是否存在只改测试或增加 sleep 的投机行为。

这可以作为课程报告中的“补丁质量评价”部分。

### 4.4 评价指标

主要指标：

| 指标 | 目标 |
| --- | --- |
| `risk_level` | 越低越好 |
| `risk_reasons` | 越少越好 |
| `uses_lock` | 对本 case 应为 true |
| `guards_increment` | 对本 case 应为 true |
| `guards_reset` | 对本 case 应为 true |
| `patches_tests_only` | 应为 false |

当前实验结果：

| patch | uses_lock | guards_increment | guards_reset | patches_tests_only | risk_level |
| --- | --- | --- | --- | --- | --- |
| no-op | false | false | false | false | high |
| gold | true | true | true | false | low |

no-op 的风险原因：

```text
no source file changed
no lock or RLock usage detected
increment update is not clearly guarded
reset update is not clearly guarded
```

gold patch 无风险原因，说明其符合本并发 case 的预期修复模式。

## 5. 三个创新点的整体对比

| 维度 | 原流程 | 改进后 |
| --- | --- | --- |
| 测试执行 | 单次 pytest | 多轮 pytest，输出通过率 |
| resolved 判断 | 单次通过即 resolved | N 轮全通过才 stable resolved |
| repair prompt | 通用修复提示 | 可选并发语义增强提示 |
| 补丁解释 | 只有测试日志 | 增加 `patch_risk` 静态风险报告 |
| 并发适配 | 无专门设计 | 针对线程竞态、共享状态和锁覆盖进行适配 |
| 结果展示 | resolved / unresolved | resolved、pass_rate、stable_resolved、risk_level |

整体改进后的流程为：

```text
Issue 描述
  -> AGENTLESS 定位
  -> repair 阶段加入 concurrency hint
  -> LLM 生成补丁
  -> evaluator 应用 test_patch 和 model_patch
  -> 多轮 pytest 稳定性评测
  -> patch_risk 静态风险检查
  -> 输出稳定性指标和风险等级
```

## 6. 可写入报告的总结表述

可以在课程报告中这样描述本项目创新点：

> 在基础 AGENTLESS 自动程序修复流程之上，本文针对并发缺陷的非确定性和语义特殊性进行了轻量增强。首先，引入重复执行机制，将单次测试判断扩展为多轮稳定性评测，使用 pass_rate 和 stable_resolved 衡量补丁可靠性。其次，在 repair 阶段加入并发语义提示，引导 LLM 关注共享状态、读-改-写序列、临界区和锁覆盖范围。最后，增加补丁并发风险检查，从是否修改源文件、是否使用锁、是否保护关键状态更新等角度解释补丁质量。实验结果表明，no-op 补丁在 10 轮测试中通过率为 0.0 且风险等级为 high，而 gold patch 通过率为 1.0、stable_resolved 为 true、风险等级为 low，说明上述评价机制能够有效区分未修复补丁和合理并发修复补丁。

## 7. 当前文件对应关系

| 内容 | 文件 |
| --- | --- |
| 稳定性评测与风险检查 | `scripts/evaluate_custom_concurrency.py` |
| 并发语义 prompt | `Agentless/agentless/repair/repair.py` |
| 一键运行入口 | `Agentless/scripts/run_custom_concurrency_case.sh` |
| no-op 评测结果 | `Agentless/results/custom_concurrency/noop_evaluation_report.json` |
| gold 评测结果 | `Agentless/results/custom_concurrency/gold_evaluation_report.json` |
| 自定义并发 case | `Agentless/resources/custom_concurrency/concurrency_cases.json` |
| 被测并发项目 | `benchmarks/concurrent_counter/` |
