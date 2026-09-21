#!/usr/bin/env ruby
require "digest"
require "fileutils"
require "json"
require "yaml"

IMPORTED_AT = "2026-09-21"
PACK_ID = "feishu-llm-complete"
PACK_TITLE = "大模型全套面试题-持续更新~"
SOURCE_ROOT_URL = "https://lcnipys9u0xh.feishu.cn/wiki/PFMJwZ2SCiWyPskpSVKcxBeknSb"
SOURCE_HOST = "https://lcnipys9u0xh.feishu.cn/wiki/"
HEADING_TYPES = %w[heading1 heading2 heading3].freeze
SKIP_PATTERNS = [
  /容易一起考的题/, /\A(?:最终)?总结(?:[：:]|\z)/, /\A小结(?:[：:]|\z)/,
  /\A设计哲学\z/, /\A适用场景\z/, /\A优缺点\z/, /流程(?:图|示意)\z/,
  /\A关键说明\z/, /对比总表\z/, /选型建议速查\z/, /\A最佳实践\z/,
  /\A思考延伸\z/, /\A避坑指南\z/
].freeze
MODULE_DESCRIPTIONS = Hash.new("按飞书原始分类整理，后续可继续细分。").merge(
  "LLMs（大语言模型）持续更新~" => "模型架构、预训练、微调、推理、RAG、Agent、评测与工程实践。",
  "Transfomer精选面试" => "Transformer 架构、位置编码、训练优化、推理部署与经典模型。",
  "LangChain面（高频）" => "LangChain 组件、检索器、记忆、Agent、生产部署与安全。",
  "AI Agent精选八股文" => "Agent 基础、工具、架构、记忆、评测、部署以及工程基础。",
  "多模态面（精选）" => "多模态模型、训练对齐、评估、部署与前沿方向。",
  "深度学习面（精选）" => "神经网络、优化、CNN、序列模型、生成模型与训练部署。",
  "RAG核心面（精选）" => "RAG 链路、分块、检索、向量数据库、Rerank、评估与生产实践。",
  "RLHF面试高频考点" => "偏好数据、奖励建模、PPO/DPO、评估监控与训练部署。",
  "SFT面（精选）" => "SFT 定位、数据工程、训练实践、评估诊断与偏好对齐。",
  "LoRA 高频面试题" => "LoRA/QLoRA 原理、实现细节、训练实践与 PEFT 对比。",
  "NLP专项高频面试（学习检测/面试都可用）" => "NLP、Transformer、RNN、BERT、解码与大模型基础。",
  "Python面" => "Python 语言基础、工程实践与常见面试题。",
  "PyTorch 面试八股" => "张量、自动求导、模块、数据、训练、分布式与部署。",
  "机器学习专项面试（学习检测/面试都可用）" => "机器学习基础、特征工程、模型融合与面试综合题。",
  "大模型手撕-核心题" => "大模型岗位常见算法、算子、工程优化与系统设计手撕题。",
  "大模型推理-核心题" => "显存、KV Cache、量化、推理加速、框架与性能评估。",
  "大模型评测面试题" => "评测指标、基准、LLM-as-a-Judge、安全性与评测工程。",
  "大模型微调-核心题" => "微调方法、数据工程、对齐、分布式训练与项目实践。",
  "大模型蒸馏面试-核心题" => "知识蒸馏方法、目标设计、训练策略与工程落地。",
  "大模型幻觉面" => "幻觉类型、成因、检测、缓解与系统可靠性。",
  "显存问题-核心题" => "显存构成、估算、优化、诊断调优与前沿实践。",
  "分布式训练-核心题" => "数据并行、模型并行、通信、ZeRO、稳定性与容错。"
)

def load_result(path)
  raw = File.read(path, encoding: "UTF-8")
  json = raw.include?("### Result\n") ? raw.split("### Result\n", 2).fetch(1).split("\n### Ran", 2).first : raw
  JSON.parse(json)
end

def clean(value)
  value.to_s.gsub("\u0000", "").strip
end

