# 题库格式

每道题使用一个 YAML 文件，复制 [`_template.yaml`](./_template.yaml) 后重命名。

## 支持的题型

| `type` | 用途 | `evaluation.plugin` |
| --- | --- | --- |
| `single_choice` | 单选题 | `choice` |
| `multiple_choice` | 多选题 | `choice` |
| `true_false` | 判断题 | `choice` |
| `fill_blank` | 填空题 | `text_match` |
| `short_answer` | 简答题 | `llm_judge` |
| `coding` | 编程题 | `unit_test` |
| `agent_task` | Agent 实战题 | `trajectory` |
| `composite` | 多阶段综合题 | `multi_stage` |

题型只负责描述交互内容，具体的展示、评分和复习逻辑由插件负责：

```text
type -> RendererPlugin -> EvaluatorPlugin -> SchedulerPlugin
```

`id` 必须保持稳定；修改题目内容时递增 `version`。答题记录会保存题目版本和题库 commit，保证历史结果可复现。

如果仓库公开，`answer` 也会被用户下载。个人学习版可以直接这样存放；需要防止提前查看答案时，应将答案和评分标准放到后端或私有题库仓库。
