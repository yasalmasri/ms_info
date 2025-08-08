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

# Resolve DB URL without reassigning a constant
_db_url = ENV["DB_URL"]
if _db_url.nil? || _db_url.strip.empty?
  data_dir = File.expand_path("data", __dir__)
  Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
  _db_url = "sqlite://#{File.join(data_dir, "ms_info.db")}"
end

SCHED_TZ = ENV["SCHED_TZ"]
SCHED_DAILY_AT = ENV.fetch("SCHED_DAILY_AT", "00:05")

DB = Sequel.connect(_db_url)

unless DB.table_exists?(:qbittorrent_daily_stats)
  DB.create_table :qbittorrent_daily_stats do
    primary_key :id
    Date :record_date, null: false, unique: true
    Integer :total_uploaded_bytes, null: false, default: 0
    Integer :total_downloaded_bytes, null: false, default: 0
    Float :total_share_ratio, null: false, default: 0.0
    Integer :daily_uploaded_bytes, null: false, default: 0
    Integer :daily_downloaded_bytes, null: false, default: 0
    Float :daily_share_ratio, null: false, default: 0.0
  end
end

DailyStats = DB[:qbittorrent_daily_stats]

class QBTotals
  attr_reader :uploaded_bytes, :downloaded_bytes
  def initialize(uploaded_bytes:, downloaded_bytes:)
    @uploaded_bytes = Integer(uploaded_bytes)
    @downloaded_bytes = Integer(downloaded_bytes)
  end
  def share_ratio
    return 0.0 if @downloaded_bytes <= 0
    @uploaded_bytes.to_f / @downloaded_bytes.to_f
  end
end

class QBittorrentClient
  def initialize(base_url:, username:, password:)
    @base_url = base_url.sub(/\/$/, "")
    @username = username
    @password = password
    @conn = Faraday.new(url: @base_url) do |f|
      f.request :url_encoded
      f.use :cookie_jar
      f.adapter Faraday.default_adapter
    end
    @logged_in = false
  end

  def ensure_login!
    return if @logged_in
    resp = @conn.post("/api/v2/auth/login", { username: @username, password: @password })
    raise "qBittorrent login failed: HTTP #{resp.status}" unless resp.status == 200 && resp.body.to_s.include?("Ok.")
    @logged_in = true
  end

  def fetch_totals
    ensure_login!
    resp = @conn.get("/api/v2/transfer/info")
    puts resp.body
    raise "qBittorrent transfer info failed: HTTP #{resp.status}" unless resp.status == 200
    data = JSON.parse(resp.body)
    up = data.fetch("up_info_data", 0)
    dl = data.fetch("dl_info_data", 0)
    QBTotals.new(uploaded_bytes: up, downloaded_bytes: dl)
  end
end

CLIENT = QBittorrentClient.new(base_url: QB_URL, username: QB_USERNAME, password: QB_PASSWORD)

# Make snapshot logic available both to routes and scheduler
module MsInfo
  module_function

  def compute_and_store_snapshot
    totals = CLIENT.fetch_totals

    today = Date.today
    prev = DailyStats.where { record_date < today }.order(Sequel.desc(:record_date)).first

    daily_uploaded = 0
    daily_downloaded = 0
    if prev
      daily_uploaded = [0, totals.uploaded_bytes - (prev[:total_uploaded_bytes] || 0)].max
      daily_downloaded = [0, totals.downloaded_bytes - (prev[:total_downloaded_bytes] || 0)].max
    end

    total_share_ratio = totals.downloaded_bytes > 0 ? (totals.uploaded_bytes.to_f / totals.downloaded_bytes.to_f) : 0.0
    daily_share_ratio = daily_downloaded > 0 ? (daily_uploaded.to_f / daily_downloaded.to_f) : 0.0

    current_today = DailyStats.where(record_date: today).first
    if current_today
      DailyStats.where(id: current_today[:id]).update(
        total_uploaded_bytes: totals.uploaded_bytes,
        total_downloaded_bytes: totals.downloaded_bytes,
        total_share_ratio: total_share_ratio,
        daily_uploaded_bytes: daily_uploaded,
        daily_downloaded_bytes: daily_downloaded,
        daily_share_ratio: daily_share_ratio
      )
    else
      DailyStats.insert(
        record_date: today,
        total_uploaded_bytes: totals.uploaded_bytes,
        total_downloaded_bytes: totals.downloaded_bytes,
        total_share_ratio: total_share_ratio,
        daily_uploaded_bytes: daily_uploaded,
        daily_downloaded_bytes: daily_downloaded,
        daily_share_ratio: daily_share_ratio
      )
    end
  end

  def human_size(bytes)
    gb = bytes.to_f / (1024.0 ** 3)
    if gb >= 1024.0
      tb = gb / 1024.0
      [tb.round(2), "TB"]
    else
      [gb.round(2), "GB"]
    end
  end
end

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
      MsInfo.compute_and_store_snapshot
    rescue => e
      warn("[scheduler] Warm-up snapshot failed: #{e}")
    end
  end
end

get "/health" do
  json status: "ok"
end

get "/api/sources" do
  json ["qbittorrent"]
end

get "/api/qbittorrent/current" do
  begin
    totals = CLIENT.fetch_totals
  rescue => e
    halt 502, json(error: "Failed to fetch qBittorrent totals: #{e}")
  end
  up_val, up_unit = MsInfo.human_size(totals.uploaded_bytes)
  dl_val, dl_unit = MsInfo.human_size(totals.downloaded_bytes)
  json uploaded: up_val, uploaded_unit: up_unit, downloaded: dl_val, downloaded_unit: dl_unit, share_ratio: totals.share_ratio
end

get "/api/qbittorrent/daily" do
  limit = (params["limit"] || 30).to_i
  rows = DailyStats.order(:record_date).reverse.limit(limit).all
  json rows.reverse
end

post "/api/qbittorrent/snapshot" do
  begin
    MsInfo.compute_and_store_snapshot
  rescue => e
    halt 500, json(error: e.message)
  end
  json status: "ok"
end

Sinatra::Application.run! if __FILE__ == $0 