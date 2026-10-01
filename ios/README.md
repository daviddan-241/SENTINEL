# Sentinel — iOS

The native app: a **read-only** wallet-security and portfolio tool for iPhone, written in
SwiftUI on top of a Foundation-only core package. It continues the design language of the web
build (near-black glass, violet → cyan accent, one spring curve for motion) as a real iOS app
with a real vault, real key derivation and real chain data.

No mock data anywhere. Every balance, price, transaction and token on screen was fetched from a
public blockchain provider at the moment you looked at it — or the screen says it could not be
checked. Nothing is cached behind a placeholder, and no value is invented to fill a gap.

```
SentinelWallet/            the app: design system, features, security gates, app state
Core/
  Crypto/                  BIP-39, BIP-32/44/49/84/86 derivation, Base58, Bech32, SS58, EIP-55
  Wallet/                  address classification, watch-only wallet model
  Security/                encrypted vault, lockout policy, spam filter, secure memory
  Chain/                   per-chain clients, provider agreement, portfolio scanner
Tests/SentinelWalletCoreTests/   93 tests, driven by official vectors
Tools/sentinel-cli/        the same core, as a command-line scanner
docs/                      networks · security · design · vault.json · vector provenance
```

## Running the core (any platform, no Xcode)

The core is a normal SwiftPM package with one dependency, `swift-crypto` on Linux.

```bash
cd ios
swift test                      # 93 tests — crypto, vault, spam filter, chain decoders
swift build -c release
./.build/release/sentinel scan "abandon abandon … about"      # live, real network
./.build/release/sentinel scan 0x…  --json
./.build/release/sentinel prices
```

`scripts/run-tests.sh` wraps the test run and, with an argument, runs the CLI against a live
address: `bash scripts/run-tests.sh <address>`.

CI runs this same suite on Linux on every push (job `ios-core`).

## Building the app

The Xcode project is generated, not committed — `project.yml` is the source of truth, so there
is no `.xcodeproj` to merge conflicts into.

```bash
brew install xcodegen
cd ios
xcodegen generate
open SentinelWallet.xcodeproj        # or:
xcodebuild -project SentinelWallet.xcodeproj -scheme SentinelWallet \
           -destination "platform=iOS Simulator,name=iPhone 16 Pro" build
```

Requirements: Xcode 15+, iOS 17+. The app target depends on the local package `SentinelCore`
(path `.`), and the `SentinelWallet` scheme also runs `SentinelWalletCoreTests`.

To run it on a device, set your team in `project.yml` (`settings.base.DEVELOPMENT_TEAM`) and
regenerate. Nothing else needs configuring: there is no API key, no server URL and no
third-party SDK.

### Screenshots

```bash
bash scripts/screenshots.sh          # boots a simulator, installs, screenshots each screen
```

## What it does

**Portfolio** — enter or import an address, or let the app derive every address from a phrase
you already hold in the vault. Each address is read from two independent providers; where they
agree the number is marked confirmed, and where they do not the address is marked
*verification required* and left out of the total. Totals never mix a confirmed number with a
guess.

**Scan** — a full address report: native balance, tokens with prices, recent activity,
provider-by-provider answers, block height, and a link out to the explorer on the chain's own
domain. Junk airdrops are flagged by the spam filter, shown with their reason, and excluded
from totals. The last 30 scans are kept as history — public data only.

**Wallet** — the encrypted vault. Import a BIP-39 phrase (validated against the official
2,048-word list and its checksum, with the offending word and position named), a raw private
key, or a passphrase-protected phrase. Imported material is wrapped in the vault immediately;
it is never written in the clear, logged, or sent anywhere. Revealing a phrase requires the
password and optionally Face ID, and the copy button clears the clipboard after 90 seconds.

**Drawer** — everything that is not one of the three tabs: scan history, the security page
(lock now, wipe the vault, clipboard and screenshot settings), settings (chains to scan,
activity depth, hide flagged tokens) and about.

## Security, in short

PBKDF2-HMAC-SHA512 (600,000 rounds) → AES-256-GCM, per-item wrapping, additional authenticated
data on every layer, files written atomically with complete file protection, three free unlock
attempts before a doubling lockout, clipboard auto-clear, a blur shield in the app switcher, and
no signing code at all. Full detail, including what it does **not** protect against, lives in
[docs/security.md](docs/security.md).

## Networks

Six EVM chains (Ethereum, Base, Arbitrum, OP Mainnet, Polygon, Gnosis), Bitcoin from two
independent Esplora indexers, and Solana. Providers, endpoints and the verification run are
documented in [docs/networks.md](docs/networks.md) — including the two hosts whose public
Blockscout instances redirect, and why the app talks to the redirect targets directly instead.

## What this build does **not** do

* **No signing, no sending.** It cannot move funds. There is no code path that builds a
  transaction.
* **No SPL token balances.** Enumerating Solana token accounts needs a full token-program scan;
  the app shows what it read and does not print an empty list as if it were "none".
* **No NFT gallery.** ERC-721/1155 holdings are counted and valued where the explorer prices
  them, but there is no grid view.
* **No price history or charts.** Current USD rates only — from the explorer's own rate, and
  Kraken where the explorer publishes none.
* **No server, no sync.** The vault is on this device only. Losing the password loses the
  vault; that is intentional and there is no recovery path.
* **Not audited.** The core is 93 tests over official vectors and behaves correctly against the
  live chains, but no third party has reviewed it. Do not use it as the only copy of a phrase
  that matters.

## Danger, plainly

A real recovery phrase enters this app only if you type it in. If that is not something you
want to do on a phone, do not — generate a **watch-only** address elsewhere and paste only the
address. Everything the app does to protect a phrase assumes the device itself is trustworthy.

## Tests

| Suite | What it pins down |
|---|---|
| `SentinelWalletCoreTests` | BIP-39 checksum/wordlist, BIP-32/44/49/84/86 vectors, Base58/Bech32/SS58/EIP-55 encodings, vault round-trip and tamper rejection, lockout timing, spam heuristics, and decoders run against real captured provider payloads in `Tests/…/Fixtures/`. |

`swift test` is the honest measure: **93 tests, 0 failures**. The SwiftUI layer is checked by
the Xcode build (a warning-free build is the bar) and by walking the app on a simulator with
`scripts/screenshots.sh`; it is not claimed to be test-complete, and there is no UI test target
pretending otherwise.

There is nothing to mock in the suite: the chain decoders run against the real provider
payloads captured in `Tests/SentinelWalletCoreTests/Fixtures/`, so a decoder that stops
matching what the live APIs return fails here before it reaches a screen.
