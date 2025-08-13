# Resolve DB URL without reassigning a constant
_db_url = ENV["DB_URL"]
if _db_url.nil? || _db_url.strip.empty?
  data_dir = File.expand_path("data", __dir__)
  Dir.mkdir(data_dir) unless Dir.exist?(data_dir)
  _db_url = "sqlite://#{File.join(data_dir, "ms_info.db")}"
end

DB = Sequel.connect(_db_url)

unless DB.table_exists?(:qbittorrent_daily_stats)
  DB.create_table :qbittorrent_daily_stats do
    primary_key :id
    Date :date, null: false, unique: true
    Integer :total_uploaded_bytes, null: false, default: 0
    Integer :total_downloaded_bytes, null: false, default: 0
    Float :total_share_ratio, null: false, default: 0.0
  end
end

DailyStats = DB[:qbittorrent_daily_stats]
