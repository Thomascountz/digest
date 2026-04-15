#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "rss"
require "net/http"
require "date"
require "time"
require "uri"
require "optparse"
require "logger"

LAST_RUN_FILE = ".last_run"
CONFIG_FILE = "config.yml"
LOGGER = Logger.new($stdout, level: Logger::INFO)

class FeedFetcher
  Item = Data.define(:title, :link, :date)
  FeedResult = Data.define(:title, :link, :items) do
    def empty? = items.empty?
  end

  def initialize(urls, since)
    @urls = urls
    @since = since
  end

  def fetch_all
    threads = @urls.map { |url| Thread.new { fetch_one(url) } }

    threads.map(&:join).map(&:value).compact
  ensure
    threads.select(&:alive?).each(&:kill)
  end

  private

  def fetch_one(url)
    content = fetch_content(url)
    feed = RSS::Parser.parse(content, false)
    FeedResult.new(
      title: feed_title(feed, url),
      link: feed_link(feed, url),
      items: extract_items(feed)
    )
  rescue => e
    LOGGER.error("Error fetching #{url}: #{e.message}")
    nil
  end

  def fetch_content(url, redirect_limit = 5, retry_limit = 3)
    raise "Too many redirects" if redirect_limit == 0
    raise "Too many retries" if retry_limit == 0

    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 10
    http.max_retries = 3 # Retries network errors (e.g. timeouts)

    request = Net::HTTP::Get.new(uri.request_uri)
    response = http.request(request)

    case response
    when Net::HTTPSuccess
      response.body
    when Net::HTTPRedirection
      LOGGER.info("Redirect #{response.code} for #{url} to #{response['location']}, following...")
      fetch_content(response["location"], redirect_limit - 1, retry_limit)
    when Net::HTTPServerError
      LOGGER.warn("Server error #{response.code} for #{url}, retrying...")
      fetch_content(url, redirect_limit, retry_limit - 1)
    when Net::HTTPClientError
      raise "ClientError #{response.code}: #{response.message}"
    else
      raise "UnknownError #{response.code}: #{response.message}"
    end
  end

  def extract_items(feed)
    items = []

    case feed
    when RSS::Atom::Feed
      feed.entries.each do |entry|
        pub_date = entry.updated&.content || entry.published&.content
        next unless pub_date && pub_date > @since

        items << Item.new(
          title: (entry.title&.content || "Untitled").gsub(/\s+/, " ").strip,
          link: entry.link&.href || entry.links.first&.href,
          date: pub_date
        )
      end
    when RSS::Rss
      feed.items.each do |item|
        pub_date = item.pubDate || item.date
        next unless pub_date && pub_date > @since

        items << Item.new(
          title: (item.title || "Untitled").gsub(/\s+/, " ").strip,
          link: item.link,
          date: pub_date
        )
      end
    end

    items.sort_by(&:date).reverse
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
end

class DigestGenerator
  def initialize(name, config, since)
    @name = name
    @feeds = config.fetch("feeds")
    @config = config
    @since = since
  end

  def generate(dry_run: false)
    LOGGER.info("Processing digest: #{@name} (#{@feeds.length} feeds)")

    feed_results = FeedFetcher.new(@feeds, @since).fetch_all

    if feed_results.all?(&:empty?)
      LOGGER.info("No new items for #{@name}, skipping")
      return
    end

    formats.each do |format|
      content = build_content(feed_results, format)
      filename = "#{@name}.#{format}"

      if dry_run
        puts "\n=== #{filename} ===\n#{content}=== End of #{filename} ==="
      else
        File.write(filename, content)
        LOGGER.info("Wrote digest to #{filename}")
      end
    end
  end

  private

  def formats
    explicit = @config.fetch("format", ["md"])
    mail_config = @config["mail"]
    if mail_config
      mail_fmt = mail_config.fetch("format", "html")
      explicit |= [mail_fmt]
    end
    explicit
  end

  def build_content(feed_results, format)
    case format
    when "md"   then build_content_md(feed_results)
    when "html" then build_content_html(feed_results)
    when "txt"  then build_content_txt(feed_results)
    end
  end

  def build_content_md(feed_results)
    title = @name.capitalize
    lines = ["# #{title} Digest - #{Date.today}"]
    lines << ""

    feed_results.each do |result|
      next if result.items.empty?

      lines << "- [#{result.title}](#{result.link})"
      result.items.each do |item|
        lines << "  - [#{item.title}](#{item.link})"
      end
    end

    lines.join("\n") + "\n"
  end

  def build_content_html(feed_results)
    title = @name.capitalize
    lines = ["<!DOCTYPE html>"]
    lines << "<html><head><meta charset=\"UTF-8\"><title>#{title} Digest</title></head>"
    lines << "<body>"
    lines << "<h1>#{title} Digest - #{Date.today}</h1>"
    lines << "<ul>"

    feed_results.each do |result|
      next if result.items.empty?

      lines << "  <li><a href=\"#{result.link}\">#{escape_html(result.title)}</a>"
      lines << "    <ul>"
      result.items.each do |item|
        lines << "      <li><a href=\"#{item.link}\">#{escape_html(item.title)}</a></li>"
      end
      lines << "    </ul>"
      lines << "  </li>"
    end

    lines << "</ul>"
    lines << "</body>"
    lines << "</html>"
    lines.join("\n") + "\n"
  end

  def build_content_txt(feed_results)
    title = @name.capitalize
    lines = ["#{title} Digest - #{Date.today}"]
    lines << ""

    feed_results.each do |result|
      next if result.items.empty?

      lines << "#{result.title} (#{result.link})"
      result.items.each do |item|
        lines << "  #{item.title} (#{item.link})"
      end
    end

    lines.join("\n") + "\n"
  end

  def escape_html(text)
    text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;")
  end
end

if __FILE__ == $0
  dry_run = false

  since = if File.exist?(LAST_RUN_FILE)
    Time.parse(File.read(LAST_RUN_FILE).strip)
  else
    Time.now - (24 * 60 * 60)
  end
  LOGGER.info("Checking for items since: #{since.iso8601}")

  digests = if File.exist?(CONFIG_FILE)
    YAML.load_file(CONFIG_FILE).fetch("digests", {})
  else
    {}
  end
  LOGGER.info("Found #{digests.length} digest(s) in config")

  OptionParser.new do |opts|
    opts.on("-n", "--dry-run", "Print to stdout instead of writing files") { dry_run = true }
  end.parse!

  digests.each do |name, digest_config|
    DigestGenerator.new(name, digest_config, since).generate(dry_run:)
  end

  if !dry_run
    File.write(LAST_RUN_FILE, Time.now.iso8601)
    LOGGER.info("Updated #{LAST_RUN_FILE}")
  end
end
