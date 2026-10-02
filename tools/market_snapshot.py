#!/usr/bin/env python3
"""Write market.json — the layer that lets the app run on a static host with no server.

GitHub Pages cannot execute Python, so the app cannot call a backend there. Instead this
script runs on a schedule (see .github/workflows/market.yml), turns whatever the public
keyless APIs will tell it into one small JSON file, and commits it. Pages then serves that
file as a static asset, exactly like a stylesheet.

Sources, in order of how much they need from the world:

  * CoinGecko  — prices *plus* market cap, dominance, 7-day sparklines. Keyless and
                 CORS-friendly, but it throttles shared and datacentre IPs aggressively
                 (a 429 at any moment is normal), so it is never the only source.
  * Kraken     — prices and today's open, from the public ticker. No key, no meaningful
                 throttle, and it reflects the caller's origin so browsers can use it too.
  * alternative.me — the Fear & Greed index.

Nothing here is invented. If a field cannot be fetched it stays null and the app renders a
dash; if no price source answers at all, the previously committed market.json is left
untouched rather than being overwritten with zeros.

    python3 tools/market_snapshot.py            # writes ./market.json
    python3 tools/market_snapshot.py --check    # exit 1 if it would change (used by CI)
"""
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "market.json"

COINS = [("bitcoin", "BTC", "Bitcoin"), ("ethereum", "ETH", "Ethereum"), ("solana", "SOL", "Solana"),
         ("binancecoin", "BNB", "BNB"), ("ripple", "XRP", "XRP"), ("cardano", "ADA", "Cardano"),
         ("dogecoin", "DOGE", "Dogecoin"), ("tron", "TRX", "Tron"), ("chainlink", "LINK", "Chainlink"),
         ("avalanche-2", "AVAX", "Avalanche"), ("polkadot", "DOT", "Polkadot"), ("litecoin", "LTC", "Litecoin")]
IDS = ",".join(c[0] for c in COINS)

# Kraken pair per symbol. XBT and XDG are Kraken's own spellings for BTC and DOGE.
KRAKEN = {"BTC": "XBTUSD", "ETH": "ETHUSD", "SOL": "SOLUSD", "BNB": "BNBUSD", "XRP": "XRPUSD",
          "ADA": "ADAUSD", "DOGE": "XDGUSD", "TRX": "TRXUSD", "LINK": "LINKUSD",
          "AVAX": "AVAXUSD", "DOT": "DOTUSD", "LTC": "LTCUSD"}
UA = {"User-Agent": "WordVault/3.0 (+https://github.com/daviddan-241/SENTINEL)", "Accept": "application/json"}


def get(url, timeout=15):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


def kraken_key(key):
    """XXBTZUSD -> BTCUSD, XDGUSD -> DOGEUSD, SOLUSD -> SOLUSD."""
    k = key.upper()
    if len(k) > 6 and k.startswith("X") and "ZUSD" in k:
        k = k[1:].replace("ZUSD", "USD")
    return k.replace("XBT", "BTC").replace("XDG", "DOGE")


def from_kraken():
    """[{sym, price, chg}] — keyless, effectively unthrottled, so this is the backbone."""
    pairs = ",".join(KRAKEN.values())
    res = get("https://api.kraken.com/0/public/Ticker?pair=" + pairs).get("result") or {}
    by_pair = {kraken_key(k): v for k, v in res.items()}
    out = []
    for sym, pair in KRAKEN.items():
        v = by_pair.get(kraken_key(pair))
        if not v or not v.get("c"):
            continue
        last = float(v["c"][0])
        opened = float(v.get("o") or last)
        chg = round((last - opened) / opened * 100, 2) if opened else None
        out.append({"sym": sym, "price": last, "chg": chg,
                    "vol": float(v["v"][1]) * last if v.get("v") else None})
    return out