def heading_value(value)
  clean(value).sub(/\A[^\p{Han}\p{Latin}\p{N}]*/u, "").strip
end

def strong_heading?(value)
  text = clean(value)
  return false if text.empty?
  return true if text.match?(/[?？]/)
  return true if heading_value(text).match?(/\A\d+\s*[-—、.．:：)]/)
  heading_value(text).match?(/\A(?:什么|如何|为什么|为何|请|简述|解释|说明|比较|对比|区别|描述|介绍|分析|谈谈|说说|列举|能否|是否|有哪些|怎么|怎样|如何理解)/)
end

def skipped_heading?(value)
  SKIP_PATTERNS.any? { |pattern| heading_value(value).match?(pattern) }
end

def choose_headings(blocks)
  indices = blocks.each_index.select { |index| HEADING_TYPES.include?(blocks[index]["type"]) }
  return [nil, []] if indices.empty?
  scores = HEADING_TYPES.to_h do |type|
    [type, indices.count { |index| blocks[index]["type"] == type && strong_heading?(blocks[index]["text"]) }]
  end
  max_score = scores.values.max || 0
  chosen = max_score.positive? ? HEADING_TYPES.find { |type| scores[type] == max_score } : blocks[indices.first]["type"]
  candidates = indices.select { |index| blocks[index]["type"] == chosen && !skipped_heading?(blocks[index]["text"]) }
  candidates = indices.select { |index| blocks[index]["type"] == chosen } if candidates.empty?
  [chosen, candidates]
end

def render_block(block)
  type = block.fetch("type", "")
  text = clean(block["text"])
  return nil if %w[image sheet].include?(type) && false
  case type
  when "text", "callout", "quote", "todo", "isv"
    text.empty? ? nil : text
  when "bullet", "ordered"
    text.empty? ? nil : "- #{text}"
  when "code"
    return nil if text.empty?
    language = clean(block["language"])
    language = "text" if language.empty? || language.casecmp("plain text").zero?
    fence = 0x60.chr * 3
    [fence + language.downcase, text, fence].join("\n")
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

def stop_types(type)
  { "heading1" => ["heading1"], "heading2" => ["heading1", "heading2"], "heading3" => ["heading1", "heading3"] }.fetch(type, HEADING_TYPES)
end

def body_between(blocks, start_index, stops)
  values = []
  (start_index + 1...blocks.length).each do |index|
    break if stops.include?(blocks[index]["type"])
    rendered = render_block(blocks[index])
    values << rendered unless rendered.nil? || rendered.empty?
  end
  values.join("\n\n").strip
end

