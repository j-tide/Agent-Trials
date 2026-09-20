#!/usr/bin/env ruby

require "digest"
require "fileutils"
require "json"
require "yaml"

AGENT_SOURCE_URL = "https://dqej47nflyz.feishu.cn/wiki/ZSBJw2ZqjiNOgVkAAPMc6ShRnYb"
LLM_SOURCE_URL = "https://dqej47nflyz.feishu.cn/wiki/O8KGwvToki7vbwkqKBbckhI1ngd"
IMPORTED_AT = "2026-09-20"

MODULE_DESCRIPTIONS = {
  "Agent 基础" => "智能体基本概念、核心组成与典型工作方式。",
  "Workflow vs Agent" => "工作流与智能体的差异、边界和选型判断。",
  "上下文管理与记忆" => "上下文窗口、长期记忆、短期记忆与上下文治理。",
  "Tool Calling / Function Call / MCP" => "工具调用、函数调用协议与 MCP 接入方式。",
  "6.5 Multi-Agent" => "多智能体协作、角色分工与任务编排。",
  "6.6 ReAct / 反思 / 任务规划" => "ReAct、反思机制、任务拆解与规划执行。",
  "6.7 异常处理 / 安全 / 熔断" => "异常恢复、安全控制、限流与熔断策略。",
  "幻觉与评测" => "幻觉识别、质量评测、可观测性与效果验证。",
  "Prompt 工程" => "提示词设计、结构化输出与提示词优化。",
  "模型相关" => "模型能力、模型选择、微调与推理相关问题。",
  "工程化与部署" => "服务化、部署、性能、稳定性与生产工程实践。",
  "Agent 场景设计题" => "面向真实业务的智能体方案设计与落地思路。",
  "网络基础八股文" => "网络协议、通信机制与服务端基础知识。",
  "Python 相关基础八股文" => "Python 语言、运行时与工程开发基础。",
  "AI大模型基础篇" => "大模型应用开发的来源分类，保留原始题库语义。",
  "模型基础" => "模型原理、能力边界、训练微调、推理与多模态。",
  "行业应用" => "AI 在云盘、客服等行业场景中的应用与落地。",
  "RAG 与知识库" => "检索增强生成、向量检索、嵌入与知识库。",
  "工程实践" => "项目架构、环境、类型安全、性能与工程质量。",
  "Agent 与工具" => "智能体、工具使用、多轮交互与任务执行。",
  "LangChain" => "LangChain 核心组件、生态与应用开发。",
  "安全与合规" => "安全、隐私、风险控制与合规要求。",
  "Prompt 与推理" => "提示词、推理过程、上下文与输出控制。"
}.freeze

def load_export(path)
  value = JSON.parse(File.read(path, encoding: "UTF-8"))
  value = JSON.parse(value) if value.is_a?(String)
  value
end

def block_text(snapshot)
  value = snapshot.dig("text", "initialAttributedTexts", "text")
  return "" if value.nil?
  return value if value.is_a?(String)

  value.keys.sort_by(&:to_i).map { |key| value[key] }.join
end

def render_block(block)
  snapshot = block.fetch("snapshot", {})
  text = block_text(snapshot).to_s.strip
  type = block.fetch("type", "")

  case type
  when "text"
    text.empty? ? nil : text
  when "bullet", "ordered"
    text.empty? ? nil : "- #{text}"
  when "code"
    return nil if text.empty?
    language = snapshot.fetch("language", "text").to_s.downcase
    language = "text" if language.empty? || language == "plain text"
    "```#{language}\n#{text}\n```"
  when "heading1", "heading2", "heading3"
    text.empty? ? nil : "### #{text}"
  when "divider"
    "---"
  when "image"
    "[图片内容未导入]"
  when "sheet"
    "[嵌入表格未展开]"
  else
    text.empty? ? nil : text
  end
end

