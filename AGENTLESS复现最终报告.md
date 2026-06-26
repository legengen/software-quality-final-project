# AGENTLESS 使用 DeepSeek V4 Pro High 修复代码复现实验报告

## 摘要

本实验围绕 AGENTLESS 论文提出的“无需 agent 交互的自动程序修复流程”进行复现，目标是在 SWE-bench Lite 子集上验证大语言模型定位缺陷、生成补丁并通过官方测试评测的可行性。实验在 WSL + Docker 环境中运行 AGENTLESS，并接入 DeepSeek V4 Pro High 作为代码定位与补丁生成模型。由于本地网络为非镜像 WSL，Docker 和 GitHub 访问统一通过主机规则代理出口。最终完成 5 个 Astropy 基础案例的 file-level、related-level、fine-grain localization、repair 与 SWE-bench Docker evaluation，5 个案例均完整执行，3 个案例通过官方测试，2 个案例生成补丁但未通过目标测试。

关键词：AGENTLESS；SWE-bench；自动程序修复；DeepSeek；软件质量

## 1. 实验目标与环境

本阶段目标不是重新实现 AGENTLESS 算法，而是在本地环境复现其官方流程，并验证 DeepSeek V4 Pro High 能否替代 OpenAI 模型完成基础案例修复。实验对象为本地 `resources/lite5/swebench_lite5.json` 中的 5 个 Astropy 案例。

实验环境如下：

| 项目 | 配置 |
| --- | --- |
| 系统 | WSL Linux，项目目录 `/home/legengen/software-quality-final-project` |
| 主项目 | `Agentless/` |
| 评测框架 | SWE-bench harness + Docker |
| LLM | DeepSeek V4 Pro High，`reasoning_effort=high`，thinking enabled |
| 代理 | WSL 默认网关 + 主机端口 `40558`，形如 `http://172.30.48.1:40558` |
| Docker 镜像 | `sweb.base.x86_64:latest`，Astropy env images 两个 |

为适配本地环境，复现过程中完成了以下工程补充：

1. 为 AGENTLESS 增加 DeepSeek backend 与 `deepseek-v4-pro` 模型选项。
2. 为 DeepSeek V4 Pro High 设置更高输出 token 上限，避免 reasoning 消耗输出预算后补丁为空。
3. 为 repair 增加 `--max_tokens` 参数，实际 repair 使用 `4096`。
4. 增加本地 JSON dataset 加载支持，避免必须从 Hugging Face 拉取数据集。
5. 为 SWE-bench Docker build 透传代理环境变量，并在需要时使用 host 网络。
6. 增强 AGENTLESS 后处理器，使其能解析 `edit_file(filename=..., start=..., end=..., content=...)` 这类 keyword 参数格式。

## 2. 复现流程

每个基础案例均按 AGENTLESS 官方主流程执行：

1. File-level localization：根据问题描述和仓库结构定位待修改文件。
2. Related-level localization：在目标文件中定位相关类、函数或方法。
3. Fine-grain localization：将修改位置缩小到具体行号或代码块。
4. Repair：基于定位上下文调用 DeepSeek V4 Pro High 生成 `edit_file` 补丁。
5. Post-process：将模型输出转成 SWE-bench 所需的 unified diff JSONL。
6. Evaluation：使用 SWE-bench Docker harness 运行 FAIL_TO_PASS 与 PASS_TO_PASS 测试。

评测命令均使用单实例 dataset，以避免无关实例干扰。Docker 评测过程中，`12907`、`14182`、`14365`、`14995` 复用了已有 Astropy 环境镜像；`6938` 因基础 commit 更旧，新构建了一个 env image。

## 3. 实验结果

| 实例 | 问题类型 | 定位主文件 | 结果 | 报告文件 |
| --- | --- | --- | --- | --- |
| `astropy__astropy-12907` | modeling separability | `astropy/modeling/separable.py` | resolved | `Agentless/agentless.deepseek-v4pro-4096-smoke.json` |
| `astropy__astropy-14182` | RST `header_rows` | `astropy/io/ascii/rst.py` | unresolved | `Agentless/agentless.deepseek-v4pro-14182.json` |
| `astropy__astropy-14365` | QDP command case | `astropy/io/ascii/qdp.py` | unresolved | `Agentless/agentless.deepseek-v4pro-14365.json` |
| `astropy__astropy-14995` | NDData mask propagation | `astropy/nddata/mixins/ndarithmetic.py` | resolved | `Agentless/agentless.deepseek-v4pro-14995.json` |
| `astropy__astropy-6938` | FITS D exponent writeback | `astropy/io/fits/fitsrec.py` | resolved | `Agentless/agentless.deepseek-v4pro-6938.json` |

总体结果：

| 指标 | 数值 |
| --- | --- |
| 总案例数 | 5 |
| 完成官方评测 | 5 |
| resolved | 3 |
| unresolved | 2 |
| error | 0 |
| empty patch | 0 |

## 4. 典型补丁与失败分析

`astropy__astropy-12907` 成功修复 `_cstack` 中右侧 separability matrix 的填充值问题：

```diff
-        cright[-right.shape[0]:, -right.shape[1]:] = 1
+        cright[-right.shape[0]:, -right.shape[1]:] = right
```

`astropy__astropy-14995` 成功修复一侧 mask 缺失时仍调用 `np.bitwise_or(mask, None)` 的问题：

```diff
+        elif operand.mask is None:
+            # self.mask is not None but operand has no mask, copy self.mask
+            return deepcopy(self.mask)
```

该补丁存在重复注释，但不影响官方测试结果，FAIL_TO_PASS 与 PASS_TO_PASS 均通过。

`astropy__astropy-6938` 成功修复 `chararray.replace` 未写回原数组的问题：

```diff
-            output_field.replace(encode_ascii('E'), encode_ascii('D'))
+            output_field[:] = output_field.replace(encode_ascii('E'), encode_ascii('D'))
```

两个 unresolved 案例如下：

- `astropy__astropy-14182`：模型让 `RST.__init__` 接收 `header_rows`，但在 `write()` 中访问不存在的 `self.header_rows`，同时未完整处理 RST 读写多行 header 的行偏移，导致目标测试和一个回归测试失败。
- `astropy__astropy-14365`：模型将 QDP 行类型正则改为大小写不敏感，使 `read serr` 可识别，但 lowercase 测试也会把数据中的 `NO` 变为 `no`，数据转换逻辑仍只检查 `v == "NO"`，因此目标测试失败。

## 5. 结论

本次复现证明，在本地 WSL + Docker 环境中，AGENTLESS 可与 DeepSeek V4 Pro High 组合完成 SWE-bench 基础案例的端到端自动修复流程。5 个基础案例全部完成官方流程，3 个案例通过 SWE-bench 官方测试，说明该流程具备可复现性和一定修复能力。

同时，两个 unresolved 案例表明，单样本 repair 容易生成“局部正确但语义不完整”的补丁。后续若要提高通过率，优先方向应是对失败案例增加多样本 repair、引入 reproduction/regression test selection 与 rerank，或在 repair 阶段加入更完整的上下文与失败反馈。

## 参考产物

- 实验记录：`AGENTLESS复现实验记录.md`
- 复跑说明：`AGENTLESS复跑说明.md`
- 结果索引：`AGENTLESS复现结果索引.json`
- AGENTLESS 项目目录：`Agentless/`
