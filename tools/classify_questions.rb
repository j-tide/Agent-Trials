#!/usr/bin/env ruby

require "json"
require "fileutils"
require "time"
require "yaml"

SOURCE_ROOT = ARGV[0] || "questions/collected"
OUTPUT_ROOT = ARGV[1] || "questions/taxonomy"
TAXONOMY_PATH = ARGV[2] || File.join(OUTPUT_ROOT, "taxonomy.yml")
REVIEW_RULES_PATH = ARGV[3] || File.join(OUTPUT_ROOT, "review-rules.yml")

def normalize(value)
  value.to_s
    .unicode_normalize(:nfkc)
    .downcase
    .gsub(/[\s\u3000]+/, "")
end

def flatten_modules(modules)
  modules.flat_map do |parent|
    children = Array(parent["children"])
    children.map do |child|
      child.merge(
        "parent_id" => parent["id"],
        "parent_label" => parent["label"],
        "parent_description" => parent["description"]
      )
    end
  end
end

def source_collection(relative_path)
  relative_path.split(File::SEPARATOR).first
end

def source_category(relative_path)
  relative_path.split(File::SEPARATOR)[1].to_s
end

def question_files(root)
  Dir.glob(File.join(root, "**", "*.yaml"))
    .reject { |path| File.basename(path) == "manifest.yaml" }
    .sort
end

def question_text(data, relative_path)
  content = data["content"].is_a?(Hash) ? data["content"] : {}
  learning = data["learning"].is_a?(Hash) ? data["learning"] : {}
  source = data["source"].is_a?(Hash) ? data["source"] : {}
  parts = relative_path.split(File::SEPARATOR)
  source_root = parts.first
  tags = Array(data["tags"]).reject { |tag| normalize(tag) == normalize(source_root) }
  concepts = Array(learning["concepts"]).reject { |concept| normalize(concept) == normalize(source_root) }
  values = [
    data["title"], data["summary"], data["derived_topic"], content["prompt"],
    source["original_title"], *tags, *concepts
  ]
  normalize(values.compact.join(" "))
end

def source_context(data, relative_path)
  learning = data["learning"].is_a?(Hash) ? data["learning"] : {}
  parts = relative_path.split(File::SEPARATOR)
  source_root = parts.first
  values = [
    data["category"], data["derived_topic"], *parts.drop(1),
    *Array(data["tags"]).reject { |tag| normalize(tag) == normalize(source_root) },
    *Array(learning["concepts"]).reject { |concept| normalize(concept) == normalize(source_root) }
  ]
  normalize(values.compact.join(" "))
end

def term_match_count(text, term)
  return 0 if term.empty? || !text.include?(term)

  count = 0
  offset = 0
  while count < 3
    index = text.index(term, offset)
    break unless index

    count += 1
    offset = index + term.length
  end
  count
end

def keyword_score(text, term)
  return 0 if term.empty?

  # Longer phrases carry more information than generic one- or two-character terms.
  base = term.length >= 8 ? 4 : term.length >= 4 ? 3 : 2
  occurrences = term_match_count(text, term)
  base * occurrences
end

def source_hint_score(text, term)
  return 0 if term.empty? || !text.include?(term)

  [term.length >= 8 ? 4 : 2, 6].min
end

def matched_keywords(text, keywords)
  keywords.each_with_object([]) do |keyword, matches|
    matches << keyword["label"] unless keyword["term"].empty? || text.index(keyword["term"]).nil?
  end.uniq
end

def load_assignments(path)
  return {} unless File.file?(path)

  File.foreach(path).each_with_object({}) do |line, rows|
    next if line.strip.empty?

    row = JSON.parse(line)
    rows[row.fetch("questionId")] = row
  end
end

def load_review_rules(path)
  return [] unless File.file?(path)

  config = YAML.load_file(path)
  Array(config["rules"]).map do |rule|
    compiled = rule.dup
    compiled["title_regexp"] = Regexp.new(rule["title_pattern"].to_s) if rule["title_pattern"]
    compiled["content_regexp"] = Regexp.new(rule["content_pattern"].to_s) if rule["content_pattern"]
    compiled
  end
end

def review_rule_text(data, relative_path)
  content = data["content"].is_a?(Hash) ? data["content"] : {}
  answer = data["answer"].is_a?(Hash) ? data["answer"] : {}
  learning = data["learning"].is_a?(Hash) ? data["learning"] : {}
  source = data["source"].is_a?(Hash) ? data["source"] : {}
  values = [
    data["title"], data["summary"], data["derived_topic"], content["prompt"],
    answer["reference_answer"], answer["value"], *Array(answer["key_points"]),
    source["original_title"], *Array(data["tags"]), *Array(learning["concepts"]), relative_path
  ]
  values.compact.join(" ")
end

def review_rule_matches?(rule, data, relative_path)
  return false if rule["source_collection"] && rule["source_collection"] != source_collection(relative_path)
  return false if rule["source_category"] && rule["source_category"] != source_category(relative_path)
  return false if rule["path_contains"] && !relative_path.include?(rule["path_contains"])
  return false if rule["title_regexp"] && !rule["title_regexp"].match?(data["title"].to_s)
  return false if rule["content_regexp"] && !rule["content_regexp"].match?(review_rule_text(data, relative_path))

  true
end

taxonomy = YAML.load_file(TAXONOMY_PATH)
leaves = flatten_modules(Array(taxonomy["modules"])).map do |leaf|
  leaf.merge(
    "compiled_keywords" => Array(leaf["keywords"]).map { |keyword| { "label" => keyword, "term" => normalize(keyword) } },
    "compiled_source_hints" => Array(leaf["source_hints"]).map { |hint| normalize(hint) }
  )