def safe_segment(value)
  result = value.to_s.strip.gsub(/[\\\/:*?"<>|]/, "-").gsub(/\s+/, " ").gsub(/\A[. ]+|[. ]+\z/, "")
  result.empty? ? "其他" : result
end

def filename_title(value)
  result = clean(value).sub(/\A\d+\s*[-—、.．:：]\s*/, "").gsub(/[？?]/, "").gsub(/["“”]/, "")
    .gsub(/[\\\/:*<>|]/, "-").gsub(/\s+/, " ").gsub(/[。！？?!．.]+\z/, "")
    .gsub(/\A[. ]+|[. ]+\z/, "")
  result.empty? ? "未命名题目" : result
end

def make_question(title:, answer:, category:, path:, url:, block_id:, page_token:, stub:)
  source = {
    "type" => "user_provided_feishu", "url" => url, "block_id" => block_id,
    "page_token" => page_token, "original_title" => title, "imported_at" => IMPORTED_AT
  }
  source["unparsed_attachment"] = true if stub
  digest = Digest::SHA1.hexdigest("#{url}##{block_id}")[0, 12]
  tags = (path.empty? ? [category] : path).uniq
  {
    "schema_version" => 1, "id" => "#{PACK_ID}-#{digest}", "version" => 1,
    "type" => "short_answer", "status" => "imported", "review_status" => "pending",
    "language" => "zh-CN", "title" => title,
    "summary" => stub ? "原始页面为飞书 PDF/附件，当前未能提取正文，保留题目链接等待补录。" : "从飞书题库导入，保留原题目解析，等待校对。",
    "difficulty" => nil, "estimated_minutes" => 10, "category" => category,
    "derived_topic" => path.length > 1 ? path[1..].join(" / ") : nil, "tags" => tags,
    "content" => { "prompt" => title },
    "answer" => { "mode" => "rubric", "reference_answer" => answer.empty? ? "原文未提供可解析的正文，请打开 source.url 补录答案。" : answer },
    "evaluation" => {
      "plugin" => "llm_judge",
      "config" => { "score" => 100, "criteria" => ["是否覆盖题目要求的核心概念", "是否给出清晰的工程实现或判断依据", "是否说明关键权衡、风险或适用边界"] }
    },
    "learning" => { "concepts" => tags, "scheduler" => { "initial_interval_days" => 1, "max_interval_days" => 30 } },
    "source" => source
  }
end

def leaf_questions(leaf)
  blocks = leaf.fetch("blocks", [])
  type, indices = choose_headings(blocks)
  return [] if type.nil?
  category = leaf.fetch("path", []).first || "其他"
  path = leaf.fetch("path", [])
  indices.map do |index|
    block = blocks[index]
    title = clean(block["text"])
    next if title.empty?
    block_id = clean(block["record_id"])
    block_id = clean(block["id"]) if block_id.empty?
    make_question(
      title: title, answer: body_between(blocks, index, stop_types(type)),
      category: category, path: path, url: leaf.fetch("url"),
      block_id: block_id, page_token: leaf.fetch("token"), stub: false
    )
  end.compact
end

def stub_questions(stubs)
  stubs.map do |stub|
    token = stub.fetch("token")
    make_question(
      title: clean(stub.fetch("title")), answer: "", category: stub.fetch("path", []).first || "其他",
      path: stub.fetch("path", []), url: "#{SOURCE_HOST}#{token}",
      block_id: "page:#{token}", page_token: token, stub: true
    )
  end
end

def filename_for(question, ordinal, used)
  base = "#{format("%05d", ordinal)}-#{filename_title(question.fetch("title"))}"
  name = "#{base}.yaml"
  unless used[name].nil?
    name = "#{base}-#{question.fetch("source").fetch("block_id").to_s[-8, 8]}.yaml"
  end
  used[name] = true
  name
end

def write_pack(output_root, questions, records, stubs)
  pack_root = File.join(output_root, PACK_ID)
  FileUtils.mkdir_p(pack_root)
  used = Hash.new { |hash, key| hash[key] = {} }
  questions.each_with_index do |question, index|
    parts = question.fetch("tags").map { |tag| safe_segment(tag) }
    directory = File.join(pack_root, *parts)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, filename_for(question, index + 1, used[directory])), question.to_yaml, mode: "w", encoding: "UTF-8")
  end

  category_counts = questions.group_by { |question| question.fetch("category") }.transform_values(&:length)
  module_counts = questions.group_by { |question| question.fetch("tags").map { |tag| safe_segment(tag) }.join(" / ") }.transform_values(&:length)
  content_count = questions.count { |question| !question.fetch("source").fetch("unparsed_attachment", false) }
  stub_count = questions.length - content_count
  manifest = {
    "schema_version" => 1, "id" => PACK_ID, "version" => 1, "title" => PACK_TITLE, "status" => "imported",
    "source" => { "type" => "user_provided_feishu", "url" => SOURCE_ROOT_URL, "imported_at" => IMPORTED_AT },
    "source_page_count" => records.length + stubs.length, "content_page_count" => records.length,
    "attachment_stub_count" => stub_count, "question_count" => questions.length,
    "content_question_count" => content_count, "categories" => category_counts, "modules" => module_counts
  }
  File.write(File.join(pack_root, "manifest.yaml"), manifest.to_yaml, mode: "w", encoding: "UTF-8")

  rows = module_counts.sort_by { |name, _count| name }.map do |name, count|
    parts = name.split(" / ")
    directory = parts.map { |part| safe_segment(part) }.join("/")
    description = parts.length == 1 ? MODULE_DESCRIPTIONS[parts.first] : "#{parts.first} 下的专题模块。"
    "| #{name} | #{count} | [打开模块](<./#{directory}/>) | #{description} |"
  end.join("\n")
  readme = <<~MARKDOWN
    # #{PACK_TITLE}

    - 来源：#{SOURCE_ROOT_URL}
    - 导入时间：#{IMPORTED_AT}
    - 题目数量：#{questions.length}（正文题 #{content_count}，附件待补录 #{stub_count}）
    - 原始页面：#{records.length} 个含正文的叶子页，#{stubs.length} 个 PDF/附件页
    - 状态：已导入，待校对

    ## 模块总览

    按飞书原始目录的“根模块 / 专题模块”生成中文目录；题目文件保留原始页面 URL 和 block id，便于回溯。

    | 模块 | 题量 | 目录 | 覆盖内容 |
    | --- | ---: | --- | --- |
    #{rows}

    ## 数据说明

    题目文件名使用“序号-中文题目.yaml”，文件内的 id 使用来源 URL 与 block id 的稳定摘要，可用于答题记录、统计和后续同步。

    answer.reference_answer 保留飞书原文解析。原始页面为 PDF/附件且无法从飞书 block 服务读取正文的条目，会保留题目和来源链接，并标记 source.unparsed_attachment: true，等待后续补录。
  MARKDOWN
  File.write(File.join(pack_root, "README.md"), readme, mode: "w", encoding: "UTF-8")
  { "pack_id" => PACK_ID, "question_count" => questions.length, "content_question_count" => content_count,
    "attachment_stub_count" => stub_count, "content_page_count" => records.length,
    "attachment_page_count" => stubs.length, "category_counts" => category_counts, "module_counts" => module_counts }
end

abort "usage: import_feishu_hierarchical_crawl.rb OUTPUT_ROOT STUBS_JSON ROOT_COVERAGE_JSON CRAWL_LOG..." if ARGV.length < 4
output_root, stubs_path, root_coverage_path, *crawl_paths = ARGV
leaves = crawl_paths.each_with_index.flat_map do |path, priority|
  load_result(path).fetch("leaves", []).map { |leaf| leaf.merge("_source_priority" => priority) }
end
records = leaves.group_by { |leaf| leaf.fetch("token") }.transform_values do |items|
  items.max_by { |item| [item.fetch("blocks", []).length, -item.fetch("_source_priority")] }
end
records.each_value { |leaf| leaf.delete("_source_priority") }
root_coverage = load_result(root_coverage_path)
direct_parent_paths = {}
direct_parent_labels = Hash.new { |hash, key| hash[key] = [] }
root_coverage.each do |parent|
  parent_label = parent.fetch("label")
  parent.fetch("nodes", []).each do |node|
    next if node.fetch("token") == parent.fetch("token")
    direct_parent_paths[node.fetch("token")] = [parent_label]
    direct_parent_labels[node.fetch("label")] << parent_label
  end
end
records.each do |token, leaf|
  if direct_parent_paths.key?(token)
    leaf["path"] = direct_parent_paths[token]
  elsif leaf.fetch("path", []).any? && direct_parent_labels[leaf.fetch("path").first].uniq.length == 1
    parent_label = direct_parent_labels[leaf.fetch("path").first].first
    leaf["path"] = [parent_label, *leaf.fetch("path")]
  end
end
stubs = JSON.parse(File.read(stubs_path, encoding: "UTF-8")).reject { |stub| records.key?(stub.fetch("token")) }
questions = records.values.sort_by { |leaf| [leaf.fetch("path", []).join(" / "), leaf.fetch("url"), leaf.fetch("title")] }.flat_map { |leaf| leaf_questions(leaf) }
questions.concat(stub_questions(stubs))
questions.sort_by! { |question| [question.fetch("category"), question.fetch("derived_topic").to_s, question.fetch("title"), question.fetch("id")] }
puts write_pack(output_root, questions, records, stubs).to_yaml
