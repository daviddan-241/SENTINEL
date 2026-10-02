#!/usr/bin/env python3
"""Build WordVault: merges term files + BIP-39 word list into a single self-contained HTML app."""
import base64, hashlib, json, re, sys, os
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT.parent
DATA = ROOT / "data"

# terms that were placeholders / too weak -> removed
BLOCKLIST = {
    "gkr", "rekt radio", "snarky", "rug radar", "diamond hands (community)",
    "ngmi (lowercase)", "liquidation cascade", "funding", "satoshi surname",
    "nakamoto (satoshi)", "mixamo", "whitepaper season", "roadmap season",
    "vanity mining", "creditor committee", "bloom filter",
}

LEVELS = {1: "Basic", 2: "Intermediate", 3: "Advanced"}


def load_terms():
    """Import every data/terms*.py and concatenate their TERMS lists in file order."""
    files = sorted([p for p in DATA.glob("terms*.py")])
    terms, seen, dupes = [], set(), []
    for f in files:
        ns = {}
        exec(compile(f.read_text(), str(f), "exec"), ns)
        for t in ns["TERMS"]:
            name, cat, definition, level, example = t
            key = name.strip().lower()
            if key in BLOCKLIST:
                continue
            if key in seen:
                dupes.append(name)
                continue
            seen.add(key)
            terms.append({
                "n": name.strip(),
                "c": cat,
                "d": definition.strip(),
                "l": int(level),
                "e": example.strip() if example else "",
            })
    return terms, dupes


def load_bip39():
    words = [w.strip() for w in (ROOT / "bip39.txt").read_text().split() if w.strip()]
    assert len(words) == 2048, f"expected 2048 words, got {len(words)}"
    assert words[0] == "abandon" and words[-1] == "zoo"
    return words


def main():
    terms, dupes = load_terms()
    bip39 = load_bip39()

    by_name = {t["n"].lower(): t for t in terms}
    seed_words = [{"i": i, "w": w, "t": by_name.get(w.lower(), {}).get("n")} for i, w in enumerate(bip39)]

    cats = []
    for t in terms:
        if t["c"] not in cats:
            cats.append(t["c"])

    from data import quotes as _q

    matching = sum(1 for s in seed_words if s["t"])
    payload = {
        "terms": terms,
        "seeds": seed_words,
        "cats": cats,
        "levels": LEVELS,
        "quotes": _q.QUOTES,
        "rules": _q.RULES,
        "stats": {"terms": len(terms), "seeds": len(seed_words), "seedDefs": matching},
    }

    blob = json.dumps(payload, ensure_ascii=False, separators=(",", ":"))

    icon_b64 = base64.b64encode((ROOT / "icon180.png").read_bytes()).decode()
    icon_uri = "data:image/png;base64," + icon_b64
    manifest = {
        "name": "WordVault — Crypto Words & Seed Words",
        "short_name": "WordVault",
        "start_url": ".",
        "display": "standalone",
        "background_color": "#06070c",
        "theme_color": "#06070c",
        "description": "Crypto dictionary plus the official BIP-39 2,048-word seed list.",
        "icons": [
            {"src": "data:image/png;base64," + base64.b64encode((ROOT / "icon.png").read_bytes()).decode(),
             "sizes": "512x512", "type": "image/png", "purpose": "any maskable"},
            {"src": icon_uri, "sizes": "180x180", "type": "image/png"},
        ],
    }
    manifest_uri = "data:application/manifest+json;base64," + base64.b64encode(
        json.dumps(manifest).encode()).decode()

    head = (ROOT / "tpl_head.html").read_text()
    body = (ROOT / "tpl_body.html").read_text()
    js = "\n".join((ROOT / f).read_text() for f in ("js1.js", "js2.js", "js3.js", "js4.js"))
    head = head.replace("__ICON__", icon_uri).replace("__MANIFEST__", manifest_uri)
    html = (head + body + "\n<script>window.__VAULT__=" + blob + ";</script>\n<script>\n"
            + js + "\n</script>\n</body>\n</html>\n")

    out = OUT / "WordVault.html"
    out.write_text(html)
    (OUT / "index.html").write_text(html)   # same app, so the folder can be served or saved to home screen directly
    (OUT / "manifest.webmanifest").write_text(json.dumps(manifest, indent=2))

    # service worker — versioned with a hash of the app so a new build always refreshes
    version = hashlib.sha256(html.encode()).hexdigest()[:10]
    sw = (ROOT / "sw.js").read_text().replace("__VERSION__", version)
    (OUT / "sw.js").write_text(sw)
    print(f"wrote {OUT / 'sw.js'}  (cache version {version})")

    print(f"terms: {len(terms)}  (dupes skipped: {len(dupes)})")
    if dupes:
        print("  skipped:", ", ".join(dupes))
    print(f"seed words: {len(seed_words)}  with dictionary entry: {matching}")
    print(f"categories: {len(cats)} -> {', '.join(cats)}")
    print(f"levels:  " + "  ".join(f"L{k}={sum(1 for t in terms if t['l']==k)}" for k in (1, 2, 3)))
    print(f"wrote {out}  ({out.stat().st_size/1024:.0f} KB)")

    # companion plain-text reference (easy to read, print or share)
    md = ["# WordVault — the word list",
          "",
          f"**{len(terms)} crypto terms** and the official **BIP-39 2,048-word seed list**. "
          "Every seed word is a word real wallets use to generate recovery phrases. "
          "Entries marked ● also have a full dictionary definition in WordVault.html.",
          ""]
    md += ["## Crypto terms A–Z", ""]
    for t in sorted(terms, key=lambda x: x["n"].lower()):
        md.append(f"### {t['n']}  ·  {t['c']}  ·  {LEVELS[t['l']]}")
        md.append(t["d"])
        if t["e"]:
            md.append(f"_Example: {t['e']}_")
        md.append("")
    md += ["## The BIP-39 seed word list (2,048 words)", ""]
    for i in range(0, len(bip39), 8):
        md.append(" | ".join(bip39[i:i + 8]))
    md += ["", "---", "", "Educational material only — not financial advice. Never generate or store a real "
           "recovery phrase using any app, website or list, including this one."]
    (OUT / "WordVault-wordlist.md").write_text("\n".join(md))
    print(f"wrote {OUT / 'WordVault-wordlist.md'}")


if __name__ == "__main__":
    main()
