# 统一知识分类

这里保存题库的知识模块定义、自动分类结果和待复核队列。

## 分类原则

题目的来源文档和知识模块分离：

- `source` / `sourceCollection` / `sourceCategory`：记录题目来自哪份飞书题库，只用于溯源和辅助筛选。
- `taxonomy.primary`：题目的唯一主知识模块，用于题库浏览、训练队列和掌握度统计。
- `taxonomy.secondary`：与题目相关的其他知识模块，允许跨模块检索。
- `taxonomy.concepts`：后续逐步补充的稳定知识点 ID。
- `taxonomy.status`：`auto` 表示高置信度自动分类，`review` 表示需要人工复核，`reviewed` 表示已确认。

物理上的 `data/packs/*.json` 是来源分片，不代表用户看到的知识分类。

## 一级知识域

| ID | 名称 |
| --- | --- |
| `engineering` | 编程与通用工程 |
| `ml` | 机器学习基础 |
| `dl` | 深度学习基础 |
| `llm` | Transformer 与大模型原理 |
| `training` | 模型训练与对齐 |
| `inference` | 推理优化与模型服务 |
| `prompt` | Prompt 与上下文工程 |
| `rag` | RAG 与知识增强 |
| `agent` | Agent 系统 |
| `evaluation` | 评测、安全与可靠性 |
| `multimodal` | 多模态与生成模型 |
| `system` | AI 应用与系统设计 |

完整的叶子模块、关键词和来源提示见 [`taxonomy.yml`](./taxonomy.yml)，当前版本为 `v2`，包含 12 个一级知识域和 60 个叶子模块。

## 重新生成

在仓库根目录执行：

```bash
ruby tools/classify_questions.rb
ruby tools/build_web_data.rb
```

分类脚本会生成：

- `assignments.jsonl`：每道题的主模块、关联模块、置信度和状态。
- `review-queue.jsonl`：需要人工复核的题目候选列表。
- `classification-report.json`：按知识模块、来源和状态统计的审计报告。
- `review-report.md`：按来源分类和候选模块聚合的人工复核视图。
- `overrides.jsonl`：人工确认后的稳定映射，分类脚本会在每次重建时重新应用。
- `review-rules.yml`：针对稳定子专题的批量复核规则；`title_pattern` 匹配题目标题，`content_pattern` 可匹配答案正文中的稳定主题；单题覆盖映射优先级更高。

人工确认的结果写入 `overrides.jsonl`，再重新运行分类脚本即可保留，不要直接编辑生成的 `assignments.jsonl`：

```json
{"questionId":"feishu-llm-complete-example","primary":"rag.retrieval","secondary":["rag.reranking"],"concepts":["hybrid-search"],"status":"reviewed","note":"人工确认主模块"}
```

当前基线：9407 道题全部获得知识模块分类，其中 1988 道为高置信度自动分类、7419 道已人工或规则确认、0 道待复核；没有未分类题目。规则确认结果会保留 `ruleId` 供审计，单题覆盖仍可通过 `overrides.jsonl` 修正，不需要移动原始题目文件，也不会影响以 `questionId` 保存的学习进度。

复核和构建完成后运行：

```bash
ruby tools/validate_taxonomy.rb
```

校验器会检查题目 ID、分类映射、复核队列、知识模块引用、数据包总数和 taxonomy 版本是否一致。
