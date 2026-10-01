# Networks, providers and how they were verified

Every number the app shows comes from a public endpoint that answers **without an API key**,
because the app has no server and no place to keep a secret. Each family is read from **two
independent sources**, and the two answers are compared before anything is totalled.

Verified on 2026-10-01 from this repository's tooling; re-run `bash tools/capture_fixtures.sh`
to check them again and to refresh the fixtures the tests decode.

## EVM chains — explorer + independent node

| Chain | Explorer (Blockscout v2) | Second source (JSON-RPC) | Derivation |
|---|---|---|---|
| Ethereum | `https://eth.blockscout.com` | `https://ethereum-rpc.publicnode.com` | `m/44'/60'/0'/0/0` |
| Base | `https://base.blockscout.com` | `https://base-rpc.publicnode.com` | same address |
| Arbitrum One | `https://arbitrum.blockscout.com` | `https://arbitrum-one-rpc.publicnode.com` | same address |
| OP Mainnet | `https://explorer.optimism.io` | `https://optimism-rpc.publicnode.com` | same address |
| Polygon | `https://polygon.blockscout.com` | `https://polygon-bor-rpc.publicnode.com` | same address |
| Gnosis | `https://gnosisscan.io` | `https://gnosis-rpc.publicnode.com` | same address |

Notes from the verification run:

* `optimism.blockscout.com` and `gnosis.blockscout.com` answer with a 301 redirect; the
  canonical hosts above (`explorer.optimism.io`, `gnosisscan.io`) answer 200 directly and are
  what the app uses, so there is no redirect to follow mid-scan.
* The six EVM chains share one address by design: that is what every major wallet does with
  the `m/44'/60'` account, and the app says so in the UI instead of pretending they differ.

Endpoints used per EVM chain:

```
GET  /api/v2/addresses/{address}                 → native balance, token/log flags, USD rate
GET  /api/v2/addresses/{address}/counters        → transaction and token-transfer counts
GET  /api/v2/addresses/{address}/token-balances  → ERC-20/721/1155 holdings + reputation
GET  /api/v2/addresses/{address}/transactions    → recent activity
POST /                                        → eth_getBalance, eth_getTransactionCount
```

## Bitcoin — two independent Esplora indexers

| Provider | Host | Used for |
|---|---|---|
| mempool.space | `https://mempool.space` | balance, transactions, BTC/USD |
| blockstream.info | `https://blockstream.info` | balance, transactions (the second opinion) |

Both implement Esplora, so the same decoder reads both — but they are separate infrastructure
with separate indexes, which is what makes the comparison meaningful.

```
GET /api/address/{address}        → chain_stats + mempool_stats
GET /api/address/{address}/txs    → recent transactions (with block_time)
GET /api/v1/prices                → BTC/USD (mempool.space only)
```

## Solana — two public RPC endpoints

| Provider | Host |
|---|---|
| Solana mainnet-beta | `https://api.mainnet-beta.solana.com` |
| publicnode | `https://solana-rpc.publicnode.com` |

```
POST getBalance                 → lamports
POST getSignaturesForAddress    → recent signatures with blockTime
```

SPL token holdings are **not** claimed: enumerating them needs the token program scan
(`getTokenAccountsByOwner` across both token programs) and the app deliberately shows only
what it has actually read rather than an empty token list that looks like "none".

## Prices

* EVM chains: the explorer's own `exchange_rate` on the address payload.
* Bitcoin: mempool.space `/api/v1/prices`.
* Solana: Kraken public ticker `https://api.kraken.com/0/public/Ticker?pair=SOLUSD` — Kraken is
  also used as a cross-check when an explorer publishes no rate.
* Amounts never go through `Double`: base units are kept as decimal strings and divided with
  `Decimal`, so a 0.000000000000000001 difference cannot appear out of thin air.

## What "two sources" actually means

1. The primary provider answers.
2. The second provider is asked for the native balance.
3. If the raw base-unit strings match, the balance is **confirmed**.
4. If they differ, the primary is asked once more after a short pause — usually the explorer
   was a block behind. If it now matches, the fresher value is used and marked confirmed.
5. If it still differs, the address is marked **verification required**: it is shown to the
   user, excluded from the total, and the raw answers are kept in the report.

An address where nothing answered is marked **could not check** — silence is never treated as
an empty wallet.
