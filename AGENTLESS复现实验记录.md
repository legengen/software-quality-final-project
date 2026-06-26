# AGENTLESS 复现实验记录

## 固定配置

- 官方仓库：`OpenAutoCoder/Agentless`
- 本地路径：`/home/legengen/software-quality-final-project/Agentless`
- 固定版本：`v1.5.0`
- Commit：`b150f28`
- 数据集：`princeton-nlp/SWE-bench_Lite`
- 模型：`gpt-4o-mini-2024-07-18`
- 固定样例：
  - `astropy__astropy-12907`
  - `astropy__astropy-14182`
  - `astropy__astropy-14365`
  - `astropy__astropy-14995`
  - `astropy__astropy-6938`

## 环境检查

- WSL2 Ubuntu：已确认。
- Git：已安装。
- Docker CLI：已安装。
- Docker 权限：当前 Codex 会话需要通过 `sg docker -c '...'` 执行 Docker 命令。
- Docker registry：Docker daemon 访问 Docker Hub / 常见镜像源超时，当前无法拉取 `ubuntu:22.04`，SWE-bench Docker 评测暂时阻塞。
- Conda：初始未安装；Miniforge 已安装到 `~/miniforge3`，但 `mamba create -n agentless python=3.11` 长时间无输出，已改用 Python `venv`。
- Python 环境：`Agentless/.venv-agentless`，Python 3.12.3。
- 关键依赖：`swebench==2.1.8`、`modal==0.64.221`、`openai==2.44.0`、`datasets==5.0.0`。
- 磁盘空间：`/` 可用约 922GB，满足小规模 SWE-bench 实验需要。
- LLM API：当前环境未设置 `OPENAI_API_KEY`，真实 LLM localization/repair 无法启动。

## 进度日志

- 2026-06-26 01:20：克隆 Agentless 官方仓库。
- 2026-06-26 01:21：切换到 `v1.5.0`，commit `b150f28`。
- 2026-06-26 01:35：Conda 环境创建卡住，改用 Python 3.12 `venv` 安装官方依赖。
- 2026-06-26 01:40：安装 Agentless requirements；将 SWE-bench 固定为 `2.1.8`，Modal 固定为 `0.64.221` 以匹配旧 harness API。
- 2026-06-26 01:48：原计划 `sqlfluff__...` 样例不在当前 SWE-bench Lite test split 中，改为当前数据集前 5 个有效样例。
- 2026-06-26 01:55：导出本地 5 样例数据集：
  - `Agentless/resources/lite5/swebench_lite5.json`
  - `Agentless/resources/lite5/swebench_lite5_smoke.json`
- 2026-06-26 01:56：SWE-bench gold 冒烟进入 Docker 构建阶段，但 Docker daemon 拉取 `ubuntu:22.04` 超时。
- 2026-06-26 02:08：为 Agentless 增加本地 JSON 数据集兼容层，避免反复访问 Hugging Face。
- 2026-06-26 02:09：`--mock` file-level localization 成功生成 prompt/token 输出：
  - `Agentless/results/swe-bench-lite-5-gpt4omini/mock_file_level/loc_outputs.jsonl`

## 已生成产物

- 自动化环境脚本：`Agentless/scripts/agentless_lite5_env.sh`
- SWE-bench 冒烟脚本：`Agentless/scripts/smoke_swebench_lite5.sh`
- Agentless 官方子集流程脚本：`Agentless/scripts/run_agentless_lite5.sh`
- 本地数据集快照：`Agentless/resources/lite5/swebench_lite5.json`
- 依赖锁定：`Agentless/requirements-repro-lock.txt`
- 本地数据集兼容工具：`Agentless/agentless/util/dataset.py`

## 当前阻塞

1. 缺少 `OPENAI_API_KEY`。
   - 影响：无法运行真实 `localize.py`、`repair.py`、`generate_reproduction_tests.py`、`select_regression_tests.py` 中的 LLM 调用。
   - 恢复命令示例：
     ```bash
     cd /home/legengen/software-quality-final-project/Agentless
     export OPENAI_API_KEY='你的 key'
     scripts/run_agentless_lite5.sh
     ```

