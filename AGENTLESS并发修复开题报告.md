# 面向并发缺陷的 AGENTLESS 自动程序修复复现与轻量增强研究

摘要：随着大型语言模型在软件工程任务中的应用不断深入，自动程序修复逐渐从传统规则驱动方法转向基于真实问题描述和代码上下文的智能修复方法。AGENTLESS 提出了一种无需复杂 agent 交互的自动程序修复流程，通过文件级定位、相关元素定位、细粒度定位和补丁生成完成 SWE-bench 缺陷修复。本研究针对该方法在本地环境中的复现和课程作业中对并发代码修复的要求，拟基于 AGENTLESS 完成 SWE-bench Lite 基础案例复现，并构造一个线程竞态类自定义并发缺陷案例，引入并发语义提示、补丁风险检查和多轮稳定性评测三个轻量改进。预期形成一套可复现、可评测、可解释的 LLM 辅助并发缺陷修复流程，为理解自动程序修复方法在并发场景下的适用性提供实验依据。

关键词：AGENTLESS；自动程序修复；SWE-bench；并发缺陷；大语言模型；稳定性评测

## 1. 研究意义

### 1.1 研究背景

软件系统规模持续扩大，代码缺陷定位与修复成本不断上升。传统自动程序修复方法通常依赖规则模板、测试用例或静态分析信息，在真实开源项目中容易受到上下文不足和补丁表达能力有限的约束。近年来，大语言模型具备较强的代码理解和生成能力，能够基于自然语言 issue、代码片段和测试反馈生成修复补丁，为自动程序修复提供了新的技术路径。

SWE-bench 将真实 GitHub issue 与对应测试结合起来，提供了更接近真实工程场景的自动修复评测基准。AGENTLESS 在此基础上提出非交互式修复流程，将复杂 agent 决策拆解为定位、修复和评测步骤，具有流程清晰、复现实验容易控制的特点。

> 图片占位符：图1 AGENTLESS 自动程序修复基本流程图占位符。建议补充内容：Issue 描述 -> 文件级定位 -> 相关元素定位 -> 细粒度定位 -> LLM 生成补丁 -> 测试评测。

### 1.2 研究缺口

现有复现工作多关注普通确定性缺陷，而课程作业要求关注并发代码修复。并发缺陷具有非确定性特征，同一段代码是否失败可能受线程调度、运行环境和测试压力影响。若仍采用单次测试结果作为评判依据，可能无法充分说明补丁是否稳定修复问题。

此外，通用 LLM 修复提示往往没有明确强调共享状态、读-改-写序列、临界区和锁覆盖范围等并发语义，模型可能生成局部正确但并发语义不足的补丁。因此，有必要在 AGENTLESS 基础复现之上，引入面向并发缺陷的轻量增强。

### 1.3 研究价值

本研究具有工程与教学双重价值。工程上，通过复现 AGENTLESS 与 SWE-bench 评测流程，可以形成一套从 issue 到补丁再到测试结果的端到端实验链路。教学上，通过构造自定义并发缺陷并加入稳定性评测和风险分析，可以更直接地展示并发 bug 的修复特点和 LLM 自动修复方法的局限。

## 2. 相关现状调研

### 2.1 技术发展脉络

自动程序修复研究早期主要依赖搜索、遗传编程、模板匹配和静态分析等方法。这类方法通常需要预先设计修复模式，能够在特定类型缺陷上取得效果，但面对真实项目中的复杂语义缺陷时扩展性不足。随着预训练语言模型和大语言模型的发展，研究者开始将自然语言问题描述、代码上下文和测试反馈共同作为输入，让模型直接生成候选补丁。

### 2.2 关键技术现状

当前基于 LLM 的自动程序修复通常包含三个关键环节：第一是缺陷上下文构建，即从大型代码库中选择与 issue 相关的文件和代码片段；第二是补丁生成，即让模型根据上下文生成可应用的 diff 或编辑命令；第三是补丁验证，即通过测试或静态检查判断补丁是否正确。AGENTLESS 将这些环节拆解为定位、修复和评测流程，降低了 agent 交互复杂度。

### 2.3 并发缺陷修复现状

并发缺陷通常包括数据竞争、死锁、原子性违反、顺序违反和异步任务调度错误等类型。与普通功能缺陷相比，并发缺陷的触发条件更不稳定，测试用例需要通过多线程压力、重复执行或超时机制提高暴露概率。因此，对于并发代码修复，单次测试通过并不能完全说明补丁可靠。

### 2.4 最新研究进展

