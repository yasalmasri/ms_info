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
    MsInfo.compute_and_store_snapshot
  rescue => e
    halt 500, json(error: e.message)
  end
  json status: "ok"
end
