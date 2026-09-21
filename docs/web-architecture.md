# Web 刷题系统架构

当前网页已经从“示例仪表盘”升级为一个可实际使用的静态刷题工作台。它仍然可以直接部署到 GitHub Pages，但题库、刷题流程、复习调度和学习报告已经分层，后续可以平滑接入 API、Agent 或自定义 LLM。

## 产品工作区

| 工作区 | 作用 | 关键动作 |
| --- | --- | --- |
| 今日训练 | 给出当天的学习入口和复习优先级 | 开始今日训练、薄弱项强化、查看到期复习 |
| 开始刷题 | 完整的主动回忆闭环 | 先回答、看提示、展开参考答案、自评记忆程度、进入下一题 |
| 题库浏览 | 管理和探索 GitHub 题库内容 | 搜索、按模块筛选、按状态筛选、单题训练 |
| 学习报告 | 观察长期学习效果 | 答题活动、记忆保留率、模块掌握度、最近记录 |

## 运行时分层

```text
GitHub Questions (YAML)              questions/taxonomy
        |                                      |
        | tools/classify_questions.rb            | assignments.jsonl / review-rules.yml / overrides.jsonl
        +----------------------+---------------+
                               |
                               | tools/build_web_data.rb
        v
Static Content Layer
  data/catalog.json       知识域、知识模块、来源、统计和分片索引
  data/packs/*.json       按来源分片懒加载题目正文和参考答案
        |
        v
Browser Application
  assets/app.js            路由、题库查询、训练会话、报告计算
  assets/styles.css        视觉系统、响应式布局、交互状态
        |
        v
Local Runtime State
  localStorage             agent-trials.progress.v2
    ├── attempts            原始答题事件
    ├── schedules            每道题的复习状态
    ├── drafts               未提交的回答草稿
    └── dailyGoal            每日训练目标
```

题目分类和来源是两个独立维度：`taxonomy.primary` 用于刷题、统计和学习路径，`source` 用于溯源和来源筛选。首屏只加载 `catalog.json`，进入训练后才按当前题目的 `packId` 加载正文，因此题库规模增长不会把所有参考答案一次性塞进首屏。

当前统一索引包含 3 个来源集合、12 个一级知识域和 60 个叶子知识模块。分类结果写入 `questions/taxonomy/assignments.jsonl`；高置信度题目标记为 `auto`，稳定专题通过 `review-rules.yml` 批量确认，单题人工决定通过 `overrides.jsonl` 持久化，其余题目进入 `review-queue.jsonl`，不会覆盖原始 YAML。

## 一次刷题的状态流

```text
选择训练入口
  -> 生成队列：到期复习 > 薄弱题 > 新题
  -> 加载当前题目 pack
  -> 用户主动回答 / 查看提示
  -> 查看参考答案
  -> 自评：不会 | 模糊 | 记得
  -> 写入 attempts
  -> 更新 schedules.nextReviewAt
  -> 进入下一题 / 结束训练
```

当前间隔是一个可替换的调度器：

- 记得：`1 / 3 / 7 / 14 / 30 / 60 / 90` 天
- 模糊：`1 / 2 / 4 / 7 / 14 / 30` 天
- 不会：回到短间隔，重新从 `1` 天开始

这不是把算法写死在 UI 里的终点，而是给后续 Scheduler 插件留下的第一版默认策略。

## 后续接入 Agent / LLM 的位置

现在的答案评价是用户自评，保证 GitHub Pages 在没有后端时也能工作。后续可以只替换三个适配点：

1. `QuestionRepository`：将静态 `catalog + packs` 换成 GitHub API 或内容服务。
2. `ProgressStore`：将 localStorage 换成 FastAPI / SQLite / PostgreSQL。
3. `Evaluator`：在查看参考答案后，把用户回答、题目 rubric 和上下文发送给自定义 LLM，返回结构化评分和追问建议。

Agent 不应直接修改学习状态。推荐由 Agent 产生 `evaluation` 事件，再由 Scheduler 根据事件更新 `schedules`，这样答题记录、评分和复习时间都可追溯。

## 静态部署

```bash
ruby tools/classify_questions.rb
ruby tools/build_web_data.rb
python3 -m http.server 8000
```

GitHub Pages 直接发布仓库根目录即可。题库 YAML 是可审阅的源内容，`data/` 是网页消费的构建产物。
