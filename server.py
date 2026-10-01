#!/usr/bin/env python3
"""
WordVault backend — zero-dependency Python server.

Serves the app and a real JSON API:
  * full-text search over the dictionary (SQLite FTS5, ranked)
  * server-side BIP-39 checksum validation and phrase generation
  * per-device progress sync (SQLite)
  * live market data (CoinGecko, Kraken fallback) with caching
  * aggregate usage stats, events, export

Run:  python3 server.py [port]
"""
import gzip, hashlib, json, os, re, sqlite3, sys, threading, time, urllib.parse, urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "app"))     # build.py + data/ live in app/

import build  # single source of truth for terms, seeds and static payloads
from data import quotes as Q

VERSION = "3.0"
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else int(os.environ.get("PORT") or 8000)
DB_PATH = Path(os.environ.get("WORDVAULT_DB") or (ROOT / "var" / "wordvault.db"))
DB_PATH.parent.mkdir(parents=True, exist_ok=True)
START = time.time()

# ---------------------------------------------------------------- data loading
TERMS, _DUPES = build.load_terms()
BIP39 = build.load_bip39()
CATS = []
for t in TERMS:
    if t["c"] not in CATS:
        CATS.append(t["c"])
BY_NAME = {t["n"].lower(): t for t in TERMS}
SEED_INDEX = {w: i for i, w in enumerate(BIP39)}

# ---------------------------------------------------------------- database
DB_LOCK = threading.Lock()
db = sqlite3.connect(DB_PATH, check_same_thread=False)
db.execute("PRAGMA journal_mode=WAL")


def db_init():
    with DB_LOCK:
        db.executescript("""
        CREATE TABLE IF NOT EXISTS progress(
            uid TEXT PRIMARY KEY, blob TEXT NOT NULL,
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS events(
            id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL,
            uid TEXT, ts INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS counters(k TEXT PRIMARY KEY, v INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS word_hits(name TEXT PRIMARY KEY, hits INTEGER NOT NULL, last INTEGER NOT NULL);
        CREATE VIRTUAL TABLE IF NOT EXISTS terms_fts
            USING fts5(name, body, cat UNINDEXED, level UNINDEXED, tokenize='porter unicode61');
        """)
        cur = db.execute("SELECT COUNT(*) FROM terms_fts").fetchone()[0]
        if cur != len(TERMS):
            db.execute("DELETE FROM terms_fts")
            db.executemany("INSERT INTO terms_fts(name, body, cat, level) VALUES (?,?,?,?)",
                           [(t["n"], t["n"] + " — " + t["d"], t["c"], t["l"]) for t in TERMS])
        for k in ("words_read", "phrases_made", "checks", "api_calls"):
            db.execute("INSERT OR IGNORE INTO counters(k,v) VALUES(?,0)", (k,))
        db.commit()


def bump(k, n=1, uid=None):
    with DB_LOCK:
        db.execute("INSERT INTO counters(k,v) VALUES(?,?) ON CONFLICT(k) DO UPDATE SET v=v+?", (k, n, n))
        if uid and k in ("words_read", "phrases_made", "checks"):
            db.execute("INSERT INTO events(kind,uid,ts) VALUES(?,?,?)", (k, uid, int(time.time())))
        db.commit()


def hit_word(name, uid=None):
    if not name:
        return
    with DB_LOCK:
        db.execute("""INSERT INTO word_hits(name,hits,last) VALUES(?,1,?)
                      ON CONFLICT(name) DO UPDATE SET hits=hits+1, last=?""", (name[:80], int(time.time()), int(time.time())))
        db.execute("INSERT INTO events(kind,uid,ts) VALUES(?,?,?)", ("word_read", (uid or "")[:64] or None, int(time.time())))
        db.execute("UPDATE counters SET v=v+1 WHERE k='words_read'")
        db.commit()


def trending(limit=10):
    with DB_LOCK:
        rows = db.execute("SELECT name,hits FROM word_hits ORDER BY hits DESC, last DESC LIMIT ?", (limit,)).fetchall()
    out = []
    for name, hits in rows:
        t = BY_NAME.get(name.lower())
        if t:
            out.append({"n": t["n"], "c": t["c"], "l": t["l"], "hits": hits})
    return out


def counters():
    with DB_LOCK:
        return {k: v for k, v in db.execute("SELECT k,v FROM counters")}


