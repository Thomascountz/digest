#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "rss"
require "net/http"
require "fileutils"
require "date"
require "time"
require "uri"

LAST_RUN_FILE = ".last_run"
CONFIG_FILE = "config.yml"
OUTPUT_DIR = "digests"

def read_last_run
  if File.exist?(LAST_RUN_FILE)
    Time.parse(File.read(LAST_RUN_FILE).strip)
  else
    Time.now - (24 * 60 * 60) # Default 24 hours ago
  end
end

def write_last_run(time)
  File.write(LAST_RUN_FILE, time.iso8601)
end

def read_feeds
  config = YAML.load_file(CONFIG_FILE)
  config["feeds"] || []
end

def fetch_feed(url, redirect_limit = 5)
  raise "Too many redirects" if redirect_limit == 0

  uri = URI.parse(url)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = uri.scheme == "https"
  http.open_timeout = 10
  http.read_timeout = 10

  request = Net::HTTP::Get.new(uri.request_uri)
  request["User-Agent"] = "RubyDigest/1.0"

  response = http.request(request)

  case response
  when Net::HTTPSuccess
    response.body
  when Net::HTTPRedirection
    fetch_feed(response["location"], redirect_limit - 1)
  else
    raise "HTTP #{response.code}: #{response.message}"
  end
end

def parse_feed(content)
  RSS::Parser.parse(content, false)
end

def extract_items(feed, since)
  items = []

  case feed
  when RSS::Atom::Feed
    feed.entries.each do |entry|
      pub_date = entry.updated&.content || entry.published&.content
      next unless pub_date && pub_date > since

      items << {
        title: (entry.title&.content || "Untitled").gsub(/\s+/, " ").strip,
        link: entry.link&.href || entry.links.first&.href,
        date: pub_date
      }
    end
  when RSS::Rss
    feed.items.each do |item|
      pub_date = item.pubDate || item.date
      next unless pub_date && pub_date > since

      items << {
        title: (item.title || "Untitled").gsub(/\s+/, " ").strip,
        link: item.link,
        date: pub_date
      }
    end
  end

  items.sort_by { |i| i[:date] }.reverse
end

def feed_title(feed, url)
  case feed
  when RSS::Atom::Feed
    feed.title&.content || url
  when RSS::Rss
    feed.channel&.title || url
  else
    url
  end
end

def feed_link(feed, url)
  case feed
  when RSS::Atom::Feed
    feed.links.find { |l| l.rel.nil? || l.rel == "alternate" }&.href || url
  when RSS::Rss
    feed.channel&.link || url
  else
    url
  end
end

def generate_digest(feed_results)
  lines = ["# Ruby Digest - #{Date.today}"]
  lines << ""

  feed_results.each do |result|
    next if result[:items].empty?

    lines << "- [#{result[:title]}](#{result[:link]})"
    result[:items].each do |item|
      lines << "  - [#{item[:title]}](#{item[:link]})"
    end
  end

  lines.join("\n") + "\n"
end

def has_new_items?(feed_results)
  feed_results.any? { |r| r[:items].any? }
end

def update_readme_symlink(digest_file)
  readme = "README.md"
  target = File.join(OUTPUT_DIR, File.basename(digest_file))

  FileUtils.rm_f(readme)
  FileUtils.ln_s(target, readme)
end

def main
  since = read_last_run
  puts "Checking for items since: #{since.iso8601}"

  feeds = read_feeds
  puts "Found #{feeds.length} feeds in config"

  feed_results = []

  feeds.each do |url|
    print "Fetching #{url}... "
    begin
      content = fetch_feed(url)
      feed = parse_feed(content)
      items = extract_items(feed, since)
      title = feed_title(feed, url)
      link = feed_link(feed, url)

      feed_results << { title: title, link: link, items: items }
      puts "#{items.length} new items"
    rescue => e
      puts "Error: #{e.message}"
    end
  end

  if has_new_items?(feed_results)
    FileUtils.mkdir_p(OUTPUT_DIR)
    output_file = File.join(OUTPUT_DIR, "#{Date.today}.md")
    digest_content = generate_digest(feed_results)
    File.write(output_file, digest_content)
    puts "Wrote digest to #{output_file}"

    update_readme_symlink(output_file)
    puts "Updated README.md symlink"
  else
    puts "No new items, skipping digest"
  end

  write_last_run(Time.now)
  puts "Updated #{LAST_RUN_FILE}"
end

main if __FILE__ == $0
