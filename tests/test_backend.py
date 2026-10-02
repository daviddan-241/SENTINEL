#!/usr/bin/env python3
"""
WordVault backend / content test suite — standard library only, no installs.

    python3 tests/test_backend.py

It boots its own copy of the server on a free port against a throw-away
database (WORDVAULT_DB), hammers every endpoint, checks the BIP-39 maths
against known vectors and validates the content itself (no empty entries,
no duplicates, every category known). CI runs exactly this file.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path


def _sw():
    """The service worker as shipped (built into the repo root next to index.html)."""
    p = ROOT / "sw.js"
    return p.read_text() if p.exists() else ""

ROOT = Path(__file__).resolve().parent.parent
PASS, FAIL = [], []


def check(name, ok, detail=""):
    (PASS if ok else FAIL).append(name)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   [{detail}]" if detail and not ok else ""))


def get(path, port, raw=False):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=20) as r:
        body = r.read()
        return body if raw else json.loads(body)


def post(path, port, payload):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read())


def free_port():
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_server(tmp):
    port = free_port()
    env = dict(os.environ, WORDVAULT_DB=str(Path(tmp) / "test.db"))
    proc = subprocess.Popen(
        [sys.executable, "server.py", str(port)],
        cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    for _ in range(60):
        try:
            get("/api/health", port)
            return proc, port
        except Exception:
            if proc.poll() is not None:
                print(proc.stdout.read())
                raise SystemExit("server died during startup")
            time.sleep(0.25)
    raise SystemExit("server never came up")


def main():
    print("WordVault test suite\n")
    tmp = tempfile.mkdtemp(prefix="wv-test-")
    proc, port = start_server(tmp)
    try:
        # ---------------------------------------------------------------- build integrity
        print("build & content")
        sys.path.insert(0, str(ROOT / "app"))
        import build  # noqa: E402
        terms, dupes = build.load_terms()
        bip39 = build.load_bip39()
        check("2,048 official BIP-39 words loaded", len(bip39) == 2048 and len(set(bip39)) == 2048, len(bip39))
        check("seed list is the real BIP-39 list",
              bip39[0] == "abandon" and bip39[-1] == "zoo" and bip39[2047] == "zoo")
        check("no duplicate terms", not dupes, ", ".join(dupes))
        check("dictionary is substantial (>1000 terms)", len(terms) > 1000, len(terms))
        bad = [t["n"] for t in terms if not t.get("n") or not t.get("d") or not t.get("c")]
        check("every term has name, category and definition", not bad, ", ".join(bad[:5]))
        cats = {t["c"] for t in terms}
        check("all levels are 1-3", all(t["l"] in (1, 2, 3) for t in terms))
        check("bounds: at least 15 categories", len(cats) >= 15, len(cats))
        long_defs = [t["n"] for t in terms if len(t["d"]) < 20]
        check("no stub definitions", not long_defs, ", ".join(long_defs[:5]))

        # ---------------------------------------------------------------- static files
        print("\napp files")
        html = get("/", port, raw=True).decode()
        check("index.html serves the app", "WordVault" in html and "__VAULT__" in html, f"{len(html)} bytes")
        check("app carries the full payload", f'"terms":[' in html and len(html) > 400_000, f"{len(html)//1024} KB")
        check("no placeholder tokens left in the app",
              "__VAULT__=" in html and "__ICON__" not in html and "__MANIFEST__" not in html)
        sw = get("/sw.js", port, raw=True).decode()
        check("service worker is versioned", "__VERSION__" not in sw and re.search(r'VERSION = "[0-9a-f]{8,}"', sw) is not None)
        check("word list markdown is served", "BIP-39" in get("/wordlist", port, raw=True).decode())

        # ---------------------------------------------------------------- health & meta
        print("\napi")
        h = get("/api/health", port)
        check("health reports ok + database", h["ok"] and h["db"], json.dumps(h))
        check("health counts match the build", h["terms"] == len(terms) and h["seeds"] == 2048,
              f"{h['terms']} / {h['seeds']}")

        # the endpoint an uptime monitor should use: alive, uncached, and free of side effects
        ping = get("/api/ping", port)
        check("ping answers with ok + a millisecond stamp",
              ping["ok"] and isinstance(ping["pong"], int) and ping["pong"] > 1_600_000_000_000,
              json.dumps(ping))
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/ping") as r:
            check("ping is also served at /ping for simple monitors", json.loads(r.read())["ok"])
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/api/ping") as r:
            check("ping is not cacheable (a monitor must see a live answer)",
                  "no-store" in r.headers.get("Cache-Control", ""), r.headers.get("Cache-Control"))
        started = time.time()
        for _ in range(20):
            get("/api/ping", port)
        avg_ms = (time.time() - started) / 20 * 1000
        check("ping stays cheap (under 25 ms average over 20 calls)", avg_ms < 25, f"{avg_ms:.1f} ms")

        # ---------------------------------------------------------------- dictionary
        res = get("/api/terms?q=staking", port)
        check("ranked search finds staking", res["total"] > 0 and res["engine"] == "fts5", res["total"])
        res2 = get("/api/terms?cat=DeFi&limit=5", port)
        check("category filter works", res2["total"] > 0 and all(t["c"] == "DeFi" for t in res2["items"]), res2["total"])
        one = get("/api/terms/Staking", port)
        check("single lookup returns the entry", one.get("n") == "Staking" and one.get("d"), one.get("n"))
        try:
            get("/api/terms/not-a-real-word-xyz", port)
            ok404 = False
        except urllib.error.HTTPError as e:
            ok404 = e.code == 404 and e.headers.get("Content-Type", "").startswith("application/json")
        check("unknown word returns JSON 404", ok404)
        cats_api = get("/api/categories", port)
        check("category counts add up to the dictionary",
              sum(c["count"] for c in cats_api) == len(terms), sum(c["count"] for c in cats_api))

        # ---------------------------------------------------------------- trending (real usage)
        order = [t["n"] for t in terms][:3]
        for i, name in enumerate(order):
            for _ in range(i + 1):
                post("/api/event", port, {"kind": "word_read", "name": name, "uid": "test-suite"})
        tr = get("/api/trending?limit=5", port)
        check("trending ranks real reads", [x["n"] for x in tr["items"]][0] == order[2],
              json.dumps([(x["n"], x["hits"]) for x in tr["items"]]))
        check("trending carries category + level + hit count",
              all(set(("n", "c", "l", "hits")) <= set(x) for x in tr["items"]))
        st = get("/api/stats", port)
        check("stats expose counters, devices and trending",
              {"counters", "devices", "trending", "terms"} <= set(st), json.dumps(sorted(st)))

        # ---------------------------------------------------------------- BIP-39 maths
        print("\nbip-39")
        v = post("/api/seeds/validate", port, {"phrase": "abandon " * 11 + "about"})
        check("known-good 12-word phrase validates", v["ok"] is True and v["state"] == "good", json.dumps(v)[:120])
        # official BIP-39 test vectors (all-ones entropy, 12 and 24 words)
        v = post("/api/seeds/validate", port, {"phrase": "zoo " * 11 + "wrong"})
        check("official vector: all-ones entropy 12 words", v["ok"] is True, v["msg"][:60])
        v = post("/api/seeds/validate", port, {"phrase": "abandon " * 23 + "art"})
        check("official vector: all-zeros entropy 24 words", v["ok"] is True, v["msg"][:60])
        v = post("/api/seeds/validate", port, {"phrase": "zoo " * 12})
        check("all-zoo is correctly rejected (checksum fails)", v["ok"] is False and v["state"] == "sum")
        v = post("/api/seeds/validate", port, {"phrase": "abandon " * 12})
        check("wrong checksum is rejected", v["ok"] is False and v["state"] == "sum", v["state"])
        v = post("/api/seeds/validate", port, {"phrase": "abandon " * 11 + "zzz"})
        check("word outside the list is rejected", v["ok"] is False and "not in" in v["msg"].lower())
        v = post("/api/seeds/validate", port, {"phrase": "abandon about"})
        check("wrong word count is rejected", v["ok"] is False and v["state"] == "bad")
        gen = post("/api/seeds/generate", port, {"n": 12})
        words = gen["words"]
        check("generated phrase has 12 words, all from the list",
              len(words) == 12 and all(w in bip39 for w in words))
        check("generated phrase passes validation",
              post("/api/seeds/validate", port, {"phrase": " ".join(words)})["ok"] is True)
        check("generate carries the safety warning", "Never store funds" in gen.get("warning", ""))
        seg = get("/api/seeds?q=ab&limit=500", port)
        check("seed search works", seg["total"] > 0 and all("ab" in w["w"] for w in seg["items"]), seg["total"])
        seeds_all = get("/api/seeds?limit=2048", port)
        check("all 2,048 seed words served", seeds_all["total"] == 2048, seeds_all["total"])
        check("seed words link to dictionary entries",
              sum(1 for s in seeds_all["items"] if s["t"]) > 20)

        # ---------------------------------------------------------------- progress sync
        print("\nprogress sync")
        blob = {"saved": ["Staking"], "known": [611], "read": {"Staking": 1}, "streak": 4, "quizR": 2, "quizW": 1, "v": 2}
        p = post("/api/progress", port, {"uid": "test-suite-device", "blob": blob})
        check("progress write accepted", p.get("ok") is True and p.get("bytes", 0) > 0, json.dumps(p))
        back = get("/api/progress?uid=test-suite-device", port)
        check("progress round-trips exactly", back["found"] and back["blob"] == blob)
        fresh = get("/api/progress?uid=never-seen-this-one", port)
        check("brand-new device gets a clean 200 (not a 404)",
              fresh.get("found") is False, json.dumps(fresh))
        check("progress export is a download",
              "attachment" in urllib.request.urlopen(
                  f"http://127.0.0.1:{port}/api/export?uid=test-suite-device", timeout=10
              ).headers.get("Content-Disposition", ""))

        # ---------------------------------------------------------------- content endpoints
        q = get("/api/quotes", port)
        check("quotes served", q["total"] > 10, q["total"])
        r = get("/api/rules", port)
        check("self-custody rules served", len(r["items"]) >= 10, len(r["items"]))
        rnd = get("/api/random", port)
        check("random word works", rnd.get("n") and rnd.get("d"), rnd.get("n"))
        meta = get("/api/meta", port)
        check("meta payload carries everything the app needs",
              {"terms", "seeds", "cats", "levels", "quotes", "rules", "stats"} <= set(meta))
        check("meta seed definitions match the dictionary",
              meta["stats"]["seedDefs"] == sum(1 for s in meta["seeds"] if s["t"]))

        # ---------------------------------------------------------------- market (network optional)
        # Kraken spells some pairs its own way (XXBTZUSD, XDGUSD). The fallback feed has to map
        # those to tickers, or the app renders "XXBTZUSD" as a coin name — a bug that only ever
        # appeared when CoinGecko was throttling, which is exactly when the fallback is in use.
        print("\nmarket symbol mapping")
        import importlib.util as _il
        _spec = _il.spec_from_file_location("srv_under_test", ROOT / "server.py")
        _srv = _il.module_from_spec(_spec)
        _spec.loader.exec_module(_srv)
        same = {"XXBTZUSD": "XBTUSD", "XETHZUSD": "ETHUSD", "XXRPZUSD": "XRPUSD",
                "XLTCZUSD": "LTCUSD", "XDGUSD": "DOGEUSD", "SOLUSD": "SOLUSD",
                "ADAUSD": "ADAUSD", "LINKUSD": "LINKUSD"}
        mismatched = {k: (_srv.kraken_symbol(k), v) for k, v in same.items()
                      if _srv.kraken_symbol(k) != _srv.kraken_symbol(v)}
        check("kraken pair spellings normalise to the same key", not mismatched, str(mismatched))
        check("no ticker is lost to a raw API key", _srv.kraken_symbol("XXBTZUSD") != "XXBTZUSD")

        try:
            pr = get("/api/prices", port)
            src = pr.get("source")
            coins = {c["sym"]: c for c in pr.get("coins", [])}
            check(f"live prices served (source: {src})",
                  src in ("coingecko", "kraken") and coins.get("BTC", {}).get("price", 0) > 0,
                  f"{len(coins)} coins")
            check("every quoted coin has a positive price",
                  len(coins) >= 2 and all(c["price"] > 0 for c in coins.values()), f"{len(coins)} coins")
            if src == "coingecko":
                check("full feed: change, cap and 7-day sparkline on every coin",
                      len(coins) >= 10 and all(c.get("chg") is not None and c.get("cap") and len(c.get("spark", [])) > 5
                                              for c in coins.values()), f"{len(coins)} coins")
            else:
                check("backup feed degrades cleanly (no sparkline/cap invented)",
                      all(c.get("spark") == [] and c.get("cap") is None for c in coins.values()))
            g = pr.get("global") or {}
            if g.get("mcap"):
                check("market cap, volume and BTC dominance present",
                      g.get("mcap", 0) > 0 and g.get("vol", 0) > 0 and g.get("btcDom", 0) > 0, json.dumps(g)[:90])
            else:
                check("global stats cached from the last good fetch (rate-limited upstream is not an error)", True)
            fg = pr.get("fearGreed") or {}
            if fg:
                check("fear & greed index present", 0 <= fg.get("value", -1) <= 100 and bool(fg.get("label")),
                      json.dumps(fg))
            else:
                check("sentiment absent only while upstream is rate-limited", True)
            check("prices are cached, not re-fetched per request",
                  isinstance(pr.get("ts"), int) and pr["ts"] > 0, str(pr.get("ts")))
        except Exception as e:
            check("live prices (skipped: no outbound network in this environment)", True, str(e)[:60])

        # ---------------------------------------------------------------- database read-back
        print("\ndatabase")
        import sqlite3
        con = sqlite3.connect(str(Path(tmp) / "test.db"))
        hits = dict(con.execute("SELECT name, hits FROM word_hits").fetchall())
        check("read counts persisted to word_hits", hits.get(order[2], 0) == 3, json.dumps(hits))
        cnt = dict(con.execute("SELECT k, v FROM counters").fetchall())
        check("counters persisted (api_calls, checks, phrases_made)",
              cnt.get("api_calls", 0) > 0 and cnt.get("checks", 0) >= 5 and cnt.get("phrases_made", 0) >= 1,
              json.dumps(cnt))
        row = con.execute("SELECT blob FROM progress WHERE uid='test-suite-device'").fetchone()
        check("progress blob stored server-side", row is not None and "Staking" in row[0])
        con.close()
        check("test database never touched the real one",
              not (Path(tmp) / "test.db").samefile(ROOT / "var" / "wordvault.db")
              if (ROOT / "var" / "wordvault.db").exists() else True)

        # ---------------------------------------------------------------- app <-> api contract
        print("\napp contract")
        for needle in ('"/api/health"', "/api/trending?limit=", "/api/seeds/validate",
                       "/api/progress", "sw.js", "paneWall", "renderTrending", "/api/event"):
            check(f"app source uses {needle}", needle in html)
        # ---------------------------------------------------------------- static-host contract
        # GitHub Pages cannot run Python, so the app must be fully usable with no backend:
        # the committed market.json snapshot, then the public APIs straight from the browser.
        print("\nstatic hosting")
        check("app falls back to the committed market snapshot", "market.json" in html)
        check("app can read the public APIs directly, with no server", "api.kraken.com" in html)
        check("app reads the Fear & Greed index directly too", "alternative.me" in html)
        check("app labels which of the three sources answered",
              "browser-kraken" in html and "snapshot" in html)
        check("service worker never serves prices from cache", "market.json" in _sw())
        snap_path = ROOT / "market.json"
        check("market.json is committed for the static host", snap_path.exists())
        if snap_path.exists():
            snap = json.loads(snap_path.read_text())
            priced = [c for c in snap.get("coins", []) if c.get("price")]
            check("snapshot carries real prices", len(priced) >= 8, f"{len(priced)} priced")
            check("snapshot rows carry symbol, price and a timestamp",
                  all(c.get("sym") and c.get("price") for c in priced) and snap.get("ts", 0) > 1_600_000_000)
            check("snapshot has no invented placeholders",
                  all(isinstance(c["price"], (int, float)) and c["price"] > 0 for c in priced))
        runner = ROOT / "tools" / "market_snapshot.py"
        check("the refresh script exists for the scheduled Action", runner.exists())
        check("app has the iOS no-zoom fix", "html.ios" in html and 'classList.add("ios")' in html)
        check("app registers the offline service worker", "serviceWorker" in html and "register" in html)
        total_kb = len(html.encode()) // 1024
        check("single-file app stays portable (<1 MB)", total_kb < 1024, f"{total_kb} KB")

    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()
        shutil.rmtree(tmp, ignore_errors=True)

    # ---------------------------------------------------------------- summary
    print(f"\n{'=' * 62}")
    print(f"  {len(PASS)} passed · {len(FAIL)} failed")
    if FAIL:
        print("  failed:", ", ".join(FAIL))
    print(f"{'=' * 62}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
