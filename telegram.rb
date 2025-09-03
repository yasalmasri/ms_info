module Telegram
  def self.send(text:, chat_id:)
    body = { chat_id:, text:, parse_mode: "MarkdownV2" }
    puts body
    conn.post("/#{ENV["TELEGRAM_BOT"]}/sendMessage", body)
  end

  private

  def self.conn
    @conn ||= Faraday.new(url: "https://api.telegram.org")
  end
end
