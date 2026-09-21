#!/usr/bin/env ruby

require "json"
require "fileutils"
require "time"
require "yaml"

SOURCE_ROOT = ARGV[0] || "questions/collected/feishu-llm-complete"
OUTPUT_ROOT = ARGV[1] || "data"

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def slugify(index)
  format("pack-%02d", index + 1)
end

def clean_string(value)
  value.to_s.strip
end

def compact_hash(value)
  value.is_a?(Hash) ? value : {}
end

paths = Dir.glob(File.join(SOURCE_ROOT, "**", "*.yaml"))
  .reject { |path| File.basename(path) == "manifest.yaml" }
  .sort

groups = Hash.new { |hash, key| hash[key] = [] }
paths.each do |path|
  data = YAML.load_file(path)
  root_category = path.delete_prefix("#{SOURCE_ROOT}/").split("/").first
  groups[root_category] << [path, data]
end

FileUtils.rm_rf(File.join(OUTPUT_ROOT, "packs"))
FileUtils.mkdir_p(File.join(OUTPUT_ROOT, "packs"))

pack_rows = []
question_rows = []

groups.sort_by { |label, _| label }.each_with_index do |(root_category, entries), index|
  pack_id = slugify(index)
  pack_filename = "#{pack_id}.json"
  pack_questions = []

  entries.each do |path, data|
    content = compact_hash(data["content"])
    answer = compact_hash(data["answer"])
    source = compact_hash(data["source"])
    learning = compact_hash(data["learning"])
    question_id = clean_string(data["id"])
    next if question_id.empty?

    title = clean_string(data["title"])
    category = clean_string(data["category"])
    difficulty = data["difficulty"].to_i
    difficulty = 2 unless (1..5).include?(difficulty)
    estimated_minutes = data["estimated_minutes"].to_i
    estimated_minutes = 8 if estimated_minutes <= 0
    reference_answer = answer["reference_answer"]
    reference_answer = answer["value"] if blank?(reference_answer)
    reference_answer = clean_string(reference_answer)
    attachment = source["unparsed_attachment"] == true

    detail = {
      "id" => question_id,
      "title" => title,
      "summary" => clean_string(data["summary"]),
      "type" => clean_string(data["type"]).then { |value| value.empty? ? "short_answer" : value },
      "status" => clean_string(data["status"]),
      "reviewStatus" => clean_string(data["review_status"]),
      "rootCategory" => root_category,
      "category" => category.empty? ? root_category : category,
      "difficulty" => difficulty,
      "estimatedMinutes" => estimated_minutes,
      "tags" => Array(data["tags"]).compact.map(&:to_s),
      "concepts" => Array(learning["concepts"]).compact.map(&:to_s),
      "prompt" => clean_string(content["prompt"] || title),
      "options" => Array(content["options"]).compact.map do |option|
        option.is_a?(Hash) ? { "id" => option["id"].to_s, "text" => option["text"].to_s } : { "id" => "", "text" => option.to_s }
      end,
      "answer" => {
        "mode" => clean_string(answer["mode"]),
        "value" => answer["value"],
        "referenceAnswer" => reference_answer,
        "keyPoints" => Array(answer["key_points"]).compact.map(&:to_s)
      },
      "feedback" => {
        "correct" => clean_string(compact_hash(data["feedback"])["correct"]),
        "wrong" => clean_string(compact_hash(data["feedback"])["wrong"])
      },
      "hints" => Array(data["hints"]).compact.map(&:to_s),
      "source" => {
        "url" => clean_string(source["url"]),
        "title" => clean_string(source["original_title"] || title),
        "unparsedAttachment" => attachment
      }
    }

    pack_questions << detail
    question_rows << {
      "id" => question_id,
      "title" => title,
      "type" => detail["type"],
      "rootCategory" => detail["rootCategory"],
      "category" => detail["category"],
      "difficulty" => detail["difficulty"],
      "estimatedMinutes" => detail["estimatedMinutes"],
      "packId" => pack_id,
      "hasReferenceAnswer" => !reference_answer.empty? && !attachment,
      "sourceUrl" => detail.dig("source", "url")
    }
  end

  pack_payload = {
    "id" => pack_id,
    "label" => root_category,
    "questionCount" => pack_questions.length,
    "questions" => pack_questions
  }
  File.write(File.join(OUTPUT_ROOT, "packs", pack_filename), JSON.pretty_generate(pack_payload, object_nl: "\n") + "\n")
  pack_rows << {
    "id" => pack_id,
    "label" => root_category,
    "questionCount" => pack_questions.length,
    "path" => "packs/#{pack_filename}"
  }
end

category_rows = question_rows.group_by { |row| row["rootCategory"] }.map do |label, rows|
  {
    "id" => rows.first["packId"],
    "label" => label,
    "count" => rows.length,
    "subcategories" => rows.group_by { |row| row["category"] }.map { |name, subrows| { "label" => name, "count" => subrows.length } }.sort_by { |row| row["label"] }
  }
end.sort_by { |row| row["label"] }

catalog = {
  "schemaVersion" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "source" => {
    "title" => "大模型全面试题-持续更新~",
    "url" => "https://lcnipys9u0xh.feishu.cn/wiki/PFMJwZ2SCiWyPskpSVKcxBeknSb"
  },
  "stats" => {
    "questionCount" => question_rows.length,
    "categoryCount" => category_rows.length,
    "attachmentCount" => question_rows.count { |row| !row["hasReferenceAnswer"] }
  },
  "packs" => pack_rows,
  "categories" => category_rows,
  "questions" => question_rows
}

FileUtils.mkdir_p(OUTPUT_ROOT)
File.write(File.join(OUTPUT_ROOT, "catalog.json"), JSON.pretty_generate(catalog, object_nl: "\n") + "\n")
puts "wrote #{question_rows.length} questions across #{pack_rows.length} packs to #{OUTPUT_ROOT}"
