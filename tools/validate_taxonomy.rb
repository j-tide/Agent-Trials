#!/usr/bin/env ruby

require "json"
require "yaml"

SOURCE_ROOT = ARGV[0] || "questions/collected"
TAXONOMY_ROOT = ARGV[1] || "questions/taxonomy"
CATALOG_PATH = ARGV[2] || "data/catalog.json"
REVIEW_RULES_PATH = File.join(TAXONOMY_ROOT, "review-rules.yml")

def question_files(root)
  Dir.glob(File.join(root, "**", "*.yaml"))
    .reject { |path| File.basename(path) == "manifest.yaml" }
    .sort
end

def jsonl(path)
  File.foreach(path).each_with_object([]) do |line, rows|
    next if line.strip.empty?

    rows << JSON.parse(line)
  end
end

taxonomy = YAML.load_file(File.join(TAXONOMY_ROOT, "taxonomy.yml"))
modules = Array(taxonomy["modules"]).flat_map { |parent| Array(parent["children"]).map { |child| [child["id"], parent["id"]] } }.to_h
source_ids = question_files(SOURCE_ROOT).each_with_object([]) do |path, ids|
  data = YAML.load_file(path)
  id = data["id"].to_s.strip
  ids << id unless id.empty?
end
assignments = jsonl(File.join(TAXONOMY_ROOT, "assignments.jsonl"))
review_queue = jsonl(File.join(TAXONOMY_ROOT, "review-queue.jsonl"))
overrides_path = File.join(TAXONOMY_ROOT, "overrides.jsonl")
overrides = File.file?(overrides_path) ? jsonl(overrides_path) : []
review_rules = if File.file?(REVIEW_RULES_PATH)
  Array(YAML.load_file(REVIEW_RULES_PATH)["rules"])
else
  []
end
catalog = JSON.parse(File.read(CATALOG_PATH))

errors = []
errors << "source question IDs are not unique" unless source_ids.uniq.length == source_ids.length
errors << "assignment question IDs are not unique" unless assignments.map { |row| row.fetch("questionId") }.uniq.length == assignments.length
errors << "assignment count does not match source count" unless assignments.length == source_ids.length
errors << "assignment IDs differ from source IDs" unless assignments.map { |row| row.fetch("questionId") }.sort == source_ids.sort
errors << "override question IDs are not unique" unless overrides.map { |row| row.fetch("questionId") }.uniq.length == overrides.length
errors << "override references a missing source question" unless (overrides.map { |row| row.fetch("questionId") } - source_ids).empty?
errors << "review rule IDs are not unique" unless review_rules.map { |rule| rule.fetch("id") }.uniq.length == review_rules.length

assignments.each do |row|
  primary = row["primary"]
  secondary = Array(row["secondary"])
  errors << "#{row["questionId"]}: unknown primary #{primary}" if primary && !modules.key?(primary)
  secondary.each { |id| errors << "#{row["questionId"]}: unknown secondary #{id}" unless modules.key?(id) }
  errors << "#{row["questionId"]}: invalid status #{row["status"]}" unless %w[auto review reviewed unclassified].include?(row["status"])
  errors << "#{row["questionId"]}: primary missing while classified" if row["status"] != "unclassified" && primary.nil?
end

overrides.each do |row|
  primary = row["primary"]
  secondary = Array(row["secondary"])
  errors << "#{row["questionId"]}: override has unknown primary #{primary}" if primary && !modules.key?(primary)
  secondary.each { |id| errors << "#{row["questionId"]}: override has unknown secondary #{id}" unless modules.key?(id) }
end

review_rules.each do |rule|
  primary = rule.fetch("primary")
  secondary = Array(rule["secondary"])
  errors << "#{rule["id"]}: rule has unknown primary #{primary}" unless modules.key?(primary)
  secondary.each { |id| errors << "#{rule["id"]}: rule has unknown secondary #{id}" unless modules.key?(id) }
  begin
    Regexp.new(rule["title_pattern"].to_s) if rule["title_pattern"]
  rescue RegexpError => error
    errors << "#{rule["id"]}: invalid title pattern #{error.message}"
  end
  begin
    Regexp.new(rule["content_pattern"].to_s) if rule["content_pattern"]
  rescue RegexpError => error
    errors << "#{rule["id"]}: invalid content pattern #{error.message}"
  end
end

review_ids = review_queue.map { |row| row.fetch("questionId") }.sort
expected_review_ids = assignments.select { |row| row["status"] == "review" }.map { |row| row.fetch("questionId") }.sort
errors << "review queue does not match review assignments" unless review_ids == expected_review_ids

catalog_questions = Array(catalog["questions"])
catalog_pack_count = Array(catalog["packs"]).sum { |pack| pack["questionCount"].to_i }
errors << "catalog question count does not match assignments" unless catalog_questions.length == assignments.length
errors << "catalog pack totals do not match question count" unless catalog_pack_count == catalog_questions.length
errors << "catalog has duplicate question IDs" unless catalog_questions.map { |row| row.fetch("id") }.uniq.length == catalog_questions.length
errors << "catalog taxonomy version mismatch" unless catalog.dig("taxonomy", "version") == taxonomy["version"]

if errors.any?
  warn errors.map { |error| "ERROR: #{error}" }
  exit 1
end

status_counts = assignments.group_by { |row| row["status"] }.transform_values(&:length)
puts "taxonomy valid: #{assignments.length} questions, #{modules.length} leaf modules"
puts "status: #{status_counts.sort.map { |key, value| "#{key}=#{value}" }.join(", ")}"
puts "review queue: #{review_queue.length}"