end
leaf_by_id = leaves.to_h { |leaf| [leaf["id"], leaf] }
overrides = load_assignments(File.join(OUTPUT_ROOT, "overrides.jsonl"))
review_rules = load_review_rules(REVIEW_RULES_PATH)
raise "taxonomy has no leaf modules" if leaves.empty?

files = question_files(SOURCE_ROOT)
raise "no question files found under #{SOURCE_ROOT}" if files.empty?

assignments = []
review_queue = []
module_counts = Hash.new(0)
status_counts = Hash.new(0)
source_counts = Hash.new(0)
rule_counts = Hash.new(0)

files.each do |path|
  data = YAML.load_file(path)
  relative_path = path.delete_prefix("#{SOURCE_ROOT}/")
  id = data["id"].to_s.strip
  next if id.empty?

  text = question_text(data, relative_path)
  source_text = source_context(data, relative_path)
  scores = leaves.map do |leaf|
    keywords = leaf["compiled_keywords"]
    hints = leaf["compiled_source_hints"]
    keyword_matches = matched_keywords(text, keywords)
    score = keywords.sum { |keyword| keyword_score(text, keyword["term"]) }
    score += hints.sum { |hint| source_hint_score(source_text, hint) }
    {
      "leaf" => leaf,
      "score" => score,
      "matchedKeywords" => keyword_matches
    }
  end.sort_by { |row| [-row["score"], row["leaf"]["id"]] }

  top = scores[0]
  second = scores[1]
  top_score = top["score"]
  second_score = second["score"]
  score_gap = top_score - second_score
  status = if top_score >= 8 && score_gap >= 3
             "auto"
           elsif top_score.positive?
             "review"
           else
             "unclassified"
           end

  primary = top_score.positive? ? top["leaf"]["id"] : nil
  secondary = scores.drop(1).select do |row|
    row["score"] >= 3 && row["score"] >= (top_score * 0.35)
  end.first(3).map { |row| row["leaf"]["id"] }

  assignment = {
    "questionId" => id,
    "primary" => primary,
    "secondary" => secondary,
    "concepts" => [],
    "status" => status,
    "confidence" => if top_score.zero?
                      0.0
                    else
                      [(top_score.to_f / [top_score + second_score, 1].max), 0.99].min.round(3)
                    end,
    "matchedKeywords" => top["matchedKeywords"],
    "taxonomyVersion" => taxonomy["version"],
    "sourceCollection" => source_collection(relative_path),
    "sourceCategory" => source_category(relative_path)
  }
  matched_rule = review_rules.find { |rule| review_rule_matches?(rule, data, relative_path) }
  if matched_rule
    assignment.merge!(
      "primary" => matched_rule.fetch("primary"),
      "secondary" => Array(matched_rule["secondary"]),
      "status" => "reviewed",
      "confidence" => 1.0,
      "ruleId" => matched_rule.fetch("id")
    )
    rule_counts[matched_rule["id"]] += 1
  end
  if overrides[id]
    assignment.merge!(overrides[id])
    assignment["questionId"] = id
    assignment["status"] = overrides[id]["status"] || "reviewed"
    assignment["confidence"] = overrides[id].key?("confidence") ? overrides[id]["confidence"].to_f : 1.0
    assignment["taxonomyVersion"] = taxonomy["version"]
  end
  assignments << assignment
  assigned_primary = assignment["primary"]
  assigned_secondary = Array(assignment["secondary"])
  module_counts[assigned_primary || "unclassified"] += 1
  status_counts[assignment["status"]] += 1
  source_counts[assignment["sourceCollection"]] += 1

  next if ["auto", "reviewed"].include?(assignment["status"])

  review_queue << {
    "questionId" => id,
    "title" => data["title"].to_s,
    "sourceCollection" => assignment["sourceCollection"],
    "sourceCategory" => assignment["sourceCategory"],
    "candidatePrimary" => assigned_primary,
    "candidateSecondary" => assigned_secondary,
    "confidence" => assignment["confidence"],
    "matchedKeywords" => assignment["matchedKeywords"]
  }
end

FileUtils.mkdir_p(OUTPUT_ROOT)
assignments_path = File.join(OUTPUT_ROOT, "assignments.jsonl")
File.write(assignments_path, assignments.map { |row| JSON.generate(row) }.join("\n") + "\n")
File.write(File.join(OUTPUT_ROOT, "review-queue.jsonl"), review_queue.map { |row| JSON.generate(row) }.join("\n") + "\n")

report = {
  "schemaVersion" => 1,
  "generatedAt" => Time.now.utc.iso8601,
  "taxonomyVersion" => taxonomy["version"],
  "sourceRoot" => SOURCE_ROOT,
  "questionCount" => assignments.length,
  "statusCounts" => status_counts,
  "moduleCounts" => module_counts.sort.to_h,
  "sourceCounts" => source_counts.sort.to_h,
  "overrideCount" => overrides.length,
  "reviewRuleCount" => review_rules.length,
  "reviewRuleAssignments" => rule_counts.sort.to_h,
  "reviewQueueCount" => review_queue.length,
  "unclassifiedCount" => module_counts["unclassified"]
}
File.write(File.join(OUTPUT_ROOT, "classification-report.json"), JSON.pretty_generate(report) + "\n")

puts "classified #{assignments.length} questions"
puts "status: #{status_counts.sort_by { |key, _| key }.map { |key, value| "#{key}=#{value}" }.join(", ")}"
puts "review queue: #{review_queue.length}"
puts "unclassified: #{module_counts["unclassified"]}"
