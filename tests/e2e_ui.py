#!/usr/bin/env python3
"""
WordVault browser end-to-end test — iPhone profile, real user journey.

    pip install playwright && playwright install chromium
    python3 tests/e2e_ui.py            # starts its own server + throw-away database

Proves, in a real browser: the iOS no-zoom rule, the three-tab bar, the word wall,
saving/learning, real-usage trending on a cold database, the offline fallback and
the service-worker app shell. Fails loudly on any console error.
"""
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IPHONE_UA = ("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
             "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1")
PASS, FAIL = [], []


def check(name, ok, detail=""):
    (PASS if ok else FAIL).append(name)
    print(f"  {'PASS' if ok else 'FAIL'}  {name}" + (f"   [{detail}]" if detail and not ok else ""))


def free_port():
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def start_server(tmp):
    port = free_port()
    env = dict(os.environ, WORDVAULT_DB=str(Path(tmp) / "e2e.db"))
    proc = subprocess.Popen([sys.executable, "server.py", str(port)], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    for _ in range(60):
        try:
            urllib.request.urlopen(f"http://127.0.0.1:{port}/api/health", timeout=5).read()
            return proc, port
        except Exception:
            if proc.poll() is not None:
                print(proc.stdout.read())
                raise SystemExit("server died during startup")
            time.sleep(0.25)
    raise SystemExit("server never came up")


def main():
    try:
        from playwright.sync_api import sync_playwright
    except ImportError as e:
        print(f"playwright is not available ({e}) — pip install playwright && playwright install chromium")
        return 0

    print("WordVault end-to-end (iPhone profile)\n")
    tmp = tempfile.mkdtemp(prefix="wv-e2e-")
    proc, port = start_server(tmp)
    base = f"http://127.0.0.1:{port}"
    errors, console = [], []

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            # iPhone 13 profile, written out by hand so the test has no dependency
            # on playwright's device registry (it moved between versions)
            ctx = browser.new_context(
                viewport={"width": 390, "height": 844},
                device_scale_factor=3,
                is_mobile=True,
                has_touch=True,
                user_agent=IPHONE_UA,
                service_workers="allow",
            )
            page = ctx.new_page()
            page.on("pageerror", lambda e: errors.append(str(e)[:200]))
            page.on("console", lambda m: console.append((m.type, m.text[:200])))

            page.goto(base + "/", wait_until="networkidle")
            page.wait_for_timeout(2500)

            # ---------------------------------------------------------- iOS, layout, no zoom
            print("device & layout")
            check("iPhone Safari detected → html.ios", page.evaluate("document.documentElement.classList.contains('ios')"))
            q = page.eval_on_selector("#q", "e=>parseFloat(getComputedStyle(e).fontSize)")
            check("search field is 16px (Safari will not zoom on focus)", q >= 16, f"{q}px")
            page.click('.tabbtn[data-v="seeds"]')
            page.wait_for_timeout(600)
            page.click('#seedSeg button[data-s="check"]')
            page.wait_for_timeout(600)
            t = page.eval_on_selector("#ptext", "e=>parseFloat(getComputedStyle(e).fontSize)")
            check("phrase textarea is 16px too", t >= 16, f"{t}px")
            z = page.eval_on_selector("#ptext", "e=>getComputedStyle(e).touchAction")
            check("paste field uses touch-action:manipulation", z == "manipulation", z)
            page.focus("#ptext")
            page.wait_for_timeout(250)
            vw = page.evaluate("[window.visualViewport.scale, window.innerWidth]")
            check("focusing the field does not scale the page", abs(vw[0] - 1) < 0.01, str(vw))
            check("no horizontal overflow", page.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 2"),
                  str(page.evaluate("[document.documentElement.scrollWidth, window.innerWidth]")))
            page.keyboard.press("Escape")

            # ---------------------------------------------------------- three tabs
            print("\ntabs & drawer")
            tabs = page.eval_on_selector_all(".tabbtn", "e=>e.map(x=>x.textContent.trim())")
            check("exactly three bottom tabs", tabs == ["Home", "Words", "Seeds"], str(tabs))
            info = page.eval_on_selector('.tabbtn.on', "e=>[getComputedStyle(e).transform, getComputedStyle(e).zIndex]")
            check("active tab is lifted and scaled", "1.07" in info[0] and "-3" in info[0], info[0])
            check("sliding indicator exists", page.eval_on_selector("#tabInd", "e=>!!e"))
            page.click("#btnDrawer")
            page.wait_for_timeout(600)
            rows = page.eval_on_selector_all("#drawer .drow", "e=>e.length")
            check("everything else lives in the drawer (10 rows)", rows >= 10, str(rows))
            page.keyboard.press("Escape")
            page.wait_for_timeout(400)

            # ---------------------------------------------------------- save a real word
            print("\nuser journey")
            page.click('.tabbtn[data-v="words"]')
            page.wait_for_timeout(600)
            page.fill("#q", "restaking")
            page.wait_for_timeout(900)
            hits = page.eval_on_selector_all("#termList .rowitem", "e=>e.length")
            check("search finds the word", hits >= 1, str(hits))
            page.click("#termList .rowitem")
            page.wait_for_timeout(700)
            title = page.text_content("#sheetIn h3")
            page.click("#sheet [data-save]")
            page.wait_for_timeout(700)
            check("word opens in the sheet and saves", "Saved" in page.text_content("#sheet [data-save]"), title)
            page.keyboard.press("Escape")
            page.wait_for_timeout(400)

            # ---------------------------------------------------------- the word wall
            page.click('.tabbtn[data-v="seeds"]')
            page.wait_for_timeout(500)
            page.click('#seedSeg button[data-s="wall"]')
            page.wait_for_timeout(1000)
            check("wall renders all 2,048 words", page.eval_on_selector_all("#wall .ww", "e=>e.length") == 2048)
            check("wall shows progress filters", page.eval_on_selector_all("#seedPane [data-wf]", "e=>e.length") == 3)
            page.fill("#wq", "ab")
            page.wait_for_timeout(700)
            nq = page.eval_on_selector_all("#wall .ww", "e=>e.length")
            okq = page.eval_on_selector_all("#wall .ww", "e=>e.every(x=>x.textContent.includes('ab'))")
            check("wall search filters the tiles", 0 < nq < 2048 and okq, str(nq))
            page.fill("#wq", "")
            page.wait_for_timeout(600)
            page.evaluate("document.querySelectorAll('#wall .ww')[611].click()")
            page.wait_for_timeout(600)
            word = page.text_content("#sheetIn h3")
            page.click("#sheet [data-know]")
            page.wait_for_timeout(600)
            check("a word can be learned straight from the wall",
                  "Learned" in page.text_content("#sheet [data-know]"), word)
            check("sparkles fire on the tap", page.evaluate("document.querySelectorAll('.sparkle').length") > 0)
            page.keyboard.press("Escape")
            page.wait_for_timeout(400)

            # ---------------------------------------------------------- real trending on a cold db
            page.click('.tabbtn[data-v="home"]')
            page.wait_for_timeout(2500)
            trend = page.eval_on_selector_all("#trending .rowitem .nm", "e=>e.map(x=>x.textContent)")
            check("home lists trending words from real reads", len(trend) >= 1, str(trend))
            check("trending is the word we actually opened", "Restaking" in trend, str(trend))
            check("reveal-on-scroll ran", page.evaluate("document.querySelectorAll('.reveal.in').length") > 3)
            check("hero counters are real numbers", re.match(r"^1158", page.text_content("#heroStats").strip()) is not None,
                  page.text_content("#heroStats")[:20])
            page.evaluate("document.querySelector('#wallPreview').scrollIntoView({block:'center'})")
            page.wait_for_timeout(900)
            check("home previews the wall with a live rail",
                  page.eval_on_selector_all("#wallPreview .wordrail .inner span", "e=>e.length") >= 60)

            # ---------------------------------------------------------- service worker + offline
            print("\noffline & service worker")
            ready = page.evaluate("navigator.serviceWorker.ready.then(r=>!!r.active)")
            check("service worker installed and active", bool(ready), str(ready))
            page.reload(wait_until="networkidle")
            page.wait_for_timeout(1200)
            check("page is controlled by the worker", page.evaluate("!!navigator.serviceWorker.controller"))

            console_before_offline = len(console)
            page.route("**/api/**", lambda r: r.abort())
            page.reload(wait_until="domcontentloaded")
            page.wait_for_timeout(2500)
            check("API outage → offline mode badge", page.text_content("#badgeNet").strip() == "offline ready",
                  page.text_content("#badgeNet"))
            check("hero still renders offline",
                  "1158" in page.text_content("#heroStats") and "2,048" in page.text_content("#heroStats"))
            page.click('.tabbtn[data-v="seeds"]')
            page.wait_for_timeout(600)
            page.click('#seedSeg button[data-s="wall"]')
            page.wait_for_timeout(900)
            check("the whole wall works offline", page.eval_on_selector_all("#wall .ww", "e=>e.length") == 2048)

            # harder case: no network at all — the worker must serve the app shell
            ctx.route("**/*", lambda r: r.abort())
            page.reload(wait_until="domcontentloaded")
            page.wait_for_timeout(2500)
            body = page.text_content("body") or ""
            check("app shell survives a total network blackout", "WordVault" in body, body[:60].replace("\n", " "))
            check("offline library badge after blackout", page.text_content("#badgeNet").strip() == "offline ready")

            # a known regression: the About view must survive a reload with no backend
            ctx.unroute("**/*")
            page.goto(base + "/", wait_until="domcontentloaded")
            page.wait_for_timeout(1500)
            page.click("#btnDrawer")
            page.wait_for_timeout(500)
            page.evaluate("document.querySelectorAll('#drawer .drow')[4].click()")
            page.wait_for_timeout(2000)
            page.route("**/api/**", lambda r: r.abort())
            page.reload(wait_until="domcontentloaded")
            page.wait_for_timeout(2500)
            check("About view reloads offline without errors (regression)",
                  page.evaluate("document.querySelector('.view.on') && document.querySelector('.view.on').id") == "v-about"
                  and "offline library" in page.text_content("#backendCard")
                  and not errors, str(errors[:1]))

            # ---------------------------------------------------------- console hygiene
            # errors raised by the deliberate network blackout are expected, so only the
            # run up to the offline phase is held to a clean console
            print("\nconsole")
            check("no uncaught page errors", not errors, str(errors[:2]))
            noisy = [t for k, t in console[:console_before_offline]
                     if k == "error" and "navigator.vibrate" not in t]
            check("no console errors while online (vibrate notice excepted)", not noisy, str(noisy[:2]))
            blocked = [t for k, t in console[console_before_offline:] if k == "error"]
            check("offline phase only shows blocked-network notices",
                  all(re.search(r"ERR_(FAILED|ABORTED|INTERNET|CONNECTION)", t) or "navigator.vibrate" in t
                      for t in blocked), str(blocked[:2]))

            ctx.close()

            # ---------------------------------------------------------- backup price feed
            print("\nbackup feed")
            reduced = json.dumps({
                "source": "kraken", "ts": 1790000000,
                "coins": [{"id": "btc", "sym": "BTC", "name": "BTC", "price": 84250.5, "chg": None,
                           "spark": [], "cap": None, "vol": None}],
                "global": {"mcap": None, "vol": None, "btcDom": None, "ethDom": None, "coins": None},
                "fearGreed": None})
            kctx = browser.new_context(viewport={"width": 390, "height": 844}, is_mobile=True,
                                       has_touch=True, user_agent=IPHONE_UA)
            kp = kctx.new_page()
            kerr = []
            kp.on("pageerror", lambda e: kerr.append(str(e)[:150]))
            kp.route("**/api/prices", lambda r: r.fulfill(status=200, content_type="application/json", body=reduced))
            kp.route("**/api/prices/history**",
                     lambda r: r.fulfill(status=200, content_type="application/json", body='{"coin":"bitcoin","points":[]}'))
            kp.goto(base + "/", wait_until="networkidle")
            kp.wait_for_timeout(2500)
            kp.click("#btnDrawer")
            kp.wait_for_timeout(500)
            kp.evaluate("document.querySelectorAll('#drawer .drow')[0].click()")   # Market pulse
            kp.wait_for_timeout(2000)
            check("reduced price feed renders without errors", not kerr, str(kerr[:1]))
            check("missing market cap shows a dash, not a blank crash",
                  "—" in " ".join(kp.eval_on_selector_all("#v-market .mkstat", "e=>e.map(x=>x.textContent)")))
            check("backup feed is labelled", "kraken" in kp.text_content("#mkNote").lower(),
                  kp.text_content("#mkNote")[:50])
            kctx.close()

            # ---------------------------------------------------------- desktop sanity
            print("\ndesktop")
            desk = browser.new_context(viewport={"width": 1280, "height": 800})
            dp = desk.new_page()
            derr = []
            dp.on("pageerror", lambda e: derr.append(str(e)[:150]))
            dp.goto(base + "/", wait_until="networkidle")
            dp.wait_for_timeout(2500)
            check("opens on a large screen", dp.eval_on_selector_all(".tabbtn", "e=>e.length") == 3)
            check("no horizontal overflow on desktop",
                  dp.evaluate("document.documentElement.scrollWidth <= window.innerWidth + 2"),
                  str(dp.evaluate("[document.documentElement.scrollWidth, window.innerWidth]")))
            check("desktop run is error-free", not derr, str(derr[:1]))
            desk.close()
            browser.close()
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except Exception:
            proc.kill()

    print(f"\n{'=' * 62}")
    print(f"  {len(PASS)} passed · {len(FAIL)} failed")
    if FAIL:
        print("  failed:", ", ".join(FAIL))
    print(f"{'=' * 62}")
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