2. Docker daemon 无法从 registry 拉取基础镜像。
   - 影响：无法运行 SWE-bench harness、regression tests、reproduction tests 和最终 evaluation。
   - 当前错误：`Head "https://registry-1.docker.io/v2/library/ubuntu/manifests/22.04": i/o timeout`
   - 需要先解决 Docker 镜像拉取，例如配置可用代理/镜像源，或手动导入 `ubuntu:22.04` 并保证 `docker pull ubuntu:22.04` 成功。

## 可继续执行的命令

```bash
cd /home/legengen/software-quality-final-project/Agentless

# 检查 Python/Agentless 本地流程
source .venv-agentless/bin/activate
PYTHONPATH=$PWD python agentless/fl/localize.py \
  --file_level --mock \
  --target_id astropy__astropy-12907 \
  --output_folder results/swe-bench-lite-5-gpt4omini/mock_file_level \
  --num_threads 1 --skip_existing \
  --model gpt-4o-mini-2024-07-18 \
  --backend openai \
  --dataset resources/lite5/swebench_lite5.json

# Docker 修复后运行 SWE-bench 冒烟
scripts/smoke_swebench_lite5.sh

# API key 和 Docker 都可用后运行完整官方子集流程
export OPENAI_API_KEY='你的 key'
scripts/run_agentless_lite5.sh
```

## 2026-06-26 DeepSeek 低成本烟测补充

- Docker 镜像状态：`ubuntu:22.04` 已成功拉取到本地；Docker CLI 可通过 `sg docker -c 'docker ...'` 运行。
- SWE-bench gold 冒烟更新：harness 已能启动，但 base image 构建卡在容器内 `apt update/apt install`。WSL 宿主机可访问 GitHub 和部分 apt metadata，但 Docker build / 容器内访问 `archive.ubuntu.com`、`mirrors.aliyun.com` 等源时会解析到 `198.18.x.x` 并间歇超时，因此最终评测链路仍未完成。
- GitHub 访问状态：WSL 宿主 `ping github.com`、`git ls-remote https://github.com/astropy/astropy.git HEAD` 可成功；但 `git clone` 大仓库在多次 AGENTLESS 阶段中出现间歇性 443 超时。
- DeepSeek API 烟测：使用 `deepseek-coder` + `--backend deepseek` 成功跑通单实例 LLM 定位链路，不将 API key 写入文件。
  - file-level 输出：`Agentless/results/deepseek-smoke/file_level/loc_outputs.jsonl`
  - 定位文件：`astropy/modeling/separable.py`、`astropy/modeling/core.py`
  - related-level 输出：`Agentless/results/deepseek-smoke/related_elements/loc_outputs.jsonl`
  - fine-grain 输出：`Agentless/results/deepseek-smoke/edit_locations/loc_outputs.jsonl`
  - 行级定位：`astropy/modeling/separable.py`，`function: _cstack`，并给出相关行号。
- 为避免 AGENTLESS 阶段反复 clone GitHub，生成了单实例最小仓库结构缓存：
  - `Agentless/resources/project_structures/astropy__astropy-12907.json`
  - raw 文件来源：目标 commit 的 `astropy/modeling/separable.py` 与 `astropy/modeling/core.py`
  - 使用方式：运行 repair 时加 `PROJECT_FILE_LOC=resources/project_structures`
- repair 阶段已使用 DeepSeek 生成 1 个候选 patch：
  - 输出：`Agentless/results/deepseek-smoke/repair_cached/output_0_processed.jsonl`
  - 结果：patch 非空，但候选修复把 `cright = np.zeros(...)` 删除后直接写 `cright[...] = right`，存在运行时 `cright` 未定义风险，不能视为有效修复。
- 当前结论：DeepSeek 可用于 AGENTLESS 的单实例定位与补丁生成烟测；但要完成正式复现，还需解决 Docker 容器网络/apt 源问题，并需要更多采样或更强模型来提高 patch 正确率。

## 后续未完成流程

1. 完成 SWE-bench Docker gold 冒烟：构建 `sweb.base.x86_64:latest`、env image、instance image，并确认 gold patch 可评测。
2. 跑官方完整定位组合：file-level、irrelevant-folder、embedding retrieval、combine、related-level、fine-grain、merge。
3. 跑 repair 多样本生成，产出 `all_preds.jsonl`。
4. 跑 reproduction/regression test selection、测试执行和 rerank。
5. 使用 SWE-bench harness 对最终 patch 做正式评价。


