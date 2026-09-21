#!/usr/bin/env ruby

require "digest/sha1"
require "json"
require "fileutils"
require "time"
require "yaml"

DEFAULT_COLLECTION_ROOT = "questions/collected"
DEFAULT_TAXONOMY_ROOT = "questions/taxonomy"

input_root = ARGV[0]
output_root = ARGV[1] || "data"
taxonomy_root = ARGV[2] || DEFAULT_TAXONOMY_ROOT

def collection_roots(input_root)
  root = input_root || DEFAULT_COLLECTION_ROOT
  if File.basename(root) == "collected" && Dir.exist?(root)
    Dir.glob(File.join(root, "*"))
      .select { |path| File.directory?(path) }
      .sort
  else
    [root]
  end
end

def blank?(value)
  value.nil? || value.to_s.strip.empty?
end

def clean_string(value)
  value.to_s.strip
end

def compact_hash(value)
  value.is_a?(Hash) ? value : {}
end

def source_collection(root)
  File.basename(root)
end

def source_category(relative_path)
  relative_path.split(File::SEPARATOR).first.to_s
end

def slug_digest(collection, category)
  Digest::SHA1.hexdigest("#{collection}/#{category}")[0, 8]
end

def flatten_taxonomy(modules)
  modules.flat_map do |parent|
    Array(parent["children"]).map do |child|
      child.merge(
        "parentId" => parent["id"],
        "parentLabel" => parent["label"]
      )
    end
  end
end

def load_assignments(path)
  return {} unless File.file?(path)

  File.foreach(path).each_with_object({}) do |line, rows|
    next if line.strip.empty?
    row = JSON.parse(line)
    rows[row.fetch("questionId")] = row
  end
end

def module_payload(module_id, module_by_id)
  return nil if blank?(module_id)

  node = module_by_id[module_id]
  return { "id" => module_id, "label" => module_id } unless node

  {
    "id" => node["id"],
    "label" => node["label"],
    "parentId" => node["parentId"],
    "parentLabel" => node["parentLabel"]
  }
end

roots = collection_roots(input_root)
raise "no collection roots found" if roots.empty?

taxonomy = YAML.load_file(File.join(taxonomy_root, "taxonomy.yml"))
knowledge_modules = flatten_taxonomy(Array(taxonomy["modules"]))
module_by_id = knowledge_modules.to_h { |node| [node["id"], node] }
assignments = load_assignments(File.join(taxonomy_root, "assignments.jsonl"))

groups = Hash.new { |hash, key| hash[key] = [] }
source_rows = []

roots.each do |root|
  collection = source_collection(root)
  manifest_path = File.join(root, "manifest.yaml")
  manifest = File.file?(manifest_path) ? compact_hash(YAML.load_file(manifest_path)) : {}
  source_rows << {
    "id" => collection,
    "label" => clean_string(manifest["title"]).empty? ? collection : clean_string(manifest["title"]),
    "questionCount" => 0,
    "path" => root
  }

  paths = Dir.glob(File.join(root, "**", "*.yaml"))
    .reject { |path| File.basename(path) == "manifest.yaml" }
    .sort

  paths.each do |path|
    data = YAML.load_file(path)
    relative_path = path.delete_prefix("#{root}/")
    category = source_category(relative_path)
    groups[[collection, category]] << [path, relative_path, data]
  end
end

FileUtils.rm_rf(File.join(output_root, "packs"))
FileUtils.mkdir_p(File.join(output_root, "packs"))

pack_rows = []
question_rows = []
attachment_count = 0
status_counts = Hash.new(0)
source_category_counts = Hash.new(0)

