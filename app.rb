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

require_relative "./models"
require_relative "./routes"

Sinatra::Application.run! if __FILE__ == $0 