## 2026-06-26 Docker 网络修复与验证补充

- 诊断结论：WSL 宿主和普通 `docker run ubuntu:22.04 apt update` 当前均可访问 Ubuntu apt 源；但 SWE-bench 使用 Docker build 构建 base image 时，`apt install` 阶段仍会大量出现 `archive.ubuntu.com:80` 超时，导致 `sweb.base.x86_64:latest` 构建失败。
- 采用的可行修复：绕过 Docker build 阶段的 base image 安装，使用 `docker run ubuntu:22.04` 手工执行 SWE-bench base Dockerfile 的等价命令，安装系统包、Miniconda、conda-forge channel 和 `nonroot` 用户，然后 `docker commit` 为 `sweb.base.x86_64:latest`。
- 已生成镜像：
  - `sweb.base.x86_64:latest`，约 1.43GB
  - `sweb.env.x86_64.428468730904ff6b4232aa:latest`，约 2.77GB
- 验证结果：`Agentless/scripts/smoke_swebench_lite5.sh` 已通过。
  - 报告文件：`Agentless/gold.agentless-lite5-gold-smoke.json`
  - total_instances: 1
  - completed_instances: 1
  - resolved_instances: 1
  - error_instances: 0
  - 测试实例：`astropy__astropy-12907`
- 说明：Docker/SWE-bench 评测链路目前已可用于后续 patch 验证；如果删除 `sweb.base.x86_64:latest`，需要重新执行手工 base 镜像生成或再次修 Docker build 网络。

## 2026-06-26 DeepSeek V4 Pro High 支持

- 已在本地 AGENTLESS 代码中加入 `deepseek-v4-pro` CLI 选项。
- 当 `--backend deepseek --model deepseek-v4-pro` 时，请求层会附加：
  - `reasoning_effort = high`
  - `extra_body = {"thinking": {"type": "enabled"}}`
- 已确认 `localize.py --help` 和 `repair.py --help` 均显示 `deepseek-v4-pro`。


## 2026-06-26 DeepSeek V4 Pro High 单实例闭环结果

- 用户补充网络规则：主机代理为 `127.0.0.1:40558`，WSL 非镜像网络场景下，应先用 `ip route` 获取默认网关作为 Windows 主机 IP，再通过 `http://<host-ip>:40558` 出口。
- 已验证代理出口：容器中设置 `HTTP_PROXY/HTTPS_PROXY/ALL_PROXY=http://172.30.48.1:40558` 后，可成功执行 `git ls-remote https://github.com/astropy/astropy HEAD`。
- 已修改 SWE-bench 本地 harness：Docker build 会从环境变量继承 `HTTP_PROXY`、`HTTPS_PROXY`、`ALL_PROXY`、`NO_PROXY` 并作为 build args 传入，解决 instance image 构建时 GitHub clone 断连问题。
- DeepSeek V4 Pro High 第一次 repair：`max_tokens=1024` 时 reasoning 用满输出长度，`finish_reason=length`，最终 `content` 为空，未生成 patch。
- 已为 `agentless/repair/repair.py` 增加 `--max_tokens` 参数；第二次使用 `--max_tokens 4096` 成功生成 patch。
- 生成结果：
  - 输出目录：`Agentless/results/deepseek-v4pro-smoke/repair_cached_4096/`
  - patch 文件：`Agentless/results/deepseek-v4pro-smoke/repair_cached_4096/output_0_processed.jsonl`
  - 模型：`deepseek-v4-pro`，backend：`deepseek`，reasoning effort：high
- 生成的核心补丁：
  ```diff
  -        cright[-right.shape[0]:, -right.shape[1]:] = 1
  +        cright[-right.shape[0]:, -right.shape[1]:] = right
  ```
- SWE-bench Docker 官方评测已通过：
  - 命令运行时使用主机代理 `http://172.30.48.1:40558`
  - 报告文件：`Agentless/agentless.deepseek-v4pro-4096-smoke.json`
  - total_instances: 1
  - completed_instances: 1
  - resolved_instances: 1
  - error_instances: 0
  - FAIL_TO_PASS：2/2 通过
  - PASS_TO_PASS：全部通过
