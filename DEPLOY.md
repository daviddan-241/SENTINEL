# Deploy: Render (free) + UptimeRobot

The app is one self-contained HTML file, so it runs with **no server at all** — GitHub Pages already
serves it at `https://daviddan-241.github.io/SENTINEL/`. The backend only adds live prices, cross-device
progress and real-usage trending. This page is the whole deploy, start to finish.

Nothing here needs a key, a secret or a paid plan. There is nothing to put in an environment variable
except the port Render sets for you.

---

## 1. Render

`render.yaml` is a Blueprint, so Render reads the service definition from the repo.

1. Sign in at [dashboard.render.com](https://dashboard.render.com) with GitHub.
2. **New → Blueprint** → pick `daviddan-241/SENTINEL` → **Apply**.
   Render reads `render.yaml` and creates the web service:
   * runtime `python`, **plan `free`**
   * build: regenerates the single-file app from `app/`
   * start: `python3 server.py` (reads Render's `$PORT`, binds `0.0.0.0`)
   * health check: `/api/health`
3. Wait for the first deploy (2–3 minutes). The service URL is on the dashboard —
   `https://wordvault.onrender.com`, or `https://wordvault-xxxx.onrender.com` if that name is taken.

### Confirm it is actually up

```bash
curl -s https://YOUR-APP.onrender.com/api/ping      # {"ok":true,"pong":...,"version":"3.0",...}
curl -s https://YOUR-APP.onrender.com/api/health    # terms, seeds, db:true, market
```

`/api/health` tells you whether the database file exists and whether the price cache is warm.
`/api/ping` does no database, file or cache work at all — it is the cheapest possible "are you
there", and it is what the monitor below should use.

### Point the app at it

Open the deployed app, then **Drawer → About → Backend**, and paste the service URL. The app
remembers it and falls back to its offline library the moment the backend is unreachable — prices
and sync degrade, every word and trainer keeps working.

---

## 2. UptimeRobot

[UptimeRobot](https://uptimerobot.com) free tier: 50 monitors, 5-minute checks, email/Slack/webhook
alerts. One monitor is all this needs.

1. **Add New Monitor**
   * Monitor Type: **Keyword** (or plain **HTTP(s)** if you only care about the status code)
   * Friendly Name: `WordVault API`
   * URL: `https://YOUR-APP.onrender.com/api/ping`
   * Keyword: `pong` — alert when it is **not** found
   * Monitoring Interval: **5 minutes**
   * Alert Contacts: your email
2. Save. The dashboard turns green within a minute.

### Why `/api/ping` and not the app page

A monitor that fetches `index.html` pulls ~510 KB every check and tells you the file is served —
not that the API works. `/api/ping` is a 61-byte JSON answer with `Cache-Control: no-store`, so it
is never a cached lie, and it stays under a millisecond of work. The test suite pins this
(`ping stays cheap (under 25 ms average over 20 calls)`), so the endpoint cannot quietly turn into
something expensive.

### What a 5-minute monitor actually changes on the free plan

Render's free web services **spin down after ~15 minutes of no traffic**, and the next request pays
a 30–60 second cold start. A 5-minute monitor means there is always traffic, so the instance stays
warm and the app never hits that stall. Two honest caveats:

* The free plan gives **750 instance-hours per workspace per month**; one always-on service uses
  about 730, so it fits — but a second always-on free service will not.
* The disk is **ephemeral**. `var/wordvault.db` is recreated on every deploy and restart, so
  aggregate counters and per-device sync rows reset. Saved words and progress live on the device
  first and re-sync on next use, so nothing is lost from your side; it is only the server-side
  copy that starts over. A persistent disk is a paid feature, and nothing here needs it.

---

## 3. Docker (anywhere else)

```bash
docker build -t wordvault . && docker run -p 8000:8000 -v wordvault-data:/data wordvault
```

`WORDVAULT_DB` points at the mounted volume, so the database survives container restarts. Any host
that runs a container works — Fly, Railway, a VPS, or a Raspberry Pi on your desk. `PORT` is read
from the environment, so there is nothing to hard-code.

---

## Coolify / a VPS, if you would rather not use Render

```bash
git clone https://github.com/daviddan-241/SENTINEL && cd SENTINEL
python3 -m venv .venv && . .venv/bin/activate     # optional; there are no dependencies to install
PORT=8000 WORDVAULT_DB=var/wordvault.db python3 server.py
```

Put nginx or Caddy in front for TLS, and point the same UptimeRobot monitor at
`https://your-domain/api/ping`. Standard library only — no `pip install` step exists in this repo,
which is exactly why it deploys anywhere Python runs.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| First request takes ~40 s | Free instance was asleep | Expected; the monitor prevents it. Nothing is broken |
| Health says `"db": false` | Fresh instance, no DB file yet | It is created on the first write; harmless |
| `"market": false` | Price cache not warm yet | It fills on first `/api/prices` call |
| Monitor shows 522/503 | Instance was spun down and the check timed out mid-wake | Set the monitor's timeout to 60 s, or accept one alert at wake-up |
| App shows "offline library" | Backend URL not set, or the service slept | Set it in Drawer → About → Backend |