SWE-bench 等真实基准推动了自动程序修复从小型合成任务走向真实开源仓库。与此同时，越来越多研究开始关注补丁正确性、测试充分性和评测可解释性。对于课程项目而言，在完整复现官方流程的基础上增加面向并发缺陷的稳定性评测和补丁风险检查，是一种成本较低但针对性明确的改进方向。

## 3. 已有基础与工具搭建情况

### 3.1 基础项目复现情况

本项目已经完成 AGENTLESS 在本地 WSL + Docker 环境中的基础复现，并接入 DeepSeek V4 Pro High 作为 OpenAI-compatible LLM 后端。已完成 5 个 SWE-bench Lite Astropy 基础案例的定位、修复和 SWE-bench Docker 评测。

| 指标 | 结果 |
| --- | --- |
| 基础案例总数 | 5 |
| 完成官方评测 | 5 |
| resolved | 3 |
| unresolved | 2 |
| error | 0 |

基础复现结果表明，AGENTLESS 与 DeepSeek V4 Pro High 能够在本地环境中完成真实缺陷修复流程，但单样本补丁仍可能出现语义不完整问题。

> 图片占位符：图2 SWE-bench Docker 评测结果截图占位符。建议补充内容：5 个基础案例 resolved/unresolved 汇总截图。

### 3.2 自定义并发案例搭建情况

为满足并发代码修复要求，本项目新增了 `benchmarks/concurrent_counter/` 自定义并发缺陷项目。该项目中的 `ConcurrentCounter.increment()` 存在典型读-改-写竞态：多个线程可能读取相同旧值并覆盖彼此更新，导致最终计数小于预期。

同时，项目将该并发缺陷包装为 SWE-bench 风格 case，包含 `problem_statement`、`test_patch`、`FAIL_TO_PASS`、`PASS_TO_PASS` 和项目结构快照，使其能够接入 AGENTLESS 的定位和修复流程。

> 图片占位符：图3 自定义 ConcurrentCounter 并发缺陷代码截图占位符。建议补充内容：展示未加锁的 increment 方法。

### 3.3 本地评测器搭建情况

由于自定义本地项目不直接属于 SWE-bench 官方 Docker 支持范围，本研究实现了 `scripts/evaluate_custom_concurrency.py` 本地 evaluator。该工具会复制被测项目、应用测试补丁、应用模型补丁并运行 pytest，输出 resolved、stable_resolved、pass_rate 和 patch_risk 等指标。

## 4. 研究内容与改进方案

### 4.1 改进方案一：并发稳定性评测

原始评测流程通常只运行一次测试，输出 resolved 或 unresolved。针对并发缺陷受线程调度影响的问题，本研究在 evaluator 中引入 `--repeat N` 参数，对同一补丁重复运行测试，统计通过率和稳定通过情况。

| 指标 | 含义 | 评价方式 |
| --- | --- | --- |
| repeat | 重复测试次数 | 默认 10，可调整 |
| passed_runs | 通过轮数 | 越高越好 |
| failed_runs | 失败轮数 | 越低越好 |
| pass_rate | 通过率 | 越接近 1.0 越稳定 |
| stable_resolved | 是否全部通过 | true 表示多轮稳定通过 |

### 4.2 改进方案二：并发语义增强 Prompt

本研究在 AGENTLESS repair 阶段新增 `--concurrency_hint` 参数。启用后，prompt 会提醒 LLM 关注共享可变状态、读-改-写序列、临界区、锁覆盖范围和顺序行为保持。该改动只在自定义并发脚本中启用，不影响基础 SWE-bench 复现结果。

> 图片占位符：图4 并发语义增强 Prompt 截图占位符。建议补充内容：展示 repair 日志中 Concurrency Repair Guidance 片段。

### 4.3 改进方案三：补丁并发风险检查

仅依赖测试结果无法解释补丁是否符合并发修复模式。因此，本研究在 evaluator 中增加 `patch_risk` 静态检查，对模型补丁进行轻量规则分析。检查内容包括是否修改源文件、是否使用 Lock/RLock、是否保护 increment/reset 共享状态更新、是否只修改测试、是否新增可疑 sleep 等。

| 检查项 | 目标状态 | 说明 |
| --- | --- | --- |
| uses_lock | true | 应使用锁或等价同步机制 |
| guards_increment | true | 核心读-改-写应在临界区内 |
| guards_reset | true | 其他共享状态修改也应保护 |
| patches_tests_only | false | 不能只修改测试逃避问题 |
| risk_level | low | 风险越低说明补丁模式越合理 |

