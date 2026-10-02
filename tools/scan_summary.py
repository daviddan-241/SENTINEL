#!/usr/bin/env python3
"""Turn the sentinel CLI's JSON into a GitHub job summary.

Used by .github/workflows/scan.yml so a scan can be run from the Actions tab — no Mac, no
terminal, no install. Reads either shape the CLI emits:

  * one address  -> {"network": "...", "native": "123", ...}
  * a portfolio  -> {"reports": [...], "total_usd": "...", "failures": [...]}

Every number here came from a live provider at scan time. A value that could not be read is
printed as a dash, never as a zero.

    python3 tools/scan_summary.py report.json
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

# The exact raw values of Verification and ScanState in Core/Chain/ChainModels.swift, read from
# the source rather than guessed: an unlisted value still prints, it just gets no sentence.
VERIFICATION_NOTE = {
    "agreed": "two independent providers returned the same balance",
    "singleSource": "only one provider could answer — shown as unconfirmed",
    "disagreed": "providers differ — this address is excluded from any total",
    "unavailable": "nothing answered; absence of data is not absence of funds",
}
STATE_NOTE = {
    "funded": "holds a balance right now",
    "active": "nothing now, but the address has history",
    "empty": "the chain answered and everything is zero",
    "unused": "the chain says this address was never used",
    "invalid": "could not be derived, or the chain rejected it",
    "verifying": "providers disagree — not safe to total up",
    "unavailable": "no provider answered",
}


def money(value):
    if value in (None, "", "nil"):
        return "—"
    try:
        return "${:,.2f}".format(float(value))
    except (TypeError, ValueError):
        return str(value)


def amount(value):
    if value in (None, "", "nil"):
        return "—"
    return str(value)


def one(report, out):
    net = report.get("network") or "?"
    sym = {"ethereum": "ETH", "base": "ETH", "arbitrum": "ETH", "optimism": "ETH",
           "polygon": "POL", "gnosis": "xDAI", "bitcoin": "BTC", "solana": "SOL"}.get(net, "")
    state = report.get("state") or "?"
    verif = report.get("verification") or "?"
    out.append(f"### {net} · `{report.get('address', '?')}`\n")
    out.append("| | |")
    out.append("|---|---|")
    out.append(f"| Balance | **{amount(report.get('native_amount'))} {sym}** ({report.get('native', '—')} base units) |")
    out.append(f"| Value | {money(report.get('usd_value'))}"
               + (f" · price {money(report.get('usd_price'))}" if report.get("usd_price") else "") + " |")
    state_note = STATE_NOTE.get(state, "")
    out.append(f"| State | {state}{f' — {state_note}' if state_note else ''} |")
    note = VERIFICATION_NOTE.get(verif, "")
    out.append(f"| Verification | {verif}{f' — {note}' if note else ''} |")
    out.append(f"| Providers | {', '.join(report.get('providers') or []) or '—'} |")
    if report.get("transactions") is not None:
        out.append(f"| Transactions | {report['transactions']} |")
    if report.get("path"):
        out.append(f"| Derivation | `{report['path']}` |")
    tokens = report.get("tokens") or []
    if tokens:
        out.append("\n<details><summary>Tokens (%d)</summary>\n" % len(tokens))
        out.append("| Token | Amount |")
        out.append("|---|---|")
        for t in tokens:
            out.append(f"| {t.get('symbol', '?')} | {amount(t.get('amount'))} |")
        out.append("\n</details>")
    for f in report.get("failures") or []:
        out.append(f"\n> ⚠️ {f}")
    out.append("")


def main():
    if len(sys.argv) < 2:
        print("usage: scan_summary.py report.json", file=sys.stderr)
        return 2
    raw = Path(sys.argv[1]).read_text().strip()
    if not raw:
        print("## Scan\n\n_no output was produced_")
        return 1
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        # the CLI failed and printed prose — surface it verbatim rather than hide it
        print("## Scan failed\n\n```\n" + raw[:1500] + "\n```")
        return 1

    out: list[str] = ["## Sentinel scan\n"]
    reports = data.get("reports")
    if isinstance(reports, list):
        out.append(f"**{len(reports)} addresses** scanned."
                   + (f" Total **{money(data.get('total_usd'))}**." if data.get("total_usd") else ""))
        out.append("")
        for r in reports:
            one(r, out)
        for f in data.get("failures") or []:
            out.append(f"\n> ⚠️ {f}")
    else:
        one(data, out)

    out.append("")
    out.append("---")
    out.append("Read-only: this only reads public chain data. Sentinel has no signing code and cannot "
               "move funds. Providers are listed per address; a balance is only shown as confirmed "
               "when two independent sources agreed on it.")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
