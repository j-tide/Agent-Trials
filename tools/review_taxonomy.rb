#!/usr/bin/env ruby

require "json"
require "time"

QUEUE_PATH = ARGV[0] || "questions/taxonomy/review-queue.jsonl"
OUTPUT_PATH = ARGV[1] || "questions/taxonomy/review-report.md"

rows = File.foreach(QUEUE_PATH).each_with_object([]) do |line, items|
  next if line.strip.empty?

  items << JSON.parse(line)
end

grouped = rows.group_by do |row|
  [row["sourceCollection"], row["sourceCategory"], row["candidatePrimary"] || "unclassified"]
end

source_groups = rows.group_by { |row| [row["sourceCollection"], row["sourceCategory"]] }
candidate_groups = rows.group_by { |row| row["candidatePrimary"] || "unclassified" }

def markdown_cell(value)
  value.to_s.gsub(/\s+/, " ").gsub("|", "\\|")
end

markdown = []
markdown << "# 分类复核报告"
markdown << ""
markdown << "> 自动生成时间：#{Time.now.utc.iso8601}。本报告只展示待复核题目的聚合视图；确认后的决定写入 `overrides.jsonl`，不要直接修改生成的 `assignments.jsonl`。"
markdown << ""
markdown << "## 总览"
markdown << ""
markdown << "- 待复核题目：**#{rows.length}**"
markdown << "- 来源分类簇：**#{source_groups.length}**"
markdown << "- 候选知识模块：**#{candidate_groups.length}**"
markdown << ""
markdown << "## 来源分类簇"
markdown << ""
markdown << "| 数量 | 来源集合 | 原始分类 | 主要候选模块 | 代表题目 |"
markdown << "| ---: | --- | --- | --- | --- |"

source_groups
  .sort_by { |_key, items| -items.length }
  .each do |(collection, category), items|
    candidate_counts = items.group_by { |row| row["candidatePrimary"] || "unclassified" }
      .sort_by { |_candidate, candidate_rows| -candidate_rows.length }
    candidate_label = candidate_counts.first ? "#{candidate_counts.first[0]}（#{candidate_counts.first[1].length}）" : "unclassified"
    examples = items.first(3).map { |row| "#{row["questionId"]} #{markdown_cell(row["title"])[0, 52]}" }
    markdown << "| #{items.length} | `#{collection}` | #{category} | #{candidate_label} | #{examples.join("；")} |"
  end

markdown << ""
markdown << "## 候选模块分布"
markdown << ""
markdown << "| 数量 | 候选模块 | 来源分类数 | 代表题目 |"
markdown << "| ---: | --- | ---: | --- |"

candidate_groups
  .sort_by { |_candidate, items| -items.length }
  .each do |candidate, items|
    source_count = items.map { |row| [row["sourceCollection"], row["sourceCategory"]] }.uniq.length
    examples = items.first(3).map { |row| "#{row["questionId"]} #{markdown_cell(row["title"])[0, 52]}" }
    markdown << "| #{items.length} | `#{candidate}` | #{source_count} | #{examples.join("；")} |"
  end

markdown << ""
markdown << "## 复核约定"
markdown << ""
markdown << "1. 只有题目主知识点明确且稳定时，才批量写入覆盖映射。"
markdown << "2. 一道题可以保留多个 `secondary` 模块，但 `primary` 只保留一个，便于统计和自适应刷题。"
markdown << "3. 无法从题面判断的题目继续保持 `review`，不能为了降低数字而强行归类。"
markdown << "4. 来源集合和原始分类只用于溯源，不作为网页上的知识模块。"
markdown << ""

File.write(OUTPUT_PATH, markdown.join("\n") + "\n")
puts "wrote #{OUTPUT_PATH} (#{rows.length} review items, #{source_groups.length} source groups)"
