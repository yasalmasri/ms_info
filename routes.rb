get "/health" do
  json status: "ok"
end

get "/api/sources" do
  json ["qbittorrent"]
end

get "/api/qbittorrent/alltime" do
  begin
    totals = CLIENT.fetch_alltime
  rescue => e
    halt 502, json(error: "Failed to fetch qBittorrent alltime: #{e}")
  end
  up_val = MsInfo.human_size(totals.uploaded_bytes)
  dl_val = MsInfo.human_size(totals.downloaded_bytes)
  json uploaded: up_val, downloaded: dl_val, share_ratio: totals.share_ratio
end

get "/api/qbittorrent/current" do
  begin
    totals = CLIENT.fetch_totals
  rescue => e
    halt 502, json(error: "Failed to fetch qBittorrent totals: #{e}")
  end
  up_val = MsInfo.human_size(totals.uploaded_bytes)
  dl_val = MsInfo.human_size(totals.downloaded_bytes)
  json uploaded: up_val, downloaded: dl_val, share_ratio: totals.share_ratio
end

get "/api/qbittorrent/daily" do
  totals = MsInfo.daily_stats
  up_val = MsInfo.human_size(totals.uploaded_bytes)
  dl_val = MsInfo.human_size(totals.downloaded_bytes)
  json uploaded: up_val, downloaded: dl_val, share_ratio: totals.share_ratio
end

post "/api/qbittorrent/snapshot" do
  begin
    MsInfo.create_daily_stats
  rescue => e
    halt 500, json(error: e.message)
  end
  json status: "ok"
end

get "/api/radarr/calendar" do
  telegram_chat = ENV["TELEGRAM_CHAT"]

  apikey = ENV["RADARR_API_KEY"]
  radar_base_url = ENV["RADARR_URL"]
  calendar_url = "/api/v3/calendar"

  conn = Faraday.new(url: radar_base_url)
  resp = conn.get(calendar_url, { apikey: })
  data = JSON.parse(resp.body)
  data.each do |movie|
    next if movie["digitalRelease"].nil?

    digital_release = Time.iso8601(movie["digitalRelease"]).localtime.to_date
    next unless digital_release == Date.today

    title = movie["title"]
    poster = movie.dig("images", 0, "remoteUrl")
    puts Telegram.send(text: "#{title}\n#{poster}", chat_id: telegram_chat).body
  rescue StandardError => e
    puts e.message
    puts e.backtrace.first 10
  end

  json status: "ok"
end
