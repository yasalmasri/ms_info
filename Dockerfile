# syntax=docker/dockerfile:1
FROM ruby:3.2-slim AS app

ENV APP_HOME=/app \
    RACK_ENV=production \
    PORT=8010 \
    HOST=0.0.0.0

# Install build tools and SQLite dev headers for the sqlite3 gem
RUN apt-get update -y && apt-get install -y --no-install-recommends \
    build-essential \
    libsqlite3-dev \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR ${APP_HOME}

# Install Ruby gems
COPY Gemfile Gemfile.lock* ./
RUN bundle install

# Copy the application
COPY . .

EXPOSE 8010

CMD ["ruby", "app.rb", "0.0.0.0", "-p", "8010"] 
