# Agent Trials 学习进度存储设计

## 结论

题库和学习进度分开存储：

| 数据 | 第一版位置 | 后续位置 |
| --- | --- | --- |
| 题目、技能、标签、评分标准 | GitHub Content Repository | GitHub Content Repository |
| 答题记录、正确率、掌握度、复习时间 | 浏览器 `localStorage` | FastAPI + SQLite，必要时迁移 PostgreSQL |

题库是版本化内容，学习进度是运行时状态，不应该提交回题库仓库。

## 当前网页版本

当前页面使用存储键：

```text
agent-trials.progress.v2
```

示例数据结构：

```json
{
  "version": 2,
  "dailyGoal": 10,
  "schedules": {
    "feishu-llm-complete-001": {
      "repetitions": 2,
      "intervalDays": 3,
      "lastRating": "remember",
      "lastReviewedAt": "2026-09-21T06:00:00.000Z",
      "nextReviewAt": "2026-09-24T06:00:00.000Z"
    }
  },
  "attempts": [
    {
      "questionId": "feishu-llm-complete-001",
      "day": "2026-09-21",
      "rating": "remember",
      "answerLength": 156,
      "reviewedAt": "2026-09-21T06:00:00.000Z"
    }
  ],
  "drafts": {
    "feishu-llm-complete-002": "尚未提交的回答草稿"
  }
}
```

页面通过 `loadProgress/saveProgress` 访问数据，因此以后接入后端时，只需要替换这个存储适配层，不需要改刷题页面和调度策略。

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
