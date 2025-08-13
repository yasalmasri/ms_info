class QBTotals
  attr_reader :uploaded_bytes, :downloaded_bytes

  def initialize(uploaded_bytes:, downloaded_bytes:, ratio: nil)
    @uploaded_bytes = Integer(uploaded_bytes)
    @downloaded_bytes = Integer(downloaded_bytes)
    @ratio = ratio
  end

  def share_ratio
    @ratio ||= begin
                 return 0.0 if @downloaded_bytes <= 0
                 (@uploaded_bytes.to_f / @downloaded_bytes.to_f).ceil(2)
               end
  end
end

class QBittorrentClient
  def initialize(base_url:, username:, password:)
    @base_url = base_url.sub(/\/$/, "")
    @username = username
    @password = password
  end

  def ensure_login!
    resp = conn.post("/api/v2/auth/login", { username: @username, password: @password })
    raise "qBittorrent login failed: HTTP #{resp.status}" unless resp.status == 200 && resp.body.to_s.include?("Ok.")
  end

  def fetch_totals
    ensure_login!
    resp = conn.get("/api/v2/transfer/info")
    raise "qBittorrent transfer info failed: HTTP #{resp.status}" unless resp.status == 200

    data = JSON.parse(resp.body)
    QBTotals.new(
      uploaded_bytes: data.fetch("up_info_data", 0),
      downloaded_bytes: data.fetch("dl_info_data", 0)
    )
  end

  def fetch_alltime
    ensure_login!
    resp = conn.get("/api/v2/sync/maindata")
    raise "qBittorrent sync maindata failed: HTTP #{resp.status}" unless resp.status == 200

    data = JSON.parse(resp.body)
    QBTotals.new(
      uploaded_bytes: data.dig("server_state", "alltime_ul"),
      downloaded_bytes: data.dig("server_state", "alltime_dl"),
      ratio: data.dig("server_state", "global_ratio")
    )
  end

  private

  def conn
    @conn ||= Faraday.new(url: @base_url) do |f|
      f.request :url_encoded
      f.use :cookie_jar
      f.adapter Faraday.default_adapter
    end
  end
end

# Make snapshot logic available both to routes and scheduler
module MsInfo
  module_function

  def daily_stat
    @daily_stat ||= begin
                      today = Date.today
                      DailyStats.where(date: today).first
                    end
  end

  def daily_stats
    today = Date.today
    totals = CLIENT.fetch_totals

    if daily_stat.nil?
      DailyStats.insert(
        date: today,
        total_uploaded_bytes: totals.uploaded_bytes,
        total_downloaded_bytes: totals.downloaded_bytes,
        total_share_ratio: totals.share_ratio
      )
    end

    today_uploaded = totals.uploaded_bytes - daily_stat[:total_uploaded_bytes]
    today_downloaded = totals.downloaded_bytes - daily_stat[:total_downloaded_bytes]

    QBTotals.new(
      uploaded_bytes: today_uploaded,
      downloaded_bytes: today_downloaded
    )
  end

  def create_daily_stats
    today = Date.today
    DailyStats.insert(date: today)
  end

  def human_size(bytes)
    gb = bytes.to_f / (1024.0 ** 3)
    if gb >= 1024.0
      tb = gb / 1024.0
      [tb.round(2), "TB"].join(" ")
    else
      [gb.round(2), "GB"].join(" ")
    end
  end
end

CLIENT = QBittorrentClient.new(base_url: QB_URL, username: QB_USERNAME, password: QB_PASSWORD)