- 当前结论：`AGENTLESS + DeepSeek V4 Pro High + SWE-bench Docker` 已完成单实例端到端闭环，模型生成的补丁通过官方测试。

## 2026-06-26 基础案例 astropy__astropy-14182 复现结果

- 目标问题：`ascii.rst` 写出时支持 `header_rows`。
- 已按 AGENTLESS 官方主流程完成：
  - file-level：定位到 `astropy/io/ascii/rst.py`
  - related-level：定位到 `RST`、`SimpleRSTHeader`、`SimpleRSTData`
  - fine-grain：定位到 `RST.__init__` 第 60-61 行
  - repair：DeepSeek V4 Pro High 生成 1 个候选补丁
  - evaluation：SWE-bench Docker 官方 harness 完成评测
- 产物：
  - 定位结果：`Agentless/results/deepseek-v4pro-lite5/14182/edit_locations/loc_outputs.jsonl`
  - 清洗后定位：`Agentless/results/deepseek-v4pro-lite5/14182/edit_locations/loc_outputs.cleaned.jsonl`
  - 原始 repair 输出：`Agentless/results/deepseek-v4pro-lite5/14182/repair_cleaned_4096/output.jsonl`
  - 手工后处理 patch：`Agentless/results/deepseek-v4pro-lite5/14182/repair_cleaned_4096/output_0_processed.manual.jsonl`
  - 评测报告：`Agentless/agentless.deepseek-v4pro-14182.json`
- 结果：
  - completed_instances: 1
  - resolved_instances: 0
  - error_instances: 0
  - patch 非空且成功应用，但最终 unresolved
- 失败原因：
  - 生成补丁使 `RST.__init__` 接收 `header_rows`，但 `write()` 中使用了不存在的 `self.header_rows` 属性，导致 `test_write_normal` 回归失败。
  - 读入带多行 header 的 RST 表时仍未正确调整 header/data 行，`test_rst_with_header_rows` 失败。
- 额外修复：
  - 本地 AGENTLESS 后处理器已增强，可解析 `edit_file(filename=..., start=..., end=..., content=...)` 这种 keyword 参数格式。
  - 该修复只影响本地 patch 后处理，不改变模型生成内容。

## 2026-06-26 基础案例 astropy__astropy-14365 复现结果

- 目标问题：`ascii.qdp` 读取 QDP 命令时应大小写不敏感。
- 已按 AGENTLESS 官方主流程完成：
  - file-level：定位到 `astropy/io/ascii/qdp.py`
  - related-level：定位到 `_line_type`、`_get_tables_from_qdp_file`、`_interpret_err_lines`、`QDP.read`
  - fine-grain：定位到 `_line_type` 第 71 行
  - repair：DeepSeek V4 Pro High 生成 1 个候选补丁
  - evaluation：SWE-bench Docker 官方 harness 完成评测
- 生成补丁：
  ```diff
  -    _line_type_re = re.compile(_type_re)
  +    _line_type_re = re.compile(_type_re, re.IGNORECASE)
  ```
- 产物：
  - 定位结果：`Agentless/results/deepseek-v4pro-lite5/14365/edit_locations/loc_outputs.jsonl`
  - repair 输出：`Agentless/results/deepseek-v4pro-lite5/14365/repair_4096/output_0_processed.jsonl`
  - 评测报告：`Agentless/agentless.deepseek-v4pro-14365.json`
- 结果：
  - completed_instances: 1
  - resolved_instances: 0
  - error_instances: 0
  - patch 非空且成功应用，但最终 unresolved
- 失败原因：
  - 候选补丁让 `_line_type` 的整体正则大小写不敏感，`read serr` 能被识别为 command。
  - 但测试会把 QDP 头和数据中的 `NO` 都转成小写，数据转换逻辑仍只检查 `v == "NO"`，导致 `no` 被尝试转换成数字并失败。
  - 目标测试 `astropy/io/ascii/tests/test_qdp.py::test_roundtrip[True]` 未通过；全部 PASS_TO_PASS 通过。

## 2026-06-26 基础案例 astropy__astropy-14995 复现结果