groups.sort_by { |(collection, category), _| [collection, category] }.each do |(collection, category), entries|
  pack_id = "pack-#{collection}-#{slug_digest(collection, category)}"
  pack_questions = []

  entries.each do |path, relative_path, data|
    content = compact_hash(data["content"])
    answer = compact_hash(data["answer"])
    source = compact_hash(data["source"])
    question_id = clean_string(data["id"])
    next if question_id.empty?

    assignment = assignments[question_id] || {
      "primary" => nil,
      "secondary" => [],
      "concepts" => [],
      "status" => "unclassified",
      "confidence" => 0.0,
      "taxonomyVersion" => taxonomy["version"]
    }
    primary_module = module_payload(assignment["primary"], module_by_id)
    secondary_modules = Array(assignment["secondary"]).map { |id| module_payload(id, module_by_id) }.compact

    title = clean_string(data["title"])
    legacy_category = clean_string(data["category"])
    difficulty = data["difficulty"].to_i
    difficulty = 2 unless (1..5).include?(difficulty)
    estimated_minutes = data["estimated_minutes"].to_i
    estimated_minutes = 8 if estimated_minutes <= 0
    reference_answer = answer["reference_answer"]
    reference_answer = answer["value"] if blank?(reference_answer)
    reference_answer = clean_string(reference_answer)
    attachment = source["unparsed_attachment"] == true
    attachment_count += 1 if reference_answer.empty? || attachment
    status_counts[assignment["status"]] += 1
    source_category_counts[[collection, category]] += 1

    source_payload = {
      "url" => clean_string(source["url"]),
      "title" => clean_string(source["original_title"] || title),
      "collection" => collection,
      "category" => category,
      "path" => relative_path,
      "unparsedAttachment" => attachment
    }
    taxonomy_payload = {
      "primary" => assignment["primary"],
      "secondary" => Array(assignment["secondary"]),
      "concepts" => Array(assignment["concepts"]),
      "status" => assignment["status"],
      "confidence" => assignment["confidence"].to_f,
      "version" => assignment["taxonomyVersion"] || taxonomy["version"]
    }

    detail = {
      "id" => question_id,
      "title" => title,
      "summary" => clean_string(data["summary"]),
      "type" => clean_string(data["type"]).then { |value| value.empty? ? "short_answer" : value },
      "status" => clean_string(data["status"]),
      "reviewStatus" => clean_string(data["review_status"]),
      # Kept for source compatibility; the UI uses taxonomy.primary instead.
      "rootCategory" => category,
      "category" => legacy_category.empty? ? category : legacy_category,
      "sourceCollection" => collection,
      "sourceCategory" => category,
      "packId" => pack_id,
      "difficulty" => difficulty,
      "estimatedMinutes" => estimated_minutes,
      "tags" => Array(data["tags"]).compact.map(&:to_s),
      "concepts" => Array(data.dig("learning", "concepts")).compact.map(&:to_s),
      "taxonomy" => taxonomy_payload,
      "primaryModule" => primary_module,
      "secondaryModules" => secondary_modules,
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
      "source" => source_payload
    }

    pack_questions << detail
    question_rows << {
      "id" => question_id,
      "title" => title,
      "summary" => clean_string(data["summary"]),
      "type" => detail["type"],
      "rootCategory" => category,
      "category" => detail["category"],
      "sourceCollection" => collection,
      "sourceCategory" => category,
      "taxonomy" => taxonomy_payload,
      "primaryModuleId" => primary_module && primary_module["id"],
      "primaryModuleLabel" => primary_module && primary_module["label"],
      "primaryModuleParentId" => primary_module && primary_module["parentId"],
      "primaryModuleParentLabel" => primary_module && primary_module["parentLabel"],
      "secondaryModuleIds" => Array(assignment["secondary"]),
      "difficulty" => difficulty,
      "estimatedMinutes" => estimated_minutes,
      "tags" => detail["tags"],
      "packId" => pack_id,
      "hasReferenceAnswer" => !reference_answer.empty? && !attachment,
      "sourceUrl" => detail.dig("source", "url")
    }
    source_rows.find { |row| row["id"] == collection }["questionCount"] += 1
  end

  pack_payload = {
    "id" => pack_id,
    "kind" => "source_shard",
    "label" => "#{collection} / #{category}",
    "sourceCollection" => collection,
    "sourceCategory" => category,
    "questionCount" => pack_questions.length,
    "questions" => pack_questions
  }
  pack_filename = "#{pack_id}.json"
  File.write(File.join(output_root, "packs", pack_filename), JSON.pretty_generate(pack_payload, object_nl: "\n") + "\n")
  pack_rows << {
    "id" => pack_id,
    "label" => pack_payload["label"],
    "sourceCollection" => collection,
    "sourceCategory" => category,
    "questionCount" => pack_questions.length,
    "path" => "packs/#{pack_filename}"
  }
end

top_modules = Array(taxonomy["modules"]).map do |parent|
  rows = question_rows.select { |row| row["primaryModuleParentId"] == parent["id"] }
  children = Array(parent["children"]).map do |child|
    child_rows = rows.select { |row| row["primaryModuleId"] == child["id"] }
    {
      "id" => child["id"],
      "label" => child["label"],
      "count" => child_rows.length,
      "reviewCount" => child_rows.count { |row| row.dig("taxonomy", "status") == "review" }
    }
  end
  {
    "id" => parent["id"],
    "label" => parent["label"],
    "description" => parent["description"],
    "count" => rows.length,
    "reviewCount" => rows.count { |row| row.dig("taxonomy", "status") == "review" },
    "children" => children
  }
end

source_category_rows = source_category_counts.map do |(collection, category), count|
  {
    "id" => "#{collection}/#{category}",
    "sourceCollection" => collection,
    "label" => category,
    "count" => count
  }
end.sort_by { |row| [row["sourceCollection"], row["label"]] }

catalog = {
  "schemaVersion" => 2,
  "generatedAt" => Time.now.utc.iso8601,
  "source" => {
    "type" => "github_collected",
    "title" => "Agent Trials 统一题库",
    "collections" => source_rows
  },
  "taxonomy" => {
    "version" => taxonomy["version"],
    "name" => taxonomy["name"]
  },
  "stats" => {
    "questionCount" => question_rows.length,
    "categoryCount" => top_modules.length,
    "domainCount" => top_modules.length,
    "moduleCount" => knowledge_modules.length,
    "leafModuleCount" => knowledge_modules.length,
    "sourceCollectionCount" => source_rows.length,
    "sourceCategoryCount" => source_category_rows.length,
    "attachmentCount" => attachment_count,
    "autoClassifiedCount" => status_counts["auto"],
    "reviewedCount" => status_counts["reviewed"],
    "reviewCount" => status_counts["review"],
    "unclassifiedCount" => status_counts["unclassified"]
  },
  "packs" => pack_rows,
  "categories" => top_modules,
  "knowledgeModules" => knowledge_modules.map { |node| module_payload(node["id"], module_by_id) },
  "sourceCategories" => source_category_rows,
  "questions" => question_rows
}

FileUtils.mkdir_p(output_root)
File.write(File.join(output_root, "catalog.json"), JSON.pretty_generate(catalog, object_nl: "\n") + "\n")
puts "wrote #{question_rows.length} questions across #{top_modules.length} knowledge domains and #{pack_rows.length} source shards to #{output_root}"
