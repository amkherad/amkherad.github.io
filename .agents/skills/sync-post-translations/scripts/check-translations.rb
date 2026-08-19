#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'set'
require 'date'

ROOT = File.expand_path('../../../..', __dir__)
POSTS_DIR = File.join(ROOT, '_posts')
CONFIG_PATH = File.join(ROOT, '_config.yml')

DRAFT_MARKERS = [
  %r{/wip/},
  %r{/_drafts/}
].freeze

def load_config
  YAML.load_file(CONFIG_PATH)
rescue Errno::ENOENT
  abort("Missing #{CONFIG_PATH}")
end

def published_post_files
  Dir.glob(File.join(POSTS_DIR, '**', '*.{md,markdown}')).select do |path|
    basename = File.basename(path)
    next false if basename.start_with?('.')
    next false if DRAFT_MARKERS.any? { |rx| path.match?(rx) }

    true
  end
end

def parse_front_matter(path)
  content = File.read(path)
  return {} unless content.match?(/\A---\s*\n/)

  fm = content.split('---', 3)[1]
  YAML.safe_load(fm, permitted_classes: [Date, Time], aliases: true) || {}
rescue Psych::SyntaxError => e
  { '__error__' => "Invalid YAML in #{path}: #{e.message}" }
end

config = load_config
languages = config['languages'] || [config['default_lang'] || 'en']
default_lang = config['default_lang'] || 'en'

errors = []
groups = Hash.new { |h, k| h[k] = {} }
files_without_key = []

published_post_files.each do |path|
  rel = path.sub("#{ROOT}/", '')
  fm = parse_front_matter(path)

  if fm['__error__']
    errors << fm['__error__']
    next
  end

  key = fm['translation_key']
  if key.nil? || key.to_s.strip.empty?
    files_without_key << rel
    next
  end

  lang = fm['lang'] || default_lang
  if groups[key].key?(lang)
    errors << "Duplicate translation_key/lang: #{key} (#{lang}) in #{rel} and #{groups[key][lang]}"
  end
  groups[key][lang] = rel

  if lang != default_lang && fm['permalink'].to_s.strip.empty?
    errors << "Missing permalink for non-default language: #{rel} (lang: #{lang})"
  end
end

files_without_key.each do |rel|
  errors << "Missing translation_key: #{rel}"
end

groups.each do |key, by_lang|
  missing = languages - by_lang.keys
  missing.each do |lang|
    errors << "Missing translation: translation_key=#{key} lang=#{lang} (have: #{by_lang.keys.sort.join(', ')})"
  end

  extra = by_lang.keys - languages
  extra.each do |lang|
    errors << "Unexpected lang=#{lang} for translation_key=#{key} (not in _config.yml languages)"
  end
end

if errors.empty?
  puts "OK: #{groups.size} post(s), all languages present (#{languages.join(', ')})"
  exit 0
end

warn "Translation check failed (#{errors.size} issue(s)):"
errors.each { |msg| warn "  - #{msg}" }
exit 1