- 目标问题：`NDDataRef` 算术中一侧没有 mask 时，`handle_mask=np.bitwise_or` 不应把现有 mask 与 `None` 做位或。
- 已按 AGENTLESS 官方主流程完成：
  - file-level：定位到 `astropy/nddata/mixins/ndarithmetic.py`、`astropy/nddata/nddata.py`
  - related-level：定位到 `NDArithmeticMixin._arithmetic_mask`
  - fine-grain：定位到 `_arithmetic_mask` 第 523、525 行
  - repair：DeepSeek V4 Pro High 生成 1 个候选补丁
  - evaluation：SWE-bench Docker 官方 harness 完成评测
- 生成补丁核心逻辑：
  ```diff
  +        elif operand.mask is None:
  +            # self.mask is not None but operand has no mask, copy self.mask
  +            return deepcopy(self.mask)
  ```
- 产物：
  - 定位结果：`Agentless/results/deepseek-v4pro-lite5/14995/edit_locations/loc_outputs.jsonl`
  - repair 输出：`Agentless/results/deepseek-v4pro-lite5/14995/repair_4096/output_0_processed.jsonl`
  - 评测报告：`Agentless/agentless.deepseek-v4pro-14995.json`
- 结果：
  - completed_instances: 1
  - resolved_instances: 1
  - error_instances: 0
  - FAIL_TO_PASS：`test_nddata_bitmask_arithmetic` 通过
  - PASS_TO_PASS：全部通过
- 备注：
  - 候选补丁中重复了一行注释，但不影响语义和官方测试结果。

## 2026-06-26 基础案例 astropy__astropy-6938 复现结果

- 目标问题：FITS ASCII table 中 `D` 指数格式写回时，`chararray.replace` 返回副本但原代码未写回。
- 已按 AGENTLESS 官方主流程完成：
  - file-level：定位到 `astropy/io/fits/fitsrec.py`
  - related-level：定位到 `FITS_rec._scale_back_ascii`
  - fine-grain：定位到 `_scale_back_ascii` 第 1264 行
  - repair：DeepSeek V4 Pro High 生成 1 个候选补丁
  - evaluation：SWE-bench Docker 官方 harness 完成评测
- 生成补丁：
  ```diff
  -            output_field.replace(encode_ascii('E'), encode_ascii('D'))
  +            output_field[:] = output_field.replace(encode_ascii('E'), encode_ascii('D'))
  ```
- 产物：
  - 定位结果：`Agentless/results/deepseek-v4pro-lite5/6938/edit_locations/loc_outputs.jsonl`
  - repair 输出：`Agentless/results/deepseek-v4pro-lite5/6938/repair_4096/output_0_processed.jsonl`
  - 评测报告：`Agentless/agentless.deepseek-v4pro-6938.json`
- 结果：
  - completed_instances: 1
  - resolved_instances: 1
  - error_instances: 0
  - FAIL_TO_PASS：`test_ascii_table_data`、`test_ascii_table` 通过
  - PASS_TO_PASS：全部通过
- Docker 说明：
  - 为该旧 Astropy commit 新构建了 env image：`sweb.env.x86_64.c70974ae7654c7a2c98577:latest`，约 2.73GB。

## 2026-06-26 Lite5 基础案例阶段汇总

| 实例 | 官方流程状态 | SWE-bench 结果 | 说明 |
| --- | --- | --- | --- |
| `astropy__astropy-12907` | 完成 | resolved | 早前单实例闭环已通过 |
| `astropy__astropy-14182` | 完成 | unresolved | RST `header_rows` 候选补丁不完整 |
| `astropy__astropy-14365` | 完成 | unresolved | QDP 候选补丁只处理命令大小写，未处理小写 `no` 缺失值 |
| `astropy__astropy-14995` | 完成 | resolved | NDData mask 缺失分支修复通过 |
| `astropy__astropy-6938` | 完成 | resolved | FITS `D` 指数写回修复通过 |

- 总计：5 个基础案例均完成 file-level、related-level、fine-grain、repair 和 SWE-bench Docker evaluation。
- resolved：3/5。
- unresolved：2/5。
- Docker/SWE-bench 链路状态：可用；当前本地保留 `sweb.base.x86_64:latest` 以及两个 Astropy env image。
