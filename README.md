# ms_info API

A small service to aggregate and expose metrics from apps like qBittorrent.

## Python (original)

The original FastAPI implementation remains in `app/` but is now deprecated in favor of the Ruby/Sinatra version below.

## Ruby/Sinatra (current)

1. Install Ruby (3.1+ recommended), then install bundler:

```bash
gem install bundler
```

2. Install gems:

```bash
bundle install
```

3. Create a `.env` file at repo root:

```
QB_URL=http://192.168.68.251:5018/
QB_USERNAME=your_username
QB_PASSWORD=your_password
# Optional
DB_URL=sqlite:////absolute/path/to/ms_info/data/ms_info.db
SCHED_TZ=local
SCHED_DAILY_AT=00:05
HOST=0.0.0.0
PORT=8010
RELOAD=true
```

4. Run the app:

```bash
bundle exec rackup -o ${HOST:-0.0.0.0} -p ${PORT:-8010}
# or (without rackup/config.ru)
HOST=0.0.0.0 PORT=8010 ruby app.rb
```

### Endpoints

- `GET /health`: Service health
- `GET /api/qbittorrent/current`: Live totals from qBittorrent (upload, download, share ratio)
- `GET /api/qbittorrent/daily`: Daily deltas stored in DB
- `POST /api/qbittorrent/snapshot`: Trigger an immediate snapshot

### Notes

- Credentials are read from env vars.
- DB defaults to `data/ms_info.db` if `DB_URL` not provided.
- Scheduler runs at `SCHED_DAILY_AT` with optional `SCHED_TZ`. 