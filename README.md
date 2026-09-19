# Agent Trials

智能体试炼塔：一个面向 Agent 工程能力的刷题与学习进度追踪原型。

## 当前版本

- 静态 Web MVP，入口为 [`index.html`](./index.html)
- 支持示例题刷题、答案反馈、今日完成数、正确率和能力掌握度统计
- 学习进度保存在浏览器 `localStorage`，键名为 `agent-trials.progress.v1`
- 题库和学习进度分离，后续题库将独立放入 GitHub Content Repository
- 进度存储与迁移设计见 [`docs/progress-storage.md`](./docs/progress-storage.md)

## 本地预览

```bash
python -m http.server 8000
```

然后打开 <http://localhost:8000>。

## GitHub Pages

此仓库的 `main` 分支根目录作为 GitHub Pages 发布目录。