def body_between(blocks, start_index, stop_types)
  rendered = []
  index = start_index + 1
  while index < blocks.length
    block = blocks[index]
    break if stop_types.include?(block["type"])

    value = render_block(block)
    rendered << value unless value.nil? || value.empty?
    index += 1
  end

  rendered.join("\n\n").strip
end

def title_of(block)
  block_text(block.fetch("snapshot", {})).strip
end

def build_question(block, blocks, index, pack_id, category, source_url, ordinal, stop_types, derived_topic: nil)
  title = title_of(block)
  block_id = block.fetch("id")
  answer = body_between(blocks, index, stop_types)
  digest = Digest::SHA1.hexdigest("#{source_url}##{block_id}")[0, 10]
  question_id = "#{pack_id}-#{format('%03d', ordinal)}-#{digest}"

  {
    "schema_version" => 1,
    "id" => question_id,
    "version" => 1,
    "type" => "short_answer",
    "status" => "imported",
    "review_status" => "pending",
    "language" => "zh-CN",
    "title" => title,
    "summary" => "从飞书题库导入，保留原题目解析，等待校对。",
    "difficulty" => nil,
    "estimated_minutes" => 10,
    "category" => category,
    "derived_topic" => derived_topic,
    "tags" => [category, derived_topic].compact.uniq,
    "content" => {
      "prompt" => title
    },
    "answer" => {
      "mode" => "rubric",
      "reference_answer" => answer.empty? ? "原文未提供解析。" : answer
    },
    "evaluation" => {
      "plugin" => "llm_judge",
      "config" => {
        "score" => 100,
        "criteria" => [
          "是否覆盖题目要求的核心概念",
          "是否给出清晰的工程实现或判断依据",
          "是否说明关键权衡、风险或适用边界"
        ]
      }
    },
    "learning" => {
      "concepts" => [category],
      "scheduler" => {
        "initial_interval_days" => 1,
        "max_interval_days" => 30
      }
    },
    "source" => {
      "type" => "user_provided_feishu",
      "url" => source_url,
      "block_id" => block_id,
      "original_title" => title,
      "imported_at" => IMPORTED_AT
    }
  }
end

def extract_agent_rag_questions(blocks)
  network_index = blocks.index do |block|
    block["type"] == "heading1" && title_of(block) == "网络基础八股文"
  end
  python_index = blocks.index do |block|
    block["type"] == "heading1" && title_of(block) == "二、Python 相关基础八股文"
  end
  raise "source headings not found" unless network_index && python_index

  questions = []
  ordinal = 0
  category = "Agent 基础"

  (0...network_index).each do |index|
    block = blocks[index]
    case block["type"]
    when "heading2"
      category = title_of(block)
    when "heading3"
      ordinal += 1
      questions << build_question(
        block, blocks, index, "feishu-agent-rag", category, AGENT_SOURCE_URL,
        ordinal, ["heading1", "heading2", "heading3"]
      )
    end
  end

  (network_index + 1...python_index).each do |index|
    block = blocks[index]
    next unless block["type"] == "heading1"

    ordinal += 1
    questions << build_question(
      block, blocks, index, "feishu-agent-rag", "网络基础八股文", AGENT_SOURCE_URL,
      ordinal, ["heading1"]
    )
  end

  (python_index + 1...blocks.length).each do |index|
    block = blocks[index]
    next unless block["type"] == "heading2"

    title = title_of(block)
    next if title == "全方位深度解析 · 大厂面试官视角"

    ordinal += 1
    questions << build_question(
      block, blocks, index, "feishu-agent-rag", "Python 相关基础八股文", AGENT_SOURCE_URL,
      ordinal, ["heading1", "heading2"]
    )
  end

  questions
end