# ---------------------------------------------------------------- BIP-39 (server side)
K = [0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
     0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
     0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
     0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
     0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
     0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
     0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
     0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]


def _rotr(x, n):
    return ((x >> n) | (x << (32 - n))) & 0xFFFFFFFF


def sha256(data: bytes) -> bytes:
    H = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
    bitlen = len(data) * 8
    b = data + b"\x80" + b"\x00" * ((55 - len(data)) % 64) + bitlen.to_bytes(8, "big")
    for off in range(0, len(b), 64):
        w = list(int.from_bytes(b[off + i * 4:off + i * 4 + 4], "big") for i in range(16))
        for i in range(16, 64):
            s0 = _rotr(w[i-15],7) ^ _rotr(w[i-15],18) ^ (w[i-15] >> 3)
            s1 = _rotr(w[i-2],17) ^ _rotr(w[i-2],19) ^ (w[i-2] >> 10)
            w.append((w[i-16] + s0 + w[i-7] + s1) & 0xFFFFFFFF)
        a,bb,c,d,e,f,g,h = H
        for i in range(64):
            S1 = _rotr(e,6) ^ _rotr(e,11) ^ _rotr(e,25)
            ch = (e & f) ^ (~e & g)
            t1 = (h + S1 + ch + K[i] + w[i]) & 0xFFFFFFFF
            S0 = _rotr(a,2) ^ _rotr(a,13) ^ _rotr(a,22)
            maj = (a & bb) ^ (a & c) ^ (bb & c)
            t2 = (S0 + maj) & 0xFFFFFFFF
            h,g,f,e,d,c,bb,a = g,f,e,(d + t1) & 0xFFFFFFFF,c,bb,a,(t1 + t2) & 0xFFFFFFFF
        H = [(x + y) & 0xFFFFFFFF for x, y in zip(H, [a,bb,c,d,e,f,g,h])]
    return b"".join(x.to_bytes(4, "big") for x in H)


