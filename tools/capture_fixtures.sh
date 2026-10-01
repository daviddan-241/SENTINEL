#!/usr/bin/env bash
# Captures the live blockchain responses the Swift tests decode, trimming each payload to a
# whitelist of fields so the fixtures stay small and readable. Every file records the URL,
# the HTTP status and the capture time in Fixtures/manifest.json.
#
#   bash tools/capture_fixtures.sh            # refresh every fixture
#
# The addresses are the public "abandon … about" BIP-39 test-vector addresses (a dusted
# address that really does hold tokens) — never a user's own wallet.
set -u
OUT="$(cd "$(dirname "$0")/.." && pwd)/ios/Tests/SentinelWalletCoreTests/Fixtures"
mkdir -p "$OUT"
EVM=0x9858EfFD232B4033E47d90003D41EC34EcaEda94
BTC_LEGACY=1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA
BTC_SEGWIT=bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu
SOL=4nFZgXtZAEwbfA56LRVRdsDGNeW3U55gr5hL9c5E5de5
USDC=0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
MANIFEST="$OUT/manifest.json"
echo "{" > "$MANIFEST"
echo "  \"captured_at\": \"$STAMP\"," >> "$MANIFEST"
echo "  \"note\": \"Live responses, trimmed to the fields the app decodes. See tools/capture_fixtures.sh.\"," >> "$MANIFEST"
echo "  \"sources\": [" >> "$MANIFEST"

capture() {                    # capture <file> <url> <python-trim-expression>
  local file="$1" url="$2" trim="$3"
  local body status
  body="$(curl -s -m 25 -w '\n%{http_code}' "$url")" || { echo "FAILED $url"; return 1; }
  status="$(printf '%s' "$body" | tail -n1)"
  printf '%s' "$body" | sed '$d' | python3 -c "$trim" > "$OUT/$file.tmp" 2>/dev/null || { echo "TRIM FAILED $url"; return 1; }
  if [ ! -s "$OUT/$file.tmp" ]; then echo "EMPTY $url"; rm -f "$OUT/$file.tmp"; return 1; fi
  mv "$OUT/$file.tmp" "$OUT/$file"
  printf '    {"file": "%s", "url": "%s", "http_status": %s, "captured_at": "%s"},\n' "$file" "$url" "$status" "$STAMP" >> "$MANIFEST"
  echo "ok  $file  ($(wc -c < "$OUT/$file") bytes, HTTP $status)"
}

KEEP3='import json,sys; d=json.load(sys.stdin)[:3]; json.dump(d, sys.stdout, indent=1)'
TRIM_ADDRESS='import json,sys; d=json.load(sys.stdin); json.dump({k: d.get(k) for k in ["hash","coin_balance","is_contract","has_tokens","has_token_transfers","has_logs","ens_domain_name","exchange_rate","implementations","creation_status"]}, sys.stdout, indent=1)'
TRIM_TXS='import json,sys
d=json.load(sys.stdin)
items = d["items"] if isinstance(d, dict) else d
xs = []
for t in items[:2]:
    xs.append({k: t.get(k) for k in ["hash","value","status","result","timestamp","from","to","method","type","created_contract"]})
    for side in ("from","to"):
        if isinstance(xs[-1].get(side), dict):
            xs[-1][side] = {"hash": xs[-1][side].get("hash"), "is_contract": xs[-1][side].get("is_contract")}
json.dump({"items": xs}, sys.stdout, indent=1)'
TRIM_BTC_TXS='import json,sys
d=json.load(sys.stdin)
xs = []
for t in d[:2]:
    xs.append({k: t.get(k) for k in ["txid","status","fee","vin","vout"]})
json.dump(xs, sys.stdout, indent=1)'
TRIM_SOL_SIGS='import json,sys
d=json.load(sys.stdin)
json.dump(d["result"][:2], sys.stdout, indent=1)'

