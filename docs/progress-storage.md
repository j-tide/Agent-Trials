# Agent Trials 学习进度存储设计

## 结论

题库和学习进度分开存储：

| 数据 | 第一版位置 | 后续位置 |
| --- | --- | --- |
| 题目、技能、标签、评分标准 | GitHub Content Repository | GitHub Content Repository |
| 答题记录、正确率、掌握度、复习时间 | 浏览器 `localStorage` | FastAPI + SQLite，必要时迁移 PostgreSQL |

题库是版本化内容，学习进度是运行时状态，不应该提交回题库仓库。

## 当前网页 MVP

当前页面使用存储键：

```text
agent-trials.progress.v1
```

示例数据结构：

```json
{
  "version": 1,
  "day": "2026-09-19",
  "completedToday": 6,
  "dailyGoal": 10,
  "streakDays": 12,
  "mastery": {
    "Agent 基础": 78,
    "Tool Calling": 64,
    "RAG & Memory": 52,
    "Evaluation": 41
  },
  "attempts": [
    {
      "questionId": "agent-harness",
      "domain": "Agent 基础",
      "day": "2026-09-19",
      "isCorrect": true,
      "selectedAnswer": 1,
      "createdAt": "2026-09-19T05:00:00.000Z"
    }
  ]
}
```

页面通过 `ProgressStore` 访问数据，因此以后接入后端时，只需要把 `load/save` 换成 API 调用。

## 后端版本建议

```text
Web UI
  -> Progress API
      -> attempts              原始答题事件
      -> mastery_states        技能/概念掌握状态
      -> study_sessions        一次训练会话
      -> scheduler              计算 next_review_at
```

建议的核心表：

```sql
attempts(
  id, user_id, question_id, question_version,
  content_commit_sha, selected_answer, is_correct,
  score, latency_ms, created_at
)

mastery_states(
  user_id, concept_id, mastery, stability,
  difficulty, last_review_at, next_review_at,
  consecutive_correct, total_reviews, updated_at
)

study_sessions(
  id, user_id, goal, started_at, completed_at,
  question_count, correct_count
)
```

每次答题都保存 `question_version` 和 `content_commit_sha`，这样即使 GitHub 题库后来更新，也能复现当时的题目和评分结果。

## 迁移路径

1. 现在：静态网页 + `localStorage`，验证刷题交互。
2. 下一步：FastAPI + SQLite，进度从浏览器移动到服务端。
3. 多设备/多人使用：SQLite 替换为 PostgreSQL，页面 API 不变。
4. 自适应刷题：新增 Scheduler 插件，根据 `mastery_states` 生成今日队列。