def llm_topic(title)
  return "RAG 与知识库" if title.match?(/RAG|检索|向量|嵌入|知识库/)
  return "Agent 与工具" if title.match?(/Agent|MCP|工具|多Agent|智能体/)
  return "LangChain" if title.match?(/LangChain/)
  return "Prompt 与推理" if title.match?(/Prompt|提示|CoT|ReAct|输出解析器|多轮对话|上下文/)
  return "安全与合规" if title.match?(/安全|合规|隐私|风险/)
  return "行业应用" if title.match?(/AI\+/)
  return "模型基础" if title.match?(/模型|Token|微调|蒸馏|推理|多模态|零样本|少样本/)

  "工程实践"
end

def extract_llm_questions(blocks)
  questions = []
  ordinal = 0
  blocks.each_with_index do |block, index|
    next unless block["type"] == "heading2"

    ordinal += 1
    title = title_of(block)
    questions << build_question(
      block, blocks, index, "feishu-llm-foundations", "AI大模型基础篇", LLM_SOURCE_URL,
      ordinal, ["heading1", "heading2"], derived_topic: llm_topic(title)
    )
  end
  questions
end

def directory_for_category(category)
  mapping = {
    "Agent 基础" => "智能体基础",
    "Workflow vs Agent" => "工作流与智能体",
    "上下文管理与记忆" => "上下文管理与记忆",
    "Tool Calling / Function Call / MCP" => "工具调用-函数调用-MCP",
    "6.5 Multi-Agent" => "多智能体",
    "6.6 ReAct / 反思 / 任务规划" => "ReAct-反思-任务规划",
    "6.7 异常处理 / 安全 / 熔断" => "异常处理-安全-熔断",
    "幻觉与评测" => "幻觉与评测",
    "Prompt 工程" => "提示词工程",
    "模型相关" => "模型相关",
    "工程化与部署" => "工程化与部署",
    "Agent 场景设计题" => "智能体场景设计题",
    "网络基础八股文" => "网络基础八股文",
    "Python 相关基础八股文" => "Python 基础八股文",
    "AI大模型基础篇" => "大模型基础篇"
  }
  mapping.fetch(category) { "其他" }
end

def directory_for_module(module_name)
  mapping = {
    "模型基础" => "模型基础",
    "行业应用" => "行业应用",
    "RAG 与知识库" => "RAG 与知识库",
    "工程实践" => "工程实践",
    "Agent 与工具" => "智能体与工具",
    "LangChain" => "LangChain",
    "安全与合规" => "安全与合规",
    "Prompt 与推理" => "提示词与推理"
  }
  mapping.fetch(module_name) { directory_for_category(module_name) }
end

def module_name_for(pack_id, question)
  pack_id == "feishu-llm-foundations" ? question.fetch("derived_topic") : question.fetch("category")
end

def module_directory_for(pack_id, module_name)
  pack_id == "feishu-llm-foundations" ? directory_for_module(module_name) : directory_for_category(module_name)
end

def module_label_for(pack_id, module_name)
  module_directory_for(pack_id, module_name)
end