def from_coingecko():
    """The rich version: cap, volume, dominance source, and the sparklines. Often 429s."""
    market = get("https://api.coingecko.com/api/v3/coins/markets"
                 f"?vs_currency=usd&ids={IDS}&price_change_percentage=24h&sparkline=true")
    coins = {}
    for c in market:
        coins[c["id"]] = {
            "id": c["id"], "sym": c["symbol"].upper(), "name": c["name"],
            "price": c["current_price"], "chg": round(c.get("price_change_percentage_24h") or 0, 2),
            "cap": c.get("market_cap"), "vol": c.get("total_volume"),
            "spark": [round(p, 6) for p in (c.get("sparkline_in_7d", {}) or {}).get("price", [])][::8][:40],
        }
    glob = {}
    try:
        g = get("https://api.coingecko.com/api/v3/global")["data"]
        glob = {"mcap": g["total_market_cap"]["usd"], "vol": g["total_volume"]["usd"],
                "btcDom": round(g["market_cap_percentage"]["btc"], 1),
                "ethDom": round(g["market_cap_percentage"]["eth"], 1),
                "coins": g["active_cryptocurrencies"]}
    except Exception:
        pass
    return coins, glob


def fear_greed():
    try:
        d = get("https://api.alternative.me/fng/?limit=1")["data"][0]
        return {"value": int(d["value"]), "label": d["value_classification"]}
    except Exception:
        return None


def blank(entry):
    return {"id": entry[0], "sym": entry[1], "name": entry[2],
            "price": None, "chg": None, "cap": None, "vol": None, "spark": []}


def build():
    out = {"source": "kraken", "coins": [blank(c) for c in COINS], "global": {}, "fearGreed": None,
           "ts": int(time.time()), "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    by_id = {c["id"]: c for c in out["coins"]}
    by_sym = {c["sym"]: c for c in out["coins"]}

    # 1) CoinGecko first when it is willing: it is the only source with caps and sparklines.
    try:
        rich, glob = from_coingecko()
        if rich:
            for cid, row in rich.items():
                if cid in by_id:
                    by_id[cid].update(row)
            out["global"] = glob
            out["source"] = "coingecko"
    except Exception as e:
        print(f"  coingecko unavailable ({e.__class__.__name__}) — falling back to kraken", file=sys.stderr)

    # 2) Kraken fills in every price, and is the only source when CoinGecko is throttled.
    try:
        for row in from_kraken():
            coin = by_sym.get(row["sym"])
            if not coin:
                continue
            coin["price"] = row["price"]
            if coin["chg"] is None:
                coin["chg"] = row["chg"]
            if coin["vol"] is None:
                coin["vol"] = row["vol"]
            if out["source"] == "coingecko" and coin["cap"] is None:
                continue
            if out["source"] != "coingecko":
                out["source"] = out["source"] if out["source"] == "coingecko+kraken" else "kraken"
    except Exception as e:
        print(f"  kraken unavailable: {e}", file=sys.stderr)
        if out["source"] == "kraken":
            out["source"] = "unavailable"

    out["fearGreed"] = fear_greed()
    priced = [c for c in out["coins"] if c["price"] is not None]
    out["count"] = len(priced)
    out["note"] = ("Live prices from public, keyless APIs. Snapshot committed by GitHub Actions; "
                   "the page itself is static.")
    return out, len(priced)


def main():
    data, priced = build()
    if priced == 0:
        print("no source answered — leaving any existing market.json alone", file=sys.stderr)
        return 1
    text = json.dumps(data, separators=(",", ":"), sort_keys=True) + "\n"
    if "--check" in sys.argv:
        old = OUT.read_text() if OUT.exists() else ""
        old_data = json.loads(old) if old.strip() else {}
        # only the priced content matters; ts alone should not count as a change
        same = all(old_data.get(k) == data.get(k) for k in ("coins", "global", "fearGreed", "source"))
        print("unchanged" if same else "changed")
        return 0 if same else 1
    OUT.write_text(text)
    print(f"wrote {OUT} — {priced}/{len(data['coins'])} assets priced, source={data['source']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
