# frozen_string_literal: true

require "sinatra"
require "sinatra/json"
require "sinatra/reloader" if ENV.fetch("RELOAD", "true").to_s.downcase =~ /^(1|true|yes|on)$/
require "sequel"
require "sqlite3"
require "rufus-scheduler"
require "faraday"
require "faraday-cookie_jar"
require "dotenv"
require "tzinfo"
require "date"
require "json"

Dotenv.load if File.exist?(File.join(__dir__, ".env"))

set :bind, ENV.fetch("HOST", "0.0.0.0")
set :port, ENV.fetch("PORT", "8010").to_i
set :environment, ENV.fetch("RACK_ENV", "development")

QB_URL = ENV.fetch("QB_URL") { raise "QB_URL env var is required" }
QB_USERNAME = ENV.fetch("QB_USERNAME") { raise "QB_USERNAME env var is required" }
QB_PASSWORD = ENV.fetch("QB_PASSWORD") { raise "QB_PASSWORD env var is required" }

SCHED_TZ = ENV["SCHED_TZ"]
SCHED_DAILY_AT = ENV.fetch("SCHED_DAILY_AT", "00:01")

require_relative "./db"
require_relative "./models"
require_relative "./routes"

configure do
  scheduler = Rufus::Scheduler.new
  hour, minute = SCHED_DAILY_AT.split(":", 2).map(&:to_i)
  cron = "#{minute} #{hour} * * *"
  tz = nil
  if SCHED_TZ && !SCHED_TZ.strip.empty? && SCHED_TZ.downcase != "local"
    begin
      tz = SCHED_TZ
    rescue StandardError
      tz = nil
    end
  end
  scheduler.cron(cron, tz: tz) { MsInfo.compute_and_store_snapshot rescue warn($!.message) }

  Thread.new do
    begin
      MsInfo.create_daily_stats
    rescue => e
      warn("[scheduler] Warm-up snapshot failed: #{e}")
    end
  end
end

Sinatra::Application.run! if __FILE__ == $0 