### 4.4 当前对比结果

| patch | repeat | passed_runs | failed_runs | pass_rate | stable_resolved | risk_level |
| --- | --- | --- | --- | --- | --- | --- |
| no-op | 10 | 0 | 10 | 0.0 | false | high |
| gold | 10 | 10 | 0 | 1.0 | true | low |

上述结果表明，no-op 补丁在 10 轮并发测试中全部失败，且风险等级为 high；gold patch 在 10 轮测试中全部通过，风险等级为 low。这说明新增指标能够有效区分未修复补丁和合理并发修复补丁。

> 图片占位符：图5 no-op 与 gold patch 评测结果截图占位符。建议补充内容：展示 JSON 报告中的 pass_rate、stable_resolved 和 risk_level。

## 5. 风险评估与应对措施

| 风险 | 影响 | 应对措施 |
| --- | --- | --- |
| LLM 生成补丁不稳定 | 可能无法一次修复并发 bug | 保留 gold patch 验证评测器；后续可增加多样本 repair |
| 并发测试存在偶然性 | 单次结果不可靠 | 使用 repeat 多轮测试和 pass_rate 指标 |
| 静态风险规则过于简单 | 可能误判复杂同步方式 | 将其定位为轻量解释指标，不替代测试结果 |
| Docker 或代理网络失败 | 影响 SWE-bench 官方评测 | 通过 WSL 主机代理和本地 evaluator 分离基础复现与自定义评测 |
| API 余额不足 | 无法重复调用 LLM | 默认脚本只验证 gold patch，RUN_LLM=1 时才调用模型 |

## 6. 进度安排与预期成效

### 6.1 进度安排

| 阶段 | 时间安排 | 主要任务 | 产出 |
| --- | --- | --- | --- |
| 第一阶段 | 第 1 周 | 阅读 AGENTLESS 论文和代码，搭建 WSL、Docker、Python 环境 | 复现计划与环境记录 |
| 第二阶段 | 第 2 周 | 接入 DeepSeek，完成 5 个 SWE-bench Lite 案例复现 | 基础评测报告 |
| 第三阶段 | 第 3 周 | 构造自定义并发缺陷 case 和本地 evaluator | 并发 case 数据与评测脚本 |
| 第四阶段 | 第 4 周 | 实现三项轻量增强并验证 no-op/gold 对比结果 | 创新点对比报告 |
| 第五阶段 | 第 5 周 | 整理最终文档、开题报告和课程提交材料 | 报告、代码仓库、结果文件 |

### 6.2 预期成效

| 成果类型 | 预期内容 | 量化指标 |
| --- | --- | --- |
| 基础复现 | 完成 AGENTLESS + DeepSeek 修复流程 | 5 个基础案例完成评测，3 resolved |
| 并发案例 | 构造线程竞态修复任务 | no-op 10 轮全失败，gold 10 轮全通过 |
| 稳定性评测 | 多轮 pytest 评价补丁可靠性 | 输出 pass_rate 和 stable_resolved |
| 风险检查 | 解释补丁并发修复模式 | 输出 risk_level 和 risk_reasons |
| 文档成果 | 形成复现、创新点、评价指标说明 | Markdown 与 Word 文档可提交 |

## 7. 结论

本研究拟在 AGENTLESS 基础复现的基础上，面向课程要求中的并发代码修复任务进行轻量增强。项目已经完成 SWE-bench Lite 5 个基础案例复现，并构造了自定义线程竞态缺陷案例。针对并发缺陷测试非确定性和补丁解释不足的问题，本研究提出并实现并发稳定性评测、并发语义增强 Prompt 和补丁风险检查三个改进点。预期最终形成一套从 issue 描述到 LLM 补丁生成、从多轮测试到风险解释的完整实验流程，能够支撑课程作业对自动程序修复与并发缺陷修复的要求。

## 参考文献

[1] Xia C S, Deng Y, Dunn S, Zhang L. Agentless: Demystifying LLM-based Software Engineering Agents. arXiv preprint, 2024.

[2] Jimenez C E, Yang J, Wettig A, et al. SWE-bench: Can Language Models Resolve Real-World GitHub Issues? ICLR, 2024.

[3] Le Goues C, Nguyen T, Forrest S, Weimer W. GenProg: A Generic Method for Automatic Software Repair. IEEE Transactions on Software Engineering, 2012.

[4] Monperrus M. Automatic Software Repair: A Bibliography. ACM Computing Surveys, 2018.

[5] OpenAI, DeepSeek 等大语言模型相关技术文档与 API 说明。
