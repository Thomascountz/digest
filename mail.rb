#!/usr/bin/env ruby
# frozen_string_literal: true

require "yaml"
require "net/smtp"
require "date"
require "optparse"

CONFIG_FILE = "config.yml"
MAIL_PORT = 587

class Mailer
  def initialize(host:, port:, username:, password:)
    @host = host
    @port = port
    @username = username
    @password = password
  end

  def deliver(to:, subject:, body:)
    smtp = Net::SMTP.new(@host, @port)
    smtp.enable_starttls
    smtp.start("localhost", @username, @password, :login) do |s|
      s.send_message(compose(to:, subject:, body:), @username, to)
    end
  end

  private

  def compose(to:, subject:, body:)
    headers = [
      "From: #{@username}",
      "To: #{to}",
      "Subject: #{subject}",
      "Content-Type: text/plain; charset=UTF-8"
    ]

    headers.join("\n") + "\n\n" + body
  end
end

if __FILE__ == $0
  dry_run = false

  config = if File.exist?(CONFIG_FILE)
    YAML.load_file(CONFIG_FILE)
  else
    {}
  end

  digests = config.fetch("digests", {})

  OptionParser.new do |opts|
    opts.on("-n", "--dry-run", "Print message instead of sending") { dry_run = true }
  end.parse!

  mail_digests = digests.select { |_, digest_config| digest_config["mail"] }

  if mail_digests.empty?
    puts "No digests configured for mail"
    exit
  end

  if !dry_run
    smtp_config = config.fetch("mail")
    host     = ENV.fetch(smtp_config.fetch("host"))
    username = ENV.fetch(smtp_config.fetch("username"))
    password = ENV.fetch(smtp_config.fetch("password"))
    mailer = Mailer.new(host:, port: MAIL_PORT, username:, password:)
  end

  mail_digests.each do |name, digest_config|
    file = "#{name}.md"
    unless File.exist?(file)
      puts "#{file} not found, skipping"
      next
    end

    body = File.read(file)
    subject = "#{name.capitalize} Digest - #{Date.today}"
    mail_config = digest_config.fetch("mail")

    mail_config.fetch("to").each do |env_name|
      recipient = dry_run ? ENV.fetch(env_name, env_name) : ENV.fetch(env_name)

      if dry_run
        puts "To: #{recipient}"
        puts "Subject: #{subject}"
        puts "---"
        puts body
        puts
      else
        begin
          mailer.deliver(to: recipient, subject:, body:)
          puts "Sent #{file} to #{recipient}"
        rescue => e
          puts "Error sending #{file} to #{recipient}: #{e.message}"
        end
      end
    end
  end
end