def validate_phrase(text):
    words = [w for w in re.split(r"[\s,;]+", (text or "").strip().lower()) if w]
    if not words:
        return {"ok": False, "state": "empty", "msg": "Type or paste a phrase to check."}
    if len(words) not in (12, 15, 18, 21, 24):
        return {"ok": False, "state": "bad",
                "msg": f"A BIP-39 phrase has 12/15/18/21/24 words — you gave {len(words)}."}
    unknown = [w for w in words if w not in SEED_INDEX]
    if unknown:
        return {"ok": False, "state": "bad", "unknown": unknown,
                "msg": "Not in the 2,048-word list: " + ", ".join(unknown[:5]) +
                       (" and %d more" % (len(unknown) - 5) if len(unknown) > 5 else "")}
    bits = "".join(format(SEED_INDEX[w], "011b") for w in words)
    cs_len = len(words) // 3
    ent, cs = bits[:-cs_len], bits[-cs_len:]
    digest = sha256(int(ent, 2).to_bytes(len(ent) // 8, "big"))
    calc = "".join(format(byte, "08b") for byte in digest)[:cs_len]
    if calc == cs:
        return {"ok": True, "state": "good", "words": words,
                "msg": "Valid BIP-39 phrase — every word is in the list and the checksum matches."}
    return {"ok": False, "state": "sum", "words": words,
            "msg": "All words are in the list, but the checksum fails — usually two words swapped "
                   "or one written down incorrectly."}


def generate_phrase(n=12):
    n = 24 if int(n) == 24 else 12
    import secrets
    pool = secrets.SystemRandom().sample(BIP39, n - 1)
    bits = "".join(format(SEED_INDEX[w], "011b") for w in pool)
    cs_len, ent_len = n // 3, 11 * n - n // 3
    for c in range(2048):
        full = bits + format(c, "011b")
        ent, cs = full[:ent_len], full[ent_len:]
        if "".join(format(x, "08b") for x in sha256(int(ent, 2).to_bytes(ent_len // 8, "big")))[:cs_len] == cs:
            return pool + [BIP39[c]]
    return pool


# ---------------------------------------------------------------- market data
PRICE_CACHE = {"ts": 0, "data": None}
GLOBAL_CACHE = {"ts": 0, "data": {}, "fng": None}
PRICE_LOCK = threading.Lock()
COINS = [("bitcoin","BTC","Bitcoin"),("ethereum","ETH","Ethereum"),("solana","SOL","Solana"),
         ("binancecoin","BNB","BNB"),("ripple","XRP","XRP"),("cardano","ADA","Cardano"),
         ("dogecoin","DOGE","Dogecoin"),("tron","TRX","Tron"),("chainlink","LINK","Chainlink"),
         ("avalanche-2","AVAX","Avalanche"),("polkadot","DOT","Polkadot"),("litecoin","LTC","Litecoin")]
IDS = ",".join(c[0] for c in COINS)


def _get(url, timeout=12):
    req = urllib.request.Request(url, headers={"User-Agent": "WordVault/2.0 (+educational)",
                                               "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def fetch_prices():
    """CoinGecko first, Kraken as fallback. Always returns something usable."""
    out = {"source": "coingecko", "coins": [], "global": {}, "fearGreed": None, "ts": int(time.time())}
    try:
        mk = _get("https://api.coingecko.com/api/v3/coins/markets"
                  f"?vs_currency=usd&ids={IDS}&price_change_percentage=24h&sparkline=true")
        for c in mk:
            out["coins"].append({
                "id": c["id"], "sym": c["symbol"].upper(), "name": c["name"],
                "price": c["current_price"], "chg": round(c.get("price_change_percentage_24h") or 0, 2),
                "cap": c.get("market_cap"), "vol": c.get("total_volume"),
                "spark": [round(p, 6) for p in (c.get("sparkline_in_7d", {}) or {}).get("price", [])][::8][:40],
            })
    except Exception as e:
        out["source"] = "kraken"
        try:
            pairs = {"BTC":"XBTUSD","ETH":"ETHUSD","SOL":"SOLUSD","XRP":"XRPUSD","ADA":"ADAUSD",
                     "DOGE":"XDGUSD","LINK":"LINKUSD","LTC":"LTCUSD","DOT":"DOTUSD","AVAX":"AVAXUSD"}
            t = _get("https://api.kraken.com/0/public/Ticker?pair=" + ",".join(pairs.values()))["result"]
            rev = {v: k for k, v in pairs.items()}
            for key, v in t.items():
                sym = rev.get(key) or next((s for s in rev if key.startswith(s[:3])), key)
                out["coins"].append({"id": sym.lower(), "sym": sym, "name": sym,
                                     "price": float(v["c"][0]), "chg": None, "spark": [], "cap": None, "vol": None})
        except Exception as e2:
            out["error"] = f"coingecko: {e}; kraken: {e2}"
    # global stats + sentiment change slowly and are rate-limited upstream: refresh every 5 min,
    # fall back to the last good values (or a retry) rather than showing blanks
    fresh = time.time() - GLOBAL_CACHE["ts"] > 300
    if fresh:
        for attempt in (1, 2):
            try:
                g = _get("https://api.coingecko.com/api/v3/global")["data"]
                GLOBAL_CACHE["data"] = {"mcap": g["total_market_cap"]["usd"],
                                        "vol": g["total_volume"]["usd"],
                                        "btcDom": round(g["market_cap_percentage"]["btc"], 1),
                                        "ethDom": round(g["market_cap_percentage"]["eth"], 1),
                                        "coins": g["active_cryptocurrencies"]}
                break
            except Exception:
                if attempt == 1:
                    time.sleep(1.5)
        try:
            fg = _get("https://api.alternative.me/fng/?limit=1")["data"][0]
            GLOBAL_CACHE["fng"] = {"value": int(fg["value"]), "label": fg["value_classification"]}
        except Exception:
            pass
        if GLOBAL_CACHE["data"]:
            GLOBAL_CACHE["ts"] = time.time()
    out["global"] = GLOBAL_CACHE["data"]
    out["fearGreed"] = GLOBAL_CACHE["fng"]
    return out


def prices(max_age=60):
    with PRICE_LOCK:
        if PRICE_CACHE["data"] and time.time() - PRICE_CACHE["ts"] < max_age:
            return PRICE_CACHE["data"]
    try:
        d = fetch_prices()
        if d.get("coins"):
            with PRICE_LOCK:
                PRICE_CACHE.update(ts=time.time(), data=d)
            return d
    except Exception as e:
        pass
    with PRICE_LOCK:
        return PRICE_CACHE["data"] or {"coins": [], "error": "market data unavailable", "ts": int(time.time())}


def warm_prices():
    time.sleep(2)
    while True:
        try:
            prices(max_age=0)
        except Exception:
            pass
        time.sleep(75)


# ---------------------------------------------------------------- static payload
def payload():
    return {
        "terms": TERMS, "seeds": [{"i": i, "w": w, "t": BY_NAME.get(w.lower(), {}).get("n")} for i, w in enumerate(BIP39)],
        "cats": CATS, "levels": build.LEVELS, "quotes": Q.QUOTES, "rules": Q.RULES,
        "stats": {"terms": len(TERMS), "seeds": len(BIP39),
                  "seedDefs": sum(1 for w in BIP39 if w.lower() in BY_NAME)},
    }


# ---------------------------------------------------------------- http
MIME = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
        ".css": "text/css; charset=utf-8", ".png": "image/png", ".json": "application/json",
        ".md": "text/plain; charset=utf-8", ".svg": "image/svg+xml", ".ico": "image/x-icon",
        ".webmanifest": "application/manifest+json", ".txt": "text/plain; charset=utf-8",
        ".map": "application/json", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
        ".webp": "image/webp", ".woff2": "font/woff2"}


class Handler(BaseHTTPRequestHandler):
    server_version = "WordVault/" + VERSION
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):
        sys.stderr.write("%s  %s\n" % (time.strftime("%H:%M:%S"), fmt % a))

    # ---- helpers
    def send_json(self, obj, code=200, cache=0):
        body = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode()
        gz = b""
        if "gzip" in (self.headers.get("Accept-Encoding") or ""):
            gz = gzip.compress(body, 6)
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "public, max-age=%d" % cache if cache else "no-store")
        if gz:
            self.send_header("Content-Encoding", "gzip")
            body = gz
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path: Path):
        if not path.exists() or not path.is_file():
            return self.send_error(404, "not found")
        data = path.read_bytes()
        body = gzip.compress(data, 6) if "gzip" in (self.headers.get("Accept-Encoding") or "") and len(data) > 1024 else data
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(path.suffix, "application/octet-stream"))
        self.send_header("Cache-Control", "no-cache")
        if body is not data:
            self.send_header("Content-Encoding", "gzip")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def body_json(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return {}

    # ---- routes
    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "content-type")
        self.send_header("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p, q = u.path, urllib.parse.parse_qs(u.query)
        try:
            return self.route(p, q, "GET")
        except Exception as e:
            return self.send_json({"error": str(e), "path": p}, 500)

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        try:
            return self.route(u.path, urllib.parse.parse_qs(u.query), "POST")
        except Exception as e:
            return self.send_json({"error": str(e)}, 500)

    def do_DELETE(self):
        u = urllib.parse.urlparse(self.path)
        try:
            return self.route(u.path, urllib.parse.parse_qs(u.query), "DELETE")
        except Exception as e:
            return self.send_json({"error": str(e)}, 500)

    def route(self, p, q, method):
        bump("api_calls")
        # ---- health / meta
        if p == "/api/health":
            return self.send_json({"ok": True, "version": VERSION, "terms": len(TERMS), "seeds": len(BIP39),
                                   "categories": len(CATS), "uptime_s": round(time.time() - START),
                                   "db": DB_PATH.exists(), "market": bool(PRICE_CACHE["data"]),
                                   "time": int(time.time())})

        if p == "/api/meta":
            return self.send_json(payload(), cache=300)

        if p == "/api/stats":
            c = counters()
            with DB_LOCK:
                devices = db.execute("SELECT COUNT(*) FROM progress").fetchone()[0]
                events = db.execute("SELECT COUNT(*) FROM events").fetchone()[0]
            return self.send_json({"counters": c, "devices": devices, "events": events,
                                   "trending": trending(5),
                                   "terms": len(TERMS), "seeds": len(BIP39),
                                   "price_age_s": int(time.time() - PRICE_CACHE["ts"]) if PRICE_CACHE["data"] else None})

        # ---- dictionary
        if p == "/api/terms":
            return self.terms(q)
        if p.startswith("/api/terms/"):
            name = urllib.parse.unquote(p[len("/api/terms/"):]).replace("-", " ").lower()
            t = BY_NAME.get(name)
            if t:
                hit_word(t["n"], q.get("uid", [""])[0])
            return self.send_json(t or {"error": "not found"}, 200 if t else 404)
        if p == "/api/categories":
            return self.send_json([{"cat": c, "count": sum(1 for t in TERMS if t["c"] == c)} for c in CATS], cache=600)
        if p == "/api/random":
            import secrets
            return self.send_json(secrets.choice(TERMS))

        # ---- seeds
        if p == "/api/seeds":
            qs = (q.get("q", [""])[0] or "").lower()
            off = int(q.get("offset", [0])[0]); lim = min(int(q.get("limit", [500])[0]), 2048)
            items = [{"i": i, "w": w, "t": BY_NAME.get(w.lower(), {}).get("n")} for i, w in enumerate(BIP39)
                     if not qs or qs in w]
            return self.send_json({"total": len(items), "offset": off, "items": items[off:off + lim]}, cache=3600)
        if p == "/api/seeds/validate":
            if method == "POST":
                b = self.body_json(); bump("checks", uid=b.get("uid"))
                return self.send_json(validate_phrase(b.get("phrase", "")))
            return self.send_json(validate_phrase(q.get("phrase", [""])[0]))
        if p == "/api/seeds/generate" and method == "POST":
            b = self.body_json()
            bump("phrases_made", uid=b.get("uid"))
            return self.send_json({"words": generate_phrase(b.get("n", 12)), "warning":
                                   "Practice only. Never store funds using a phrase generated by any "
                                   "app, website or API — including this one."})

        # ---- market
        if p == "/api/prices":
            d = prices()
            return self.send_json(d, cache=30)
        if p == "/api/prices/history":
            coin = q.get("coin", ["bitcoin"])[0]
            days = q.get("days", ["1"])[0]
            try:
                h = _get(f"https://api.coingecko.com/api/v3/coins/{coin}/market_chart?vs_currency=usd&days={days}")
                pts = [round(p[1], 6) for p in h["prices"]]
                return self.send_json({"coin": coin, "days": days, "points": pts[::max(1, len(pts)//80)]}, cache=120)
            except Exception as e:
                return self.send_json({"coin": coin, "points": [], "error": str(e)})

        # ---- content
        if p == "/api/quotes":
            cat = q.get("cat", ["All"])[0]
            items = [{"t": t, "a": a, "c": c} for (t, a, c) in Q.QUOTES if cat == "All" or c == cat]
            return self.send_json({"total": len(items), "items": items}, cache=600)
        if p == "/api/rules":
            return self.send_json({"items": Q.RULES}, cache=600)

        # ---- progress
        if p == "/api/progress":
            uid = (q.get("uid", [""])[0] or "").strip()
            if method == "GET":
                if not uid:
                    return self.send_json({"error": "uid required"}, 400)
                with DB_LOCK:
                    row = db.execute("SELECT blob, created_at, updated_at FROM progress WHERE uid=?", (uid,)).fetchone()
                if not row:
                    return self.send_json({"found": False})
                return self.send_json({"found": True, "blob": json.loads(row[0]),
                                       "created_at": row[1], "updated_at": row[2]})
            if method == "POST":
                b = self.body_json()
                uid = (b.get("uid") or uid or "").strip()
                if not uid or len(uid) > 128:
                    return self.send_json({"error": "valid uid required"}, 400)
                blob = json.dumps(b.get("blob") or {}, separators=(",", ":"))
                if len(blob) > 400_000:
                    return self.send_json({"error": "payload too large"}, 413)
                now = int(time.time())
                with DB_LOCK:
                    db.execute("""INSERT INTO progress(uid,blob,created_at,updated_at) VALUES(?,?,?,?)
                                  ON CONFLICT(uid) DO UPDATE SET blob=excluded.blob, updated_at=excluded.updated_at""",
                               (uid, blob, now, now))
                    db.commit()
                return self.send_json({"ok": True, "updated_at": now, "bytes": len(blob)})
            if method == "DELETE":
                with DB_LOCK:
                    db.execute("DELETE FROM progress WHERE uid=?", (uid,)); db.commit()
                return self.send_json({"ok": True})

        if p == "/api/export":
            uid = q.get("uid", [""])[0]
            with DB_LOCK:
                row = db.execute("SELECT blob, updated_at FROM progress WHERE uid=?", (uid,)).fetchone()
            if not row:
                return self.send_json({"error": "not found"}, 404)
            body = json.dumps({"uid": uid, "updated_at": row[1], "progress": json.loads(row[0])}, indent=2).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Disposition", 'attachment; filename="wordvault-progress.json"')
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            return self.wfile.write(body)

        # ---- analytics (aggregate only)
        if p == "/api/event" and method == "POST":
            b = self.body_json()
            kind = str(b.get("kind", ""))[:40]
            if not kind:
                return self.send_json({"error": "kind required"}, 400)
            if kind == "word_read" and b.get("name"):
                nm = str(b["name"])[:80]
                if BY_NAME.get(nm.lower()):
                    hit_word(BY_NAME[nm.lower()]["n"], b.get("uid"))
                    return self.send_json({"ok": True})
            bump(kind, uid=str(b.get("uid", ""))[:64] or None)
            return self.send_json({"ok": True})

        if p == "/api/trending":
            lim = min(int(q.get("limit", [10])[0]), 30)
            return self.send_json({"items": trending(lim), "note": "real usage: words opened by everyone using this backend"})

        # ---- static
        if p in ("/", "/index.html", "/app"):
            return self.send_file(ROOT / "index.html")
        if p == "/WordVault.html":
            return self.send_file(ROOT / "WordVault.html")
        if p == "/manifest.webmanifest":
            return self.send_file(ROOT / "manifest.webmanifest")
        if p == "/wordlist":
            return self.send_file(ROOT / "WordVault-wordlist.md")
        if p == "/api":
            return self.send_json({"endpoints": [
                "GET /api/health", "GET /api/meta", "GET /api/stats",
                "GET /api/terms?q=&cat=&level=&offset=&limit=&sort=", "GET /api/terms/{name}",
                "GET /api/categories", "GET /api/random",
                "GET /api/seeds?q=&offset=&limit=", "POST /api/seeds/validate", "POST /api/seeds/generate",
                "GET /api/prices", "GET /api/prices/history?coin=&days=",
                "GET /api/quotes?cat=", "GET /api/rules", "GET /api/trending?limit=",
                "GET /api/progress?uid=", "POST /api/progress", "DELETE /api/progress?uid=",
                "GET /api/export?uid=", "POST /api/event"]})
        safe = p.lstrip("/").replace("..", "")
        return self.send_file(ROOT / safe)

    # ---- dictionary query
    def terms(self, q):
        query = (q.get("q", [""])[0] or "").strip()
        cat = q.get("cat", ["All"])[0]
        level = q.get("level", ["0"])[0]
        off = max(0, int(q.get("offset", [0])[0]))
        lim = min(max(1, int(q.get("limit", [40])[0])), 500)
        sort = q.get("sort", ["az"])[0]

        if query:
            safe = re.sub(r'["*^]', " ", query).strip()
            fts = " ".join(w + "*" for w in safe.split() if w)
            sql = ("""SELECT t.name, t.body, t.cat, t.level, bm25(terms_fts) AS r
                      FROM terms_fts t WHERE terms_fts MATCH ? ORDER BY r LIMIT 400""")
            try:
                with DB_LOCK:
                    rows = db.execute(sql, (fts,)).fetchall()
            except Exception:
                rows = []
            items = []
            for name, body, c, lvl, _r in rows:
                t = BY_NAME.get(name.lower())
                if not t:
                    continue
                if cat != "All" and t["c"] != cat:
                    continue
                if level != "0" and str(t["l"]) != str(level):
                    continue
                items.append(t)
            if sort == "za":
                items.sort(key=lambda t: t["n"].lower(), reverse=True)
            return self.send_json({"total": len(items), "offset": off, "limit": lim,
                                   "query": query, "engine": "fts5", "items": items[off:off + lim]})

        items = [t for t in TERMS
                 if (cat == "All" or t["c"] == cat) and (level == "0" or str(t["l"]) == str(level))]
        items.sort(key=lambda t: t["n"].lower(), reverse=(sort == "za"))
        return self.send_json({"total": len(items), "offset": off, "limit": lim,
                               "engine": "index", "items": items[off:off + lim]}, cache=120)


def main():
    db_init()
    threading.Thread(target=warm_prices, daemon=True).start()
    srv = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    print(f"WordVault {VERSION} backend")
    print(f"  terms {len(TERMS)} · seeds {len(BIP39)} · categories {len(CATS)}")
    print(f"  db     {DB_PATH}")
    print(f"  http://0.0.0.0:{PORT}  (api docs at /api)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nshutdown")
        srv.shutdown()


if __name__ == "__main__":
    main()