capture evm_eth_address.json      "https://eth.blockscout.com/api/v2/addresses/$EVM"                  "$TRIM_ADDRESS"
capture evm_eth_counters.json     "https://eth.blockscout.com/api/v2/addresses/$EVM/counters"          'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1)'
capture evm_eth_token_balances.json "https://eth.blockscout.com/api/v2/addresses/$EVM/token-balances"  "$KEEP3"
capture evm_eth_transactions.json "https://eth.blockscout.com/api/v2/addresses/$EVM/transactions"      "$TRIM_TXS"
capture evm_eth_stats.json        "https://eth.blockscout.com/api/v2/stats"                            'import json,sys; d=json.load(sys.stdin); json.dump({k: d.get(k) for k in ["coin_price","coin_price_change_percentage","total_transactions","total_addresses","network_utilization_percentage"]}, sys.stdout, indent=1)'
capture evm_token_usdc.json       "https://eth.blockscout.com/api/v2/tokens/$USDC"                     'import json,sys; d=json.load(sys.stdin); json.dump({k: d.get(k) for k in ["address_hash","name","symbol","decimals","type","total_supply","holders_count","exchange_rate"]}, sys.stdout, indent=1)'
capture btc_address.json          "https://mempool.space/api/address/$BTC_LEGACY"                      'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1)'
capture btc_segwit_address.json   "https://mempool.space/api/address/$BTC_SEGWIT"                      'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1)'
capture btc_transactions.json     "https://mempool.space/api/address/$BTC_LEGACY/txs"                  "$TRIM_BTC_TXS"
capture btc_prices.json           "https://mempool.space/api/v1/prices"                                'import json,sys; d=json.load(sys.stdin); json.dump({k: d.get(k) for k in ["time","USD","EUR","GBP"]}, sys.stdout, indent=1)'
capture kraken_sol.json           "https://api.kraken.com/0/public/Ticker?pair=SOLUSD"                 'import json,sys; die=json.load(sys.stdin); json.dump({k: die[k] for k in ("error","result")}, sys.stdout, indent=1)'

# the two POST endpoints' real bodies, captured once so the tests decode a genuine shape
curl -s -m 25 -X POST https://ethereum-rpc.publicnode.com -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getBalance\",\"params\":[\"$EVM\",\"latest\"]}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); json.dump({"jsonrpc":d["jsonrpc"],"id":d["id"],"result":d["result"]}, sys.stdout, indent=1)' > "$OUT/evm_rpc_balance.json"
curl -s -m 25 -X POST https://ethereum-rpc.publicnode.com -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_getTransactionCount\",\"params\":[\"$EVM\",\"latest\"]}" \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); json.dump({"jsonrpc":d["jsonrpc"],"id":d["id"],"result":d["result"]}, sys.stdout, indent=1)' > "$OUT/evm_rpc_nonce.json"
printf '    {"file": "evm_rpc_nonce.json", "url": "https://ethereum-rpc.publicnode.com (eth_getTransactionCount, POST)", "captured_at": "%s"},\n' "$STAMP" >> "$MANIFEST"
printf '    {"file": "evm_rpc_balance.json", "url": "https://ethereum-rpc.publicnode.com (eth_getBalance, POST)", "captured_at": "%s"},\n' "$STAMP" >> "$MANIFEST"
echo "ok  evm_rpc_balance.json"

# the SPL Token program is used here only because it is a busy public account: the test
# address from the standard mnemonic has never transacted, and an empty list would not
# exercise the decoder. The balance fixture above uses the test address itself.
curl -s -m 25 -X POST https://api.mainnet-beta.solana.com -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"getSignaturesForAddress","params":["TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA",{"limit":2}]}' \
  | python3 -c 'import json,sys; d=json.load(sys.stdin); json.dump({"jsonrpc":d.get("jsonrpc"),"id":d.get("id"),"result":d.get("result",[])}, sys.stdout, indent=1)' > "$OUT/sol_signatures.json"
curl -s -m 25 -X POST https://api.mainnet-beta.solana.com -H 'content-type: application/json' \
  -d "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getBalance\",\"params\":[\"$SOL\"]}" \
  | python3 -c 'import json,sys; json.dump(json.load(sys.stdin), sys.stdout, indent=1)' > "$OUT/sol_balance.json"
printf '    {"file": "sol_signatures.json", "url": "https://api.mainnet-beta.solana.com (getSignaturesForAddress, POST)", "captured_at": "%s"},\n' "$STAMP" >> "$MANIFEST"
printf '    {"file": "sol_balance.json", "url": "https://api.mainnet-beta.solana.com (getBalance, POST)", "captured_at": "%s"},\n' "$STAMP" >> "$MANIFEST"
echo "ok  sol_signatures.json / sol_balance.json"

sed -i '$ s/,$//' "$MANIFEST"
echo "  ]" >> "$MANIFEST"
echo "}" >> "$MANIFEST"
echo "manifest written"
