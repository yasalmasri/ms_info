class Radarr
  def releases
    releases = []
    puts "Movies: #{movies.count}"
    movies.each do |movie|
      next if movie["digitalRelease"].nil?

      digital_release = Time.iso8601(movie["digitalRelease"]).localtime.to_date
      next unless digital_release == Date.today

      title = movie["title"]
      poster = movie.dig("images", 0, "remoteUrl")

      releases << "\r\n    \\- [#{title}](#{radarr_base_url}/movie/#{movie["tmdbId"]})"
    rescue StandardError => e
      puts e.message
      puts e.backtrace.first 10
    end

    puts "Releases: #{releases.count}"
    if releases.any?
      text = "Today's Releases:" + releases.join
      puts Telegram.send(text).body
    end
  end

  private

  def movies
    @movies ||= begin
                  resp = conn.get("/api/v3/calendar", { apikey: ENV["RADARR_API_KEY"] })
                  JSON.parse(resp.body)
                end
  end

  def conn
    @conn ||= Faraday.new(url: radarr_base_url)
  end

  def radarr_base_url
    ENV["RADARR_URL"]
  end
end
