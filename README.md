# Agent Trials

智能体试炼塔：面向 AI / Agent 面试的刷题、间隔复习与学习报告工作台。

## 当前版本

- 四个真实工作区：今日训练、开始刷题、题库浏览、学习报告
- 接入 `feishu-llm-complete` 题库，共 9158 道题、22 个模块
- 简答题采用“先回答 → 看参考答案 → 自评记忆程度 → 自动安排复习”的训练闭环
- 支持题库搜索、模块筛选、未开始 / 待复习 / 已练习筛选、随机挑战和薄弱项强化
- 学习进度保存在浏览器 `localStorage`，键名为 `agent-trials.progress.v2`
- 题库索引首屏加载，题目正文按模块懒加载，适合直接部署到 GitHub Pages

架构和后续接入自定义 LLM 的边界见 [`docs/web-architecture.md`](./docs/web-architecture.md)；进度存储迁移设计见 [`docs/progress-storage.md`](./docs/progress-storage.md)。

## 本地预览

```bash
python3 -m http.server 8000
```

然后打开 <http://localhost:8000>。如果题库源 YAML 有更新，先重新生成网页数据：

```bash
ruby tools/build_web_data.rb questions/collected/feishu-llm-complete data
```

## GitHub Pages

此仓库的 `main` 分支根目录作为 GitHub Pages 发布目录，入口为 [`index.html`](./index.html)。
