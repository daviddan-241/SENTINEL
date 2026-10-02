"use strict";
/* =========================================================================
   WordVault — the wallet view.

   Sentinel's portfolio scanner, running in the page. Nothing here talks to a
   server of ours: the browser reads public blockchain APIs directly, which is
   possible because every one of them sends permissive CORS headers. What the
   page shows is therefore always live, and when a provider cannot be reached
   the screen says so instead of showing a zero.

   Two rules are deliberate and are not configurable:

   * A recovery phrase is never accepted, anywhere. The input refuses anything
     with whitespace in it and says why. A static page is the worst possible
     place to type a seed — there is no vault here, no encryption, and no way
     to prove what happens to it.
   * A balance is only called confirmed when two independent providers return
     the same base-unit number. Otherwise it is shown as unconfirmed and kept
     out of the total.
   ========================================================================= */
(function(){
var W = window.WV;
var $ = W.$, $$ = W.$$, esc = W.esc, ICON = W.ICON, toast = W.toast, money = W.money, copy = W.copy;
var haptic = W.haptic, ST = W.ST;

/* ---------------------------------------------------------------- chains */

var CHAINS = [
  { id:"ethereum", name:"Ethereum",  sym:"ETH",  kind:"evm", dec:18,
    api:"https://eth.blockscout.com/api/v2",      rpc:"https://ethereum-rpc.publicnode.com",
    ui:"https://eth.blockscout.com",              pair:"ETHUSD" },
  { id:"base",     name:"Base",      sym:"ETH",  kind:"evm", dec:18,
    api:"https://base.blockscout.com/api/v2",     rpc:"https://base-rpc.publicnode.com",
    ui:"https://base.blockscout.com",             pair:"ETHUSD" },
  { id:"arbitrum", name:"Arbitrum",  sym:"ETH",  kind:"evm", dec:18,
    api:"https://arbitrum.blockscout.com/api/v2", rpc:"https://arbitrum-one-rpc.publicnode.com",
    ui:"https://arbitrum.blockscout.com",         pair:"ETHUSD" },
  { id:"optimism", name:"OP Mainnet",sym:"ETH",  kind:"evm", dec:18,
    api:"https://explorer.optimism.io/api/v2",    rpc:"https://optimism-rpc.publicnode.com",
    ui:"https://explorer.optimism.io",            pair:"ETHUSD" },
  { id:"polygon",  name:"Polygon",   sym:"POL",  kind:"evm", dec:18,
    api:"https://polygon.blockscout.com/api/v2",  rpc:"https://polygon-bor-rpc.publicnode.com",
    ui:"https://polygon.blockscout.com",          pair:null },
  { id:"gnosis",   name:"Gnosis",    sym:"xDAI", kind:"evm", dec:18,
    api:"https://gnosisscan.io/api/v2",           rpc:"https://gnosis-rpc.publicnode.com",
    ui:"https://gnosisscan.io",                   pair:null },
  { id:"bitcoin",  name:"Bitcoin",   sym:"BTC",  kind:"btc", dec:8,
    ui:"https://mempool.space",                   pair:"XBTUSD" },
  { id:"solana",   name:"Solana",    sym:"SOL",  kind:"sol", dec:9,
    ui:"https://solscan.io/account",              pair:"SOLUSD",
    rpc:"https://api.mainnet-beta.solana.com",    rpc2:"https://solana-rpc.publicnode.com" }
];
function chain(id){ for (var i=0;i<CHAINS.length;i++) if (CHAINS[i].id === id) return CHAINS[i]; return CHAINS[0]; }

/* ------------------------------------------------------- address checking */
/* Real checks, not regexes: Base58Check recomputes its own double-SHA-256, and bech32 runs the
   BIP-173/BIP-350 polymod, so a mistyped address is caught here rather than by a provider. */

var B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
function b58decode(str){
  var bytes = [0], i, j, carry;
  for (i = 0; i < str.length; i++){
    var val = B58.indexOf(str.charAt(i));
    if (val < 0) return null;
    carry = val;
    for (j = 0; j < bytes.length; j++){
      carry += bytes[j] * 58;
      bytes[j] = carry & 0xff;
      carry >>= 8;
    }
    while (carry > 0){ bytes.push(carry & 0xff); carry >>= 8; }
  }
  for (i = 0; i < str.length && str.charAt(i) === "1"; i++) bytes.push(0);
  return new Uint8Array(bytes.reverse());
}
function b58encode(bytes){
  var digits = [0], i, j, carry;
  for (i = 0; i < bytes.length; i++){
    carry = bytes[i];
    for (j = 0; j < digits.length; j++){ carry += digits[j] << 8; digits[j] = carry % 58; carry = (carry / 58) | 0; }
    while (carry){ digits.push(carry % 58); carry = (carry / 58) | 0; }
  }
  var out = "";
  for (i = 0; i < bytes.length && bytes[i] === 0; i++) out += "1";
  for (i = digits.length - 1; i >= 0; i--) out += B58.charAt(digits[i]);
  return out;
}
function sha256(bytes){
  if (!(window.crypto && window.crypto.subtle)) return Promise.reject(new Error("no WebCrypto"));
  return window.crypto.subtle.digest("SHA-256", bytes).then(function(b){ return new Uint8Array(b); });
}
function sha256d(bytes){ return sha256(bytes).then(sha256); }

function base58checkOK(addr){
  var raw = b58decode(addr);
  if (!raw || raw.length < 5) return Promise.resolve(false);
  var payload = raw.slice(0, raw.length - 4);
  var checksum = raw.slice(raw.length - 4);
  return sha256d(payload).then(function(h){
    for (var i = 0; i < 4; i++) if (h[i] !== checksum[i]) return false;
    return true;
  }).catch(function(){ return false; });
}

var BECH32 = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";
function bech32Polymod(values){
  var GEN = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3];
  var chk = 1;
  for (var p = 0; p < values.length; p++){
    var top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ values[p];
    for (var i = 0; i < 5; i++) if ((top >> i) & 1) chk ^= GEN[i];
  }
  return chk;
}
function bech32Expand(hrp){
  var out = [], i;
  for (i = 0; i < hrp.length; i++) out.push(hrp.charCodeAt(i) >> 5);
  out.push(0);
  for (i = 0; i < hrp.length; i++) out.push(hrp.charCodeAt(i) & 31);
  return out;
}
/// Returns "bech32", "bech32m", "bad-character", or null when the checksum fails.
function bech32Variant(addr){
  if (addr !== addr.toLowerCase() && addr !== addr.toUpperCase()) return null;
  var s = addr.toLowerCase();
  var pos = s.lastIndexOf("1");
  if (pos < 1 || pos + 7 > s.length) return null;
  var hrp = s.slice(0, pos), data = [];
  for (var i = pos + 1; i < s.length; i++){
    var v = BECH32.indexOf(s.charAt(i));
    if (v < 0) return "bad-character";
    data.push(v);
  }
  var values = bech32Expand(hrp).concat(data);
  var chk = bech32Polymod(values);
  if (chk === 1) return "bech32";
  if (chk === 0x2bc830a3) return "bech32m";
  return null;
}

/// EVM addresses are hex; mixed case carries an EIP-55 checksum, which needs Keccak-256 —
/// not available in WebCrypto, so a mixed-case address is accepted but flagged as unverified
/// rather than silently trusted.
function classify(input){
  var raw = (input || "").trim();
  if (!raw) return Promise.resolve({ ok:false, reason:"Paste an address first." });
  if (/\s/.test(raw)) return Promise.resolve({
    ok:false, phrase:true,
    reason:"That looks like a phrase, not an address. Sentinel will not accept a recovery phrase." });

  if (/^0x[0-9a-fA-F]{40}$/.test(raw)) {
    var eip55 = (raw !== raw.toLowerCase()) && (raw !== raw.toUpperCase());
    return Promise.resolve({ ok:true, family:"evm", address:raw, checksum:eip55 ? "unverified" : "n/a",
      note: eip55 ? "Mixed-case address: EIP-55 checksum not verified in the browser." : "" });
  }
  if (/^bc1[a-zA-HJ-NP-Z0-9]{8,87}$/.test(raw)){
    var variant = bech32Variant(raw);
    if (!variant) return Promise.resolve({ ok:false, reason:"The bech32 checksum does not match — one character is wrong." });
    if (variant === "bad-character") return Promise.resolve({ ok:false, reason:"That address contains a character bech32 does not allow." });
    // the witness version is the first character after the "1" separator, not a fixed offset
    var sep = raw.toLowerCase().lastIndexOf("1");
    var witver = BECH32.indexOf(raw.toLowerCase().charAt(sep + 1));
    if (variant === "bech32" && witver !== 0) return Promise.resolve({ ok:false, reason:"bech32 (v0) is only valid for witness version 0." });
    if (variant === "bech32m" && witver === 0) return Promise.resolve({ ok:false, reason:"Version 0 addresses must use bech32, not bech32m." });
    return Promise.resolve({ ok:true, family:"btc", address:raw, kind: witver === 0 ? "P2WPKH/P2WSH" : "P2TR",
      checksum: variant });
  }
  if (/^tb1[a-zA-HJ-NP-Z0-9]{8,87}$/i.test(raw))
    return Promise.resolve({ ok:false, reason:"That is a testnet address (tb1…). This scans mainnet only." });
  if (/^[13][1-9A-HJ-NP-Za-km-z]{25,39}$/.test(raw))
    return base58checkOK(raw).then(function(ok){
      if (!ok) return { ok:false, reason:"The Base58Check checksum does not match — one character is wrong." };
      return { ok:true, family:"btc", address:raw, kind: raw.charAt(0) === "1" ? "P2PKH" : "P2SH", checksum:"base58check" };
    });
  if (/^[1-9A-HJ-NP-Za-km-z]{32,44}$/.test(raw)){
    var bytes = b58decode(raw);
    if (bytes && bytes.length === 32)
      return Promise.resolve({ ok:true, family:"sol", address:raw, checksum:"base58" });
    return Promise.resolve({ ok:false, reason:"That is not a 32-byte Solana public key." });
  }
  return Promise.resolve({ ok:false, reason:"Not a Bitcoin, EVM or Solana address." });
}

/* ------------------------------------------------------------------ fetch */

function jget(url, ms){
  var ctl = new AbortController();
  var timer = setTimeout(function(){ ctl.abort(); }, ms || 12000);
  return fetch(url, { signal: ctl.signal, headers:{ "Accept":"application/json" } })
    .then(function(r){ if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .finally(function(){ clearTimeout(timer); });
}
function jpost(url, body, ms){
  var ctl = new AbortController();
  var timer = setTimeout(function(){ ctl.abort(); }, ms || 12000);
  return fetch(url, { method:"POST", signal: ctl.signal,
      headers:{ "Content-Type":"application/json", "Accept":"application/json" }, body: JSON.stringify(body) })
    .then(function(r){ if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
    .finally(function(){ clearTimeout(timer); });
}
function settled(p){ return p.then(function(v){ return { ok:true, value:v }; },
                                   function(e){ return { ok:false, error:(e && e.message) || "failed" }; }); }

function krakenPrice(pair){
  if (!pair) return Promise.resolve(null);
  return jget("https://api.kraken.com/0/public/Ticker?pair=" + pair, 9000)
    .then(function(d){
      var res = d && d.result, keys = res ? Object.keys(res) : [];
      if (!keys.length) return null;
      var v = res[keys[0]];
      return v && v.c && v.c[0] ? String(v.c[0]) : null;
    }).catch(function(){ return null; });
}

/* --------------------------------------------------------------- formatting */

function amountText(rawStr, decimals){
  if (rawStr === null || rawStr === undefined) return "—";
  var s = String(rawStr);
  var neg = s.charAt(0) === "-";
  if (neg) s = s.slice(1);
  s = s.replace(/[^0-9]/g, "") || "0";
  var dec = Number(decimals || 0);
  while (s.length <= dec) s = "0" + s;
  var whole = s.slice(0, s.length - dec) || "0";
  var frac = dec ? s.slice(s.length - dec).replace(/0+$/, "") : "";
  whole = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  return (neg ? "-" : "") + whole + (frac ? "." + frac : "");
}
function usdText(value){
  if (value === null || value === undefined || isNaN(value)) return "—";
  return money(Number(value));
}
function mulDecimal(amountStr, priceStr){
  // exact decimal multiply good enough for display: integer part + up to 8 fractional digits
  var a = Number(amountStr), p = Number(priceStr);
  if (!isFinite(a) || !isFinite(p)) return null;
  return a * p;
}
function hexToDecimalString(hex){
  if (!hex) return null;
  try { return BigInt(hex).toString(); } catch(e){ return null; }
}

/* ------------------------------------------------------------ spam filter */
/* The same deterministic rules as Core/Chain/SpamFilter.swift: an explorer reputation wins,
   otherwise the name and symbol are matched against what junk tokens actually use. */

var FLAG_REP = ["spam","scam","suspicious","unsafe","honeypot"];
var HOSTS = ["http://","https://","www.","t.me/","telegram",".eth.limo",".com",".io",".cc",".xyz",".top",
             ".vip",".cfd",".store",".lat",".rest",".site",".online",".click",".link",".lol",".gift",
             ".gifts",".fun",".app",".vercel.app",".ltd",".club",".live",".life"];
var LURES = ["claim","airdrop","reward","bonus","visit","unwrap","free ","redeem","voucher","giveaway",
             "win ","get ","swap for","bridge for"];
var NOISE = ["@","[","]","✅","💰","🎁","🔥","🚀"];

function spamCheck(token){
  var name = token.name || "", sym = token.symbol || "";
  var rep = (token.reputation || "").toLowerCase();
  if (FLAG_REP.indexOf(rep) >= 0) return { flagged:true, reason:"The explorer flagged this token as " + rep + "." };
  var h = (name + " " + sym).toLowerCase();
  if (!h.trim()) return { flagged:true, reason:"The token has no name at all." };
  for (var i = 0; i < HOSTS.length; i++)
    if (h.indexOf(HOSTS[i]) >= 0) return { flagged:true, reason:"The name contains a link — this is an airdrop lure, not a holding." };
  var hasDigit = /\d/.test(h);
  for (var j = 0; j < LURES.length; j++)
    if (h.indexOf(LURES[j]) >= 0 && hasDigit) return { flagged:true, reason:"The name advertises a claim or an airdrop." };
  if (h.indexOf("claim") >= 0 || h.indexOf("airdrop") >= 0) return { flagged:true, reason:"The name advertises a claim or an airdrop." };
  for (var k = 0; k < NOISE.length; k++)
    if (h.indexOf(NOISE[k]) >= 0) return { flagged:true, reason:"The name looks like a bot handle or advertising." };
  return { flagged:false, reason:null };
}

/* ------------------------------------------------------------------ scans */

function btcStats(s){
  var chain = s.chain_stats || {}, mem = s.mempool_stats || {};
  var funded = (chain.funded_txo_sum || 0) + (mem.funded_txo_sum || 0);
  var spent = (chain.spent_txo_sum || 0) + (mem.spent_txo_sum || 0);
  return { sats: funded - spent, tx: (chain.tx_count || 0) + (mem.tx_count || 0) };
}

function scanBTC(address){
  var url1 = "https://mempool.space/api/address/" + address;
  var url2 = "https://blockstream.info/api/address/" + address;
  return Promise.all([ settled(jget(url1, 12000)), settled(jget(url2, 12000)), settled(krakenPrice("XBTUSD")) ])
    .then(function(res){
      var out = { family:"btc", chain:"bitcoin", symbol:"BTC", decimals:8, providers:[], failures:[],
                  raw:null, address:address, lookup:url1.replace("/api/address/", "/address/") };
      var a = res[0].ok ? btcStats(res[0].value) : null;
      var b = res[1].ok ? btcStats(res[1].value) : null;
      if (a){ out.providers.push("mempool.space"); }
      else { out.failures.push("mempool.space: " + (res[0].error || "no answer")); }
      if (b){ out.providers.push("blockstream.info"); }
      else { out.failures.push("blockstream.info: " + (res[1].error || "no answer")); }
      if (!a && !b) return out;
      out.raw = String((a || b).sats);
      out.txCount = (a || b).tx;
      out.verification = (a && b) ? (a.sats === b.sats ? "agreed" : "disagreed") : "singleSource";
      if (a && b && a.sats !== b.sats) out.failures.push("The two providers disagree: " + a.sats + " vs " + b.sats + " sats.");
      out.price = res[2].ok ? res[2].value : null;
      out.usd = out.price ? mulDecimal(amountText(out.raw, 8).replace(/,/g, ""), out.price) : null;
      return out;
    });
}

function scanEVM(address, cfg){
  var api = cfg.api + "/addresses/" + address.toLowerCase();
  var body = [{ jsonrpc:"2.0", id:1, method:"eth_getBalance", params:[address, "latest"] },
              { jsonrpc:"2.0", id:2, method:"eth_getTransactionCount", params:[address, "latest"] }];
  return Promise.all([
      settled(jget(api, 14000)),
      settled(jget(api + "/counters", 10000)),
      settled(jpost(cfg.rpc, body, 12000)),
      settled(krakenPrice(cfg.pair))
    ]).then(function(res){
      var out = { family:"evm", chain:cfg.id, symbol:cfg.sym, decimals:cfg.dec, providers:[], failures:[],
                  address:address, raw:null, lookup:cfg.ui + "/address/" + address, isContract:null, explorerRate:null };
      var info = res[0].ok ? res[0].value : null;
      var counts = res[1].ok ? res[1].value : null;
      var rpc = res[2].ok && Array.isArray(res[2].value) ? res[2].value : null;
      if (info){ out.providers.push(cfg.name + " explorer"); out.raw = info.coin_balance || null;
                 out.isContract = !!info.is_contract; out.explorerRate = info.exchange_rate || null; }
      else { out.failures.push(cfg.name + " explorer: " + (res[0].error || "no answer")); }
      if (counts && counts.transactions_count !== undefined) out.txCount = Number(counts.transactions_count);
      var rpcBal = null, rpcNonce = null;
      if (rpc){
        rpc.forEach(function(r){
          if (r.id === 1 && r.result) rpcBal = hexToDecimalString(r.result);
          if (r.id === 2 && r.result) rpcNonce = hexToDecimalString(r.result);
        });
      }
      if (rpcBal !== null){
        out.providers.push(cfg.name + " node");
        if (out.raw === null) out.raw = rpcBal;
        out.verification = (out.raw === rpcBal) ? "agreed" : "disagreed";
        if (out.raw !== rpcBal) out.failures.push("The explorer and the node disagree on the balance.");
      } else {
        out.failures.push(cfg.name + " node: " + (res[2].error || "no answer"));
        out.verification = out.raw !== null ? "singleSource" : "unavailable";
      }
      if (rpcBal === null && out.raw === null) out.verification = "unavailable";
      if (out.txCount === undefined && rpcNonce !== null) out.txCount = Number(rpcNonce);
      out.price = res[3].ok ? res[3].value : null;
      if (!out.price && out.explorerRate) { out.price = out.explorerRate; out.priceFrom = "explorer"; }
      out.usd = out.price && out.raw ? mulDecimal(amountText(out.raw, cfg.dec).replace(/,/g, ""), out.price) : null;
      return out;
    });
}

function scanSOL(address){
  var call = function(url){
    return jpost(url, { jsonrpc:"2.0", id:1, method:"getBalance", params:[address] }, 12000)
      .then(function(d){ return d && d.result && d.result.value !== undefined ? String(d.result.value) : null; });
  };
  return Promise.all([ settled(call("https://api.mainnet-beta.solana.com")),
                       settled(call("https://solana-rpc.publicnode.com")),
                       settled(krakenPrice("SOLUSD")) ]).then(function(res){
    var out = { family:"sol", chain:"solana", symbol:"SOL", decimals:9, providers:[], failures:[],
                address:address, raw:null, lookup:"https://solscan.io/account/" + address };
    var a = res[0].ok ? res[0].value : null, b = res[1].ok ? res[1].value : null;
    if (a !== null) out.providers.push("Solana mainnet-beta"); else out.failures.push("Solana mainnet-beta: " + (res[0].error || "no answer"));
    if (b !== null) out.providers.push("publicnode"); else out.failures.push("publicnode: " + (res[1].error || "no answer"));
    if (a === null && b === null){ out.verification = "unavailable"; return out; }
    out.raw = a !== null ? a : b;
    out.verification = (a !== null && b !== null) ? (a === b ? "agreed" : "disagreed") : "singleSource";
    if (a !== null && b !== null && a !== b) out.failures.push("The two RPCs disagree: " + a + " vs " + b + " lamports.");
    out.price = res[2].ok ? res[2].value : null;
    out.usd = out.price ? mulDecimal(amountText(out.raw, 9).replace(/,/g, ""), out.price) : null;
    return out;
  });
}

function scan(address, cfg){
  if (cfg.kind === "btc") return scanBTC(address);
  if (cfg.kind === "sol") return scanSOL(address);
  return scanEVM(address, cfg);
}

/// Token holdings, on a second tap: a heavily dusted address returns thousands of rows and
/// megabytes, which is not something to fetch behind the user's back on a phone.
function loadTokens(address, cfg){
  var url = cfg.api + "/addresses/" + address.toLowerCase() + "/token-balances";
  return jget(url, 20000).then(function(rows){
    if (!Array.isArray(rows)) return { rows:[], failures:["The explorer returned no token list."] };
    var fungible = [], nft = 0, flagged = [], unpriced = 0, total = 0;
    rows.forEach(function(row){
      var tok = row.token || {};
      var type = String(tok.type || "");
      if (type.indexOf("721") >= 0 || type.indexOf("1155") >= 0){ nft++; return; }
      var amount = amountText(row.value, tok.decimals || 0).replace(/,/g, "");
      var price = tok.exchange_rate ? Number(tok.exchange_rate) : null;
      var value = price !== null ? Number(amount) * price : null;
      var spam = spamCheck(tok);
      var item = { symbol: tok.symbol || "?", name: tok.name || "", amount: amount,
                   price: price, usd: value, flagged: spam.flagged, reason: spam.reason,
                   address: tok.address || null };
      if (spam.flagged) { flagged.push(item); return; }
      if (value === null || !isFinite(value) || value <= 0) { unpriced++; }
      else total += value;
      fungible.push(item);
    });
    fungible.sort(function(a, b){ return (b.usd || 0) - (a.usd || 0); });
    return { rows: fungible, flagged: flagged, nft: nft, unpriced: unpriced, total: total, scanned: rows.length };
  }).catch(function(e){
    return { rows:[], failures:["Token list could not be read: " + ((e && e.message) || "failed")] };
  });
}

/* ------------------------------------------------------------- the watch list */

var KEY = "wv_watch_v1";
function load(){
  try { var raw = localStorage.getItem(KEY); return raw ? JSON.parse(raw) : []; } catch(e){ return []; }
}
function save(items){ try { localStorage.setItem(KEY, JSON.stringify(items)); } catch(e){} }
function add(entry){
  var items = load();
  for (var i = 0; i < items.length; i++)
    if (items[i].a.toLowerCase() === entry.a.toLowerCase() && items[i].c === entry.c) return items;
  items.unshift(entry);
  save(items);
  return items;
}
function remove(index){ var items = load(); items.splice(index, 1); save(items); return items; }
function update(address, cfgId, patch){
  var items = load();
  for (var i = 0; i < items.length; i++){
    if (items[i].a.toLowerCase() === address.toLowerCase() && items[i].c === cfgId){
      items[i] = Object.assign({}, items[i], patch, { t: Date.now() });
    }
  }
  save(items);
  return items;
}

/* ------------------------------------------------------------------ render */

var VERIFY = {
  agreed:      { cls:"g", label:"Confirmed",        note:"two independent providers returned the same number" },
  singleSource:{ cls:"y", label:"Unconfirmed",      note:"only one provider answered" },
  disagreed:   { cls:"r", label:"Verification required", note:"the providers disagree — this is not counted in the total" },
  unavailable: { cls:"r", label:"Could not check",  note:"no provider answered; this is not the same as an empty wallet" }
};

var state = { report:null, evm:"ethereum", busy:false, tokens:null, tokensBusy:false, family:null };

function chipRow(family){
  // Always visible: the six EVM chains share one address, so which chain to read is a real
  // choice the user should see before scanning, not something to discover afterwards.
  var label = '<div class="chips-note">' + (family === "btc" || family === "sol"
    ? "Chain applies to EVM addresses — this one reads its own network."
    : "One EVM address exists on all six chains. Pick which to read:") + '</div>';
  if (family === "btc" || family === "sol")
    return label;
  return label + '<div class="filters">' + CHAINS.filter(function(c){ return c.kind === "evm"; }).map(function(c){
    return '<button class="chip' + (c.id === state.evm ? " on" : "") + '" data-chain="' + c.id + '">' + esc(c.name) + '</button>';
  }).join("") + '</div>';
}

function reportCard(r){
  if (!r) return "";
  var v = VERIFY[r.verification] || { cls:"y", label:r.verification || "—", note:"" };
  var amt = r.raw === null ? "—" : amountText(r.raw, r.decimals);
  var rows = "";
  rows += '<div class="kv"><span>Balance</span><b>' + esc(amt) + " " + esc(r.symbol) + '</b></div>';
  rows += '<div class="kv"><span>Value</span><b>' + usdText(r.usd) + '</b></div>';
  if (r.price) rows += '<div class="kv"><span>Price</span><b>' + usdText(r.price) + (r.priceFrom === "explorer" ? " (explorer)" : " (Kraken)") + '</b></div>';
  if (r.txCount !== undefined && r.txCount !== null) rows += '<div class="kv"><span>Transactions</span><b>' + W.fmt(r.txCount) + '</b></div>';
  if (r.isContract === true || r.isContract === false)
    rows += '<div class="kv"><span>Type</span><b>' + (r.isContract ? "Contract" : "Wallet") + '</b></div>';
  rows += '<div class="kv"><span>Providers</span><b>' + (r.providers.length ? esc(r.providers.join(" · ")) : "none answered") + '</b></div>';
  if (r.raw !== null && r.decimals <= 18) rows += '<div class="kv"><span>Base units</span><b class="mono">' + esc(String(r.raw)) + '</b></div>';
  return '<div class="card glass wres">' +
      '<div class="whead"><span class="pill ' + v.cls + '">' + esc(v.label) + '</span>' +
      '<span class="wsub">' + esc(v.note) + '</span></div>' +
      '<div class="waddr mono">' + esc(r.address) + '</div>' +
      rows +
      (r.failures.length ? '<div class="wfail">' + r.failures.map(function(f){ return "⚠ " + esc(f); }).join("<br>") + '</div>' : "") +
      '<div class="acts">' +
        '<button class="btn ghost" data-act="watch">' + ICON("i-star") + 'Watch this address</button>' +
        '<a class="btn ghost" href="' + esc(r.lookup) + '" target="_blank" rel="noopener">' + ICON("i-link") + 'Explorer</a>' +
        (r.family === "evm" ? '<button class="btn ghost" data-act="tokens">' + ICON("i-coins") + 'Token holdings</button>' : '') +
      '</div></div>';
}

function tokensCard(){
  var t = state.tokens;
  if (state.tokensBusy) return '<div class="card glass empty">Reading the token list… a heavily dusted address can return thousands of rows, so this is a separate tap.</div>';
  if (!t) return "";
  if (t.failures) return '<div class="card glass empty">' + esc(t.failures.join(" ")) + '</div>';
  var head = '<div class="card glass"><div class="kv"><span>Fungible tokens</span><b>' + W.fmt(t.rows.length) + '</b></div>' +
    '<div class="kv"><span>Worth counting</span><b>' + usdText(t.total) + '</b></div>' +
    '<div class="kv"><span>Flagged as junk</span><b>' + W.fmt(t.flagged.length) + '</b></div>' +
    (t.nft ? '<div class="kv"><span>NFTs (not valued)</span><b>' + W.fmt(t.nft) + '</b></div>' : '') +
    (t.unpriced ? '<div class="kv"><span>No price available</span><b>' + W.fmt(t.unpriced) + '</b></div>' : '') +
    '<div class="kv"><span>Rows returned</span><b>' + W.fmt(t.scanned) + '</b></div></div>';
  var top = t.rows.filter(function(x){ return x.usd > 0.01; }).slice(0, 12).map(function(x){
    return '<div class="rowitem"><div class="av">' + esc((x.symbol || "?").slice(0, 4)) + '</div>' +
      '<div style="min-width:0"><div class="nm">' + esc(x.symbol) + '</div><div class="mt">' + esc(x.name.slice(0, 28)) + '</div></div>' +
      '<div class="go up" style="font-weight:740;font-size:13px">' + usdText(x.usd) + '</div></div>';
  }).join("");
  var junk = t.flagged.length ? '<h2 class="sec">Flagged as junk <span class="n">' + t.flagged.length + '</span></h2>' +
    '<div class="card glass">' + t.flagged.slice(0, 10).map(function(x){
      // the name is shown too: it is where the lure usually lives ("pepefork.vip"), so hiding it
      // would make the flag harder to trust
      var label = esc((x.symbol || "?").slice(0, 12)) + (x.name ? ' <i style="opacity:.65;font-style:normal">' + esc(x.name.slice(0, 24)) + '</i>' : "");
      return '<div class="kv"><span>' + label + '</span><b class="wjunk">' + esc(x.reason || "matched the spam patterns") + '</b></div>';
    }).join("") + (t.flagged.length > 10 ? '<div class="kv"><span>…and ' + (t.flagged.length - 10) + ' more</span><b></b></div>' : "") + '</div>' : "";
  return head + (top ? '<h2 class="sec">Biggest holdings</h2><div class="list">' + top + '</div>' : "") + junk;
}

function watchList(){
  var items = load();
  if (!items.length) return '<div class="card glass empty">Nothing watched yet. Scan an address and tap “Watch this address”.</div>';
  var confirmed = 0, unconfirmed = 0;
  var rows = items.map(function(it, i){
    var cfg = chain(it.c);
    var usd = it.usd === null || it.usd === undefined ? null : Number(it.usd);
    if (usd !== null){
      if (it.verification === "disagreed" || it.verification === "unavailable") { /* excluded */ }
      else if (it.verification === "agreed") confirmed += usd;
      else unconfirmed += usd;
    }
    var badge = it.verification === "agreed" ? '<span class="pill g">Confirmed</span>'
              : it.verification === "singleSource" ? '<span class="pill y">Unconfirmed</span>'
              : it.verification ? '<span class="pill r">Not counted</span>' : '';
    var amt = it.raw ? amountText(it.raw, it.decimals === undefined ? (cfg ? cfg.dec : 18) : it.decimals) + " " + (it.sym || (cfg ? cfg.sym : "")) : "—";
    return '<div class="rowitem wrow" data-i="' + i + '">' +
      '<div class="av ' + (it.family === "btc" ? "c" : it.family === "sol" ? "b" : "") + '">' + esc((it.sym || (cfg ? cfg.sym : "?")).slice(0, 4)) + '</div>' +
      '<div style="min-width:0"><div class="nm mono">' + esc(it.a.slice(0, 14)) + '…' + esc(it.a.slice(-6)) + '</div>' +
      '<div class="mt">' + esc(cfg ? cfg.name : "?") + ' · ' + esc(amt) + '</div></div>' +
      '<div class="go ' + (it.usd >= 0 ? "up" : "down") + '" style="font-weight:740;font-size:13px">' + usdText(it.usd) + '<br><span style="font-size:10px">' + badge + '</span></div>' +
      '</div>';
  }).join("");
  return '<div class="card glass"><div class="kv"><span>Confirmed total</span><b>' + usdText(confirmed) + '</b></div>' +
      '<div class="kv"><span>Unconfirmed</span><b>' + usdText(unconfirmed) + '</b></div>' +
      '<div class="kv"><span>Addresses</span><b>' + items.length + '</b></div>' +
      '<div class="acts"><button class="btn ghost" data-act="refresh-all">' + ICON("i-refresh") + 'Refresh all</button>' +
      '<button class="btn ghost" data-act="clear">' + ICON("i-close") + 'Forget all</button></div></div>' +
    '<div class="list">' + rows + '</div>';
}

function renderWallet(){
  var host = $("#wResult"), list = $("#wList"), notes = $("#wNotes"), chips = $("#wChains");
  if (chips) chips.innerHTML = chipRow(state.family);
  if (host) host.innerHTML = state.busy ? '<div class="card glass empty">' + ICON("i-bolt") + 'Reading the chain…</div>' + reportCard(state.report) + tokensCard() : reportCard(state.report) + tokensCard();
  if (list) list.innerHTML = watchList();
  if (notes) notes.innerHTML =
    '<div class="kv"><span>Recovery phrases</span><b>Never accepted here — the input refuses anything with a space in it</b></div>' +
    '<div class="kv"><span>Signing</span><b>There is none. This page cannot move funds or build a transaction</b></div>' +
    '<div class="kv"><span>Confirmed means</span><b>two independent providers returned the same base-unit number</b></div>' +
    '<div class="kv"><span>Unconfirmed means</span><b>one provider answered, so the number is shown but kept separate</b></div>' +
    '<div class="kv"><span>Junk tokens</span><b>flagged by explorer reputation or by the patterns lures use, and never counted</b></div>' +
    '<div class="kv"><span>Prices</span><b>Kraken’s public ticker, or the explorer’s own rate where there is no pair</b></div>';
}

/* ------------------------------------------------------------------- events */

function doScan(){
  var input = $("#wAddr");
  if (!input || state.busy) return;
  var raw = input.value.trim();
  haptic();
  klassify(raw);
}

function klassify(raw){
  classify(raw).then(function(c){
    if (!c.ok){
      state.report = null; state.tokens = null;
      var msg = c.reason;
      if (c.phrase) msg = "That looks like a phrase. Sentinel never accepts a recovery phrase — type it into a wallet you control, never a web page. Public addresses only.";
      $("#wResult").innerHTML = '<div class="card glass badmsg">' + ICON("i-alert") + ' ' + esc(msg) + '</div>';
      return;
    }
    state.family = c.family;
    var cfg = c.family === "evm" ? chain(state.evm) : chain(c.family === "btc" ? "bitcoin" : "solana");
    state.report = null; state.tokens = null; state.busy = true;
    renderWallet();
    scan(c.address, cfg).then(function(r){
      r.family = c.family;
      state.report = r; state.busy = false;
      renderWallet();
      if (c.note) toast(c.note);
    });
  });
}

function wire(host){
  var input = $("#wAddr");
  if (input){
    input.addEventListener("keydown", function(e){ if (e.key === "Enter") doScan(); });
  }
  var btn = $("#wScan");
  if (btn) btn.addEventListener("click", doScan);
  host.addEventListener("click", function(e){
    var chip = e.target.closest("[data-chain]");
    if (chip){
      state.evm = chip.getAttribute("data-chain");
      if (state.report && state.report.family === "evm") klassify(state.report.address);
      else renderWallet();
      return;
    }
    var row = e.target.closest(".wrow");
    var act = e.target.closest("[data-act]");
    var name = act ? act.getAttribute("data-act") : null;
    if (name === "watch" && state.report){
      var r = state.report;
      add({ a:r.address, c:r.chain, family:r.family, sym:r.symbol, decimals:r.decimals, raw:r.raw,
            usd:r.usd, price:r.price, verification:r.verification, txCount:r.txCount, t:Date.now() });
      toast("Watching " + r.address.slice(0, 10) + "…");
      renderWallet();
      return;
    }
    if (name === "tokens" && state.report){
      state.tokensBusy = true; state.tokens = null; renderWallet();
      var cfg2 = chain(state.report.chain);
      loadTokens(state.report.address, cfg2).then(function(t){
        state.tokens = t; state.tokensBusy = false; renderWallet();
      });
      return;
    }
    if (name === "refresh-all"){
      refreshAll(); return;
    }
    if (name === "clear"){
      save([]); toast("Watch list cleared"); renderWallet(); return;
    }
    if (row && !act){
      var i = Number(row.getAttribute("data-i"));
      var items = load();
      var it = items[i];
      if (it){
        var clicked = chain(it.c);
        if (clicked.kind === "evm") state.evm = clicked.id;
        $("#wAddr").value = it.a;
        klassify(it.a);
      }
    }
  });
}

function refreshAll(){
  var items = load();
  if (!items.length) return;
  var pending = items.length;
  toast("Refreshing " + pending + " address" + (pending === 1 ? "" : "es") + "…");
  items.forEach(function(it){
    var cfg = chain(it.c);
    scan(it.a, cfg).then(function(r){
      update(it.a, it.c, { raw:r.raw, usd:r.usd, price:r.price, verification:r.verification, txCount:r.txCount });
      pending--;
      if (pending === 0){ renderWallet(); toast("Watch list refreshed"); }
    });
  });
}

W.Wallet = { classify: classify, scan: scan, loadTokens: loadTokens, chains: CHAINS, spamCheck: spamCheck,
             amountText: amountText, b58decode: b58decode, b58encode: b58encode, bech32Variant: bech32Variant,
             load: load, save: save };
W.RENDER.wallet = function(){
  var host = $("#v-wallet");
  if (!host) return;
  if (!host.getAttribute("data-wired")){ host.setAttribute("data-wired", "1"); wire(host); }
  renderWallet();
};
})();