def filename_title(title)
  normalized = title.to_s.strip.sub(/\A\d+\s*[-—、.．:：]\s*/, "")
  normalized = normalized.gsub(/[？?]/, "")
  normalized = normalized.gsub(/["“”]/, "")
  normalized = normalized.gsub(%r{[\\/:*<>|]}, "-")
  normalized = normalized.gsub(/\s+/, " ").strip
  normalized = normalized.gsub(/[。！？?!．.]+\z/, "")
  normalized = normalized.gsub(/\A[. ]+|[. ]+\z/, "")
  normalized.empty? ? "未命名题目" : normalized
end

def question_filename(question, used_names)
  ordinal = question.fetch("id").match(/-(\d+)-/)&.[](1).to_i
  base = "#{format('%03d', ordinal)}-#{filename_title(question.fetch('title'))}"
  filename = "#{base}.yaml"
  unless used_names[filename].nil?
    digest = question.fetch("source").fetch("block_id").to_s[-8, 8]
    filename = "#{base}-#{digest}.yaml"
  end
  used_names[filename] = true
  filename
end

def module_description(module_name)
  MODULE_DESCRIPTIONS.fetch(module_name) { "按题库来源分类整理，后续可继续细分。" }
end

def write_pack(root, pack_id, title, source_url, questions)
  pack_root = File.join(root, pack_id)
  FileUtils.mkdir_p(pack_root)
  used_names = {}

  questions.each do |question|
    module_name = module_name_for(pack_id, question)
    module_dir = File.join(pack_root, module_directory_for(pack_id, module_name))
    FileUtils.mkdir_p(module_dir)
    path = File.join(module_dir, question_filename(question, used_names))
    File.write(path, question.to_yaml, mode: "w", encoding: "UTF-8")
  end

  category_counts = questions.group_by { |question| question.fetch("category") }
    .transform_values(&:length)
  module_counts = questions.group_by { |question| module_name_for(pack_id, question) }
    .transform_values(&:length)
  manifest = {
    "schema_version" => 1,
    "id" => pack_id,
    "version" => 1,
    "title" => title,
    "status" => "imported",
    "source" => {
      "type" => "user_provided_feishu",
      "url" => source_url,
      "imported_at" => IMPORTED_AT
    },
    "question_count" => questions.length,
    "categories" => category_counts,
    "modules" => module_counts
  }
  File.write(File.join(pack_root, "manifest.yaml"), manifest.to_yaml, mode: "w", encoding: "UTF-8")

  module_rows = module_counts.map do |module_name, count|
    directory = module_directory_for(pack_id, module_name)
    label = module_label_for(pack_id, module_name)
    "| #{label} | #{count} | [打开模块](<./#{directory}/>) | #{module_description(module_name)} |"
  end.join("\n")
  classification_note = if pack_id == "feishu-llm-foundations"
    "保留来源分类 `AI大模型基础篇`，并根据题目标题生成 `derived_topic` 作为刷题模块。"
  else
    "按飞书原始分类整理，每个模块对应一个中文目录。"
  end
  readme = <<~MARKDOWN
    # #{title}

    - 来源：#{source_url}
    - 导入时间：#{IMPORTED_AT}
    - 题目数量：#{questions.length}
    - 状态：已导入，待校对

    ## 模块总览

    #{classification_note}

    | 模块 | 题量 | 目录 | 覆盖内容 |
    | --- | ---: | --- | --- |
    #{module_rows}

    ## 数据说明

    题目文件名使用“序号-中文题目.yaml”，方便在 GitHub 中直接浏览；文件内的 `id` 保持稳定，用于统计、答题记录和后续同步。

    `source` 字段保留原始飞书 block id，`answer.reference_answer` 保留原文解析。
  MARKDOWN
  File.write(File.join(pack_root, "README.md"), readme, mode: "w", encoding: "UTF-8")
end

abort "usage: import_feishu_question_bank.rb AGENT_JSON LLM_JSON OUTPUT_ROOT" unless ARGV.length == 3

agent_blocks = load_export(ARGV[0])
llm_blocks = load_export(ARGV[1])
output_root = ARGV[2]
FileUtils.mkdir_p(output_root)

agent_questions = extract_agent_rag_questions(agent_blocks)
llm_questions = extract_llm_questions(llm_blocks)
write_pack(output_root, "feishu-agent-rag", "AI应用开发面试题 / Agent / RAG", AGENT_SOURCE_URL, agent_questions)
write_pack(output_root, "feishu-llm-foundations", "AI大模型面试题 / 基础篇", LLM_SOURCE_URL, llm_questions)

summary = {
  "imported_at" => IMPORTED_AT,
  "packs" => {
    "feishu-agent-rag" => agent_questions.length,
    "feishu-llm-foundations" => llm_questions.length
  },
  "total_questions" => agent_questions.length + llm_questions.length
}
File.write(File.join(output_root, "manifest.yaml"), summary.to_yaml, mode: "w", encoding: "UTF-8")
puts summary.to_yaml
