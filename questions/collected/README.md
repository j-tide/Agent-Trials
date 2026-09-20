# 已收集题库

本目录保存从用户提供的飞书知识库导入的第一批题目。每个题库的 README 都提供了可直接点击的模块总览。

| 题库 | 数量 | 模块划分 |
| --- | ---: | --- |
| [`AI应用开发面试题 / Agent / RAG`](./feishu-agent-rag/) | 148 | 按飞书原始分类建中文目录 |
| [`AI大模型面试题 / 基础篇`](./feishu-llm-foundations/) | 101 | 按 `derived_topic` 划分刷题模块 |

共 249 道题。导入题目统一使用 `short_answer` + `llm_judge`，因为原始题库主要是面试开放题；后续可以根据内容再细分为选择题、编程题或 Agent 实战题。

## 模块总览

### AI 应用开发 / Agent / RAG

| 模块 | 题量 | 目录 |
| --- | ---: | --- |
| 智能体基础 | 11 | [打开](<./feishu-agent-rag/智能体基础/>) |
| 工作流与智能体 | 5 | [打开](<./feishu-agent-rag/工作流与智能体/>) |
| 上下文管理与记忆 | 21 | [打开](<./feishu-agent-rag/上下文管理与记忆/>) |
| 工具调用-函数调用-MCP | 13 | [打开](<./feishu-agent-rag/工具调用-函数调用-MCP/>) |
| 多智能体 | 8 | [打开](<./feishu-agent-rag/多智能体/>) |
| ReAct-反思-任务规划 | 7 | [打开](<./feishu-agent-rag/ReAct-反思-任务规划/>) |
| 异常处理-安全-熔断 | 11 | [打开](<./feishu-agent-rag/异常处理-安全-熔断/>) |
| 幻觉与评测 | 12 | [打开](<./feishu-agent-rag/幻觉与评测/>) |
| 提示词工程 | 4 | [打开](<./feishu-agent-rag/提示词工程/>) |
| 模型相关 | 8 | [打开](<./feishu-agent-rag/模型相关/>) |
| 工程化与部署 | 9 | [打开](<./feishu-agent-rag/工程化与部署/>) |
| 智能体场景设计题 | 11 | [打开](<./feishu-agent-rag/智能体场景设计题/>) |
| 网络基础八股文 | 16 | [打开](<./feishu-agent-rag/网络基础八股文/>) |
| Python 基础八股文 | 12 | [打开](<./feishu-agent-rag/Python 基础八股文/>) |

### 大模型基础篇

| 模块 | 题量 | 目录 |
| --- | ---: | --- |
| 模型基础 | 22 | [打开](<./feishu-llm-foundations/模型基础/>) |
| 行业应用 | 18 | [打开](<./feishu-llm-foundations/行业应用/>) |
| RAG 与知识库 | 15 | [打开](<./feishu-llm-foundations/RAG 与知识库/>) |
| 工程实践 | 11 | [打开](<./feishu-llm-foundations/工程实践/>) |
| 智能体与工具 | 10 | [打开](<./feishu-llm-foundations/智能体与工具/>) |
| LangChain | 9 | [打开](<./feishu-llm-foundations/LangChain/>) |
| 安全与合规 | 8 | [打开](<./feishu-llm-foundations/安全与合规/>) |
| 提示词与推理 | 8 | [打开](<./feishu-llm-foundations/提示词与推理/>) |

## 数据说明

题目文件名使用“序号-中文题目.yaml”，方便在 GitHub 中直接浏览；文件内的 `id` 保持稳定，用于统计、答题记录和后续同步。

当前所有题目均标记为 `review_status: pending`，原因是原文内容需要进一步做去重、事实校对、难度分级和题型细化。

每道题的 `source` 字段保留原始飞书页面链接、block id、原始题目标题和导入日期。访问密码不会写入仓库。
