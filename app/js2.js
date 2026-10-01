"use strict";
/* =========================================================================
   WordVault v2 — seeds trainer, live market, pulse, vault, safety, about
   ========================================================================= */
(function(){
var W = window.WV;
var $ = W.$, $$ = W.$$, esc = W.esc, ICON = W.ICON, ST = W.ST, save = W.save, haptic = W.haptic;
var toast = W.toast, copy = W.copy, shuffle = W.shuffle, fmt = W.fmt, money = W.money;
var Net = W.Net, BIP = W.BIP, SEEDS = W.SEEDS, TERMS = W.TERMS, QUOTES = W.QUOTES, RULES = W.RULES;
var BY_LOWER = W.BY_LOWER, SEED_BY_WORD = W.SEED_BY_WORD;

/* =====================================================================
   SEEDS
   ===================================================================== */
var seedQ = "", seedShown = 240, flashOrder = [], flashI = 0, flashBack = false, quiz = null, qmode = "real", phrase = null;

function renderSeeds(){
  $$("#seedSeg button").forEach(function(b){ b.classList.toggle("on", b.dataset.s === ST.seedTab); });
  paneSeed();
}
$$("#seedSeg button").forEach(function(b){
  b.addEventListener("click", function(){
    ST.seedTab = b.dataset.s; save(); flashBack = false;
    $$("#seedSeg button").forEach(function(x){ x.classList.toggle("on", x === b); });
    paneSeed(); haptic();
  });
});
$("#seedToCheck").addEventListener("click", function(){ ST.seedTab = "check"; save(); gotoSeeds(); });
$("#seedToCards").addEventListener("click", function(){ ST.seedTab = "flash"; save(); gotoSeeds(); });
function gotoSeeds(){ W.rendered.seeds = 0; W.go("seeds"); }
function paneSeed(){
  var p = ST.seedTab;
  if(p === "flash") return paneFlash();
  if(p === "quiz") return paneQuiz();
  if(p === "phrase") return panePhrase();
  if(p === "check") return paneCheck();
  if(p === "wall") return (W.paneWall ? W.paneWall() : paneList());
  paneList();
}
/* ---- list ---- */
function paneList(){
  var q = seedQ.trim().toLowerCase();
  var ids = [];
  for(var i=0;i<2048;i++){ if(!q || SEEDS[i].w.indexOf(q) >= 0) ids.push(i); }
  var html = '<div class="search" style="position:static;margin-top:6px">'+ICON("i-search")+
    '<input id="sq" type="search" placeholder="Search the 2,048 seed words…" value="'+esc(seedQ)+'" autocapitalize="off" autocorrect="off" spellcheck="false">'+
    '<button class="clr'+(seedQ?"":"")+'" id="sqClear">✕</button></div>'+
    '<div class="filters" style="padding-top:10px">'+
      '<span class="s" style="pointer-events:none">'+ICON("i-check")+ST.known.length+' learned</span>'+
      '<span class="s" style="pointer-events:none">'+ICON("i-book")+ids.length+' shown</span>'+
      '<span class="s" style="pointer-events:none">'+ICON("i-sparkles")+window.__VAULT__.stats.seedDefs+' defined</span>'+
    '</div>'+
    '<div class="wordgrid" id="wgrid"></div>'+
    (ids.length > seedShown ? '<div class="acts"><button class="btn pri" id="sMore">Show more ('+(ids.length-seedShown)+' left)</button></div>' : '');
  $("#seedPane").innerHTML = html;
  var grid = "";
  for(var k=0;k<ids.length && k<seedShown;k++){
    var s = SEEDS[ids[k]], kn = ST.known.indexOf(s.i) >= 0;
    grid += '<div class="wcell'+(kn?" known":"")+(s.t?" linked":"")+' ripple" data-fill-seed="'+s.i+'"><b>'+esc(s.w)+'</b><span>#'+(s.i+1)+'</span>'+(s.t?'<em>defined</em>':'')+'</div>';
  }
  $("#wgrid").innerHTML = grid;
  var sq = $("#sq");
  sq.addEventListener("input", function(){
    seedQ = this.value; seedShown = 240; var pos = this.selectionStart;
    paneList(); var n = $("#sq"); n.focus(); try{ n.setSelectionRange(pos,pos); }catch(e){}
  });
  $("#sqClear").addEventListener("click", function(){ seedQ = ""; seedShown = 240; paneList(); });
  var sm = $("#sMore"); if(sm) sm.addEventListener("click", function(){ seedShown += 240; paneList(); });
}
/* ---- flashcards ---- */
function paneFlash(){
  if(!flashOrder.length){ flashOrder = SEEDS.map(function(s){ return s.i; }); shuffle(flashOrder); }
  var s = SEEDS[flashOrder[flashI % 2048]], t = BY_LOWER[s.w], kn = ST.known.indexOf(s.i) >= 0;
  var body = flashBack
    ? (t ? '<div class="back">'+esc(t.d)+'</div>'+(t.e?'<div class="hint" style="font-style:italic">'+esc(t.e)+'</div>':'')
         : '<div class="back">No crypto-jargon meaning — purely a recognition and spelling word.</div>'+
           '<div class="hint">'+s.w.length+' letters · neighbours: '+(s.i>0?esc(SEEDS[s.i-1].w):"—")+' / '+(s.i<2047?esc(SEEDS[s.i+1].w):"—")+'</div>')
    : '<div class="hint">BIP-39 word #'+(s.i+1)+' of 2,048</div>';
  $("#seedPane").innerHTML =
    '<div class="card glass"><div style="display:flex;align-items:center;gap:9px"><span class="pill">Flashcards</span>'+
    '<span style="margin-left:auto;font-size:11.5px;color:var(--muted)">'+(flashI+1)+' / 2,048 · '+ST.known.length+' learned</span></div>'+
    '<div class="flash" id="flashCard"><div class="w">'+esc(s.w)+'</div>'+body+
      '<div class="hint" style="color:var(--muted-2)">tap the card to flip</div></div>'+
    '<div class="acts"><button class="btn" id="fPrev">← Prev</button>'+
    '<button class="btn '+(kn?"ok":"")+'" id="fKnow">'+ICON("i-check")+(kn?"Learned":"Got it")+'</button>'+
    '<button class="btn pri" id="fNext">Next →</button></div>'+
    '<div class="prog"><i style="width:'+(ST.known.length/2048*100)+'%"></i></div></div>';
  $("#flashCard").addEventListener("click", function(){ flashBack = !flashBack; paneFlash(); haptic(7); });
  $("#fNext").addEventListener("click", function(){ flashBack = false; flashI = (flashI+1)%2048; paneFlash(); haptic(); });
  $("#fPrev").addEventListener("click", function(){ flashBack = false; flashI = (flashI+2047)%2048; paneFlash(); haptic(); });
  $("#fKnow").addEventListener("click", function(){
    var j = ST.known.indexOf(s.i);
    if(j < 0){ ST.known.push(s.i); toast("Learned · "+ST.known.length+"/2048", "i-check"); haptic(14); Net.event("seed_learned"); }
    else { ST.known.splice(j,1); haptic(); }
    save(); flashBack = false; flashI = (flashI+1)%2048; paneFlash(); W.buildDrawer();
  });
}
/* ---- quiz ---- */
function fakeWord(){
  var w = SEEDS[Math.floor(Math.random()*2048)].w;
  var ops = [
    function(x){ var i=1+Math.floor(Math.random()*(x.length-1)); return x.slice(0,i)+x[i-1]+x.slice(i); },
    function(x){ var i=x.search(/[aeiou]/); if(i<0) return x+"e"; var v="aeiou", n=v[v.indexOf(x[i])===0?1:Math.max(0,v.indexOf(x[i])-1)]; return x.slice(0,i)+n+x.slice(i+1); },
    function(x){ return x.slice(0,-1)+x[x.length-1]+x[x.length-1]; },
    function(x){ return x.slice(0,1)+"l"+x.slice(2); },
    function(x){ return x.slice(0,-2)+x[x.length-1]+x[x.length-2]; }
  ];
  for(var k=0;k<10;k++){
    var c = ops[Math.floor(Math.random()*ops.length)](w);
    if(c !== w && !SEED_BY_WORD[c]) return c;
  }
  return w+"s";
}
function linked(){ return SEEDS.filter(function(s){ return s.t; }); }
function newQuiz(){
  var q = { score:(quiz && quiz.score)||0, miss:(quiz && quiz.miss)||0, answered:false };
  if(qmode === "def"){
    var pool = linked(), s = pool[Math.floor(Math.random()*pool.length)];
    var t = BY_LOWER[s.w], others = shuffle(pool.filter(function(x){ return x.i !== s.i; })).slice(0,3);
    var opts = shuffle([s.w].concat(others.map(function(o){ return o.w; })));
    q.answer = s.w;
    q.html = '<div class="qcard glass"><div class="q">'+esc(t.d)+'</div>';
    opts.forEach(function(w){ q.html += '<button class="opt ripple" data-w="'+esc(w)+'">'+esc(w)+'</button>'; });
  } else {
    var real = SEEDS[Math.floor(Math.random()*2048)].w;
    var opts2 = shuffle([real, fakeWord(), fakeWord(), fakeWord()]);
    q.answer = real;
    q.html = '<div class="qcard glass"><div class="q" style="margin-bottom:4px">Which one is a real BIP-39 seed word?</div>'+
      '<div style="font-size:12.3px;color:var(--muted);margin-bottom:12px">The fakes are deliberate misspellings — a wallet rejects anything outside the exact 2,048-word list.</div>';
    opts2.forEach(function(w){ q.html += '<button class="opt ripple" data-w="'+esc(w)+'">'+esc(w)+'</button>'; });
  }
  q.html += '</div><div class="acts"><button class="btn pri" id="qNext">'+ICON("i-right")+'Next question</button></div>';
  return q;
}
function paneQuiz(){
  quiz = quiz || newQuiz();
  $("#seedPane").innerHTML =
    '<div class="seg"><button class="'+(qmode==="real"?"on":"")+'" data-qm="real">Real word?</button>'+
    '<button class="'+(qmode==="def"?"on":"")+'" data-qm="def">From definition</button></div>'+
    '<div style="display:flex;align-items:center;gap:9px;margin-bottom:9px"><span class="pill g">'+quiz.score+' right</span><span class="pill r">'+quiz.miss+' wrong</span>'+
    '<span style="margin-left:auto;font-size:11.5px;color:var(--muted)">'+(Net.online?"server-backed":"offline")+'</span></div>'+ quiz.html;
  $$("#seedPane [data-qm]").forEach(function(b){ b.addEventListener("click", function(){ qmode = b.dataset.qm; quiz = null; paneQuiz(); haptic(); }); });
  var ans = quiz.answered;
  $$("#seedPane .opt[data-w]").forEach(function(b){
    if(ans && b.dataset.w === quiz.answer) b.classList.add("right");
    b.addEventListener("click", function(){
      if(quiz.answered) return; quiz.answered = true;
      var ok = b.dataset.w === quiz.answer;
      b.classList.add(ok ? "right" : "wrong");
      $$("#seedPane .opt[data-w]").forEach(function(bb){ if(bb.dataset.w === quiz.answer) bb.classList.add("right"); });
      if(ok){ quiz.score++; ST.quizR++; Net.event("quiz_correct"); if(W.burst) W.burst(b); } else { quiz.miss++; ST.quizW++; Net.event("quiz_wrong"); }
      var s = SEED_BY_WORD[quiz.answer];
      if(ok && s && ST.known.indexOf(s.i) < 0) ST.known.push(s.i);
      save(); haptic(ok?14:[10,40,10]); W.buildDrawer();
      setTimeout(function(){ quiz = newQuiz(); quiz.score = quiz.score; paneQuiz(); }, ok ? 700 : 1400);
    });
  });
  $("#qNext").addEventListener("click", function(){ quiz = newQuiz(); paneQuiz(); haptic(); });
}
/* ---- phrase builder ---- */
function newPhrasePack(words){
  var bank = shuffle(words.slice()).map(function(w){ return {w:w, used:false}; });
  return { order:words, picked:new Array(words.length).fill(null), bank:bank };
}
function panePhrase(){
  if(!phrase){ $("#seedPane").innerHTML = '<div class="coingrid"><div class="skel"></div><div class="skel"></div></div>'; loadPhrase(); return; }
  var slots = phrase.picked.map(function(w,i){
    return '<div class="slot'+(w?" f":"")+'" data-slot="'+i+'">'+(w?esc(w):(i+1))+'</div>'; }).join("");
  var bank = phrase.bank.map(function(b){ return '<button class="b'+(b.used?" used":"")+'" data-b="'+esc(b.w)+'">'+esc(b.w)+'</button>'; }).join("");
  $("#seedPane").innerHTML =
    '<div class="warn">'+ICON("i-alert")+'<span><b>Practice words — valid maths, zero funds.</b> These phrases pass the real BIP-39 checksum'+(Net.online?' (generated by the backend)':' (generated offline in this page)')+', which is exactly why you must never adopt a phrase from any app or website, including this one.</span></div>'+
    '<div class="card glass" style="margin-top:12px"><div style="display:flex;align-items:center;gap:9px"><span class="pill">Build the phrase</span><span style="margin-left:auto;font-size:11.5px;color:var(--muted)">tap words in order</span></div>'+
    '<div class="slotwrap">'+slots+'</div><div class="bank">'+bank+'</div>'+
    '<div class="acts"><button class="btn" id="pUndo">Undo</button><button class="btn" id="pCheck">'+ICON("i-check")+'Check order</button><button class="btn pri" id="pNew">'+ICON("i-refresh")+'New phrase</button></div>'+
    '<div id="pMsg" style="margin-top:11px;font-size:13.2px;color:var(--muted)"></div></div>';
  $$("#seedPane .b").forEach(function(b){
    b.addEventListener("click", function(){
      var w = b.dataset.b, idx = phrase.picked.indexOf(null);
      if(idx < 0) return;
      phrase.picked[idx] = w;
      phrase.bank.filter(function(x){ return x.w === w; })[0].used = true;
      haptic(); panePhrase();
    });
  });
  $("#pUndo").addEventListener("click", function(){
    for(var i=phrase.picked.length-1;i>=0;i--){
      if(phrase.picked[i]){ var w = phrase.picked[i]; phrase.picked[i] = null;
        phrase.bank.filter(function(x){ return x.w === w && x.used; })[0].used = false; break; }
    }
    haptic(); panePhrase();
  });
  $("#pCheck").addEventListener("click", function(){
    var got = phrase.picked.filter(Boolean).length;
    if(got < phrase.picked.length){ $("#pMsg").innerHTML = '<b style="color:#fde68a">'+got+' of '+phrase.picked.length+' filled.</b> Keep going.'; return; }
    if(phrase.picked.every(function(w,i){ return w === phrase.order[i]; })){
      phrase.order.forEach(function(w){ var s = SEED_BY_WORD[w]; if(s && ST.known.indexOf(s.i) < 0) ST.known.push(s.i); });
      save(); W.buildDrawer();
      $("#pMsg").innerHTML = '<b style="color:#86efac">Correct order.</b> It passes the real checksum — the Check tab can verify the maths for you.';
      haptic(16); Net.event("phrase_solved");
    } else {
      $("#pMsg").innerHTML = '<b style="color:#fca5a5">Not the right order.</b> Wallets rebuild the exact phrase in sequence — position matters as much as the words.';
      haptic([10,40,10]);
    }
  });
  $("#pNew").addEventListener("click", function(){ phrase = null; panePhrase(); haptic(); });
}
async function loadPhrase(){
  var words = await Net.makePhrase(12);
  phrase = newPhrasePack(words);
  panePhrase();
}
/* ---- checker ---- */
function paneCheck(){
  $("#seedPane").innerHTML =
    '<div class="warn">'+ICON("i-lock")+'<span><b>'+(Net.online?'Validated by the backend (FTS + SHA-256), and never stored.':'100% offline maths — SHA-256 runs inside this page.')+'</b> Only check a phrase you wrote down from your own wallet. Never type one that a website, DM, email or “support agent” gave you.</span></div>'+
    '<div class="card glass" style="margin-top:12px"><div style="display:flex;align-items:center;gap:9px"><span class="pill c">BIP-39 checker</span><span id="cw" style="margin-left:auto;font-size:11.5px;color:var(--muted)">0 words</span></div>'+
    '<div style="font-size:13px;color:var(--muted);margin:10px 0 9px">12, 15, 18, 21 or 24 words. Every word is checked against the official list, then the checksum is recomputed.</div>'+
    '<textarea class="big" id="ptext" autocapitalize="off" autocorrect="off" spellcheck="false" placeholder="word word word …"></textarea>'+
    '<div id="pout" style="margin-top:12px"></div>'+
    '<div class="acts"><button class="btn pri" id="pgo">'+ICON("i-shield")+'Check phrase</button>'+
    '<button class="btn" id="psample">'+ICON("i-dice")+'Practice phrase</button>'+
    '<button class="btn" id="pclear">Clear</button></div></div>';
  var ta = $("#ptext");
  ta.addEventListener("input", function(){
    var n = this.value.trim().split(/[\s,;]+/).filter(Boolean).length;
    $("#cw").textContent = n + " word" + (n===1?"":"s");
  });
  $("#pgo").addEventListener("click", async function(){
    $("#pout").innerHTML = '<div class="skel" style="height:52px"></div>';
    showCheck(await Net.validate(ta.value));
  });
  $("#psample").addEventListener("click", async function(){
    var p = await Net.makePhrase(12);
    ta.value = p.join(" "); $("#cw").textContent = "12 words";
    showCheck(await Net.validate(p.join(" ")));
    haptic(14);
  });
  $("#pclear").addEventListener("click", function(){ ta.value = ""; $("#cw").textContent = "0 words"; $("#pout").innerHTML = ""; });
}
function showCheck(r){
  var good = r.state === "good", empty = r.state === "empty";
  var cls = good ? "okmsg" : (empty ? "" : "badmsg");
  var html = '<div class="warn '+(good?"okmsg":(empty?"":(r.state==="sum"?"":"badmsg")))+'">'+
    ICON(good?"i-check":(empty?"i-info":"i-alert"))+'<span>'+esc(r.msg)+'</span></div>';
  if(r.words) html += '<div class="bank" style="margin-top:12px">'+r.words.map(function(w){
    var ok = !!SEED_BY_WORD[w];
    return '<span class="b" style="pointer-events:none;'+(ok?"":"opacity:.6;border-color:rgba(251,113,133,.6);color:#fecdd3")+'">'+esc(w)+'</span>';
  }).join("")+'</div>';
  if(good) html += '<div style="font-size:12.5px;color:var(--muted);margin-top:11px">Structural check only: it proves the words and checksum are correct, not that the wallet is empty or safe. Never import a phrase you did not generate yourself.</div>';
  $("#pout").innerHTML = html;
}

/* =====================================================================
   MARKET
   ===================================================================== */
var COIN_TERMS = {
  bitcoin:["Bitcoin","Halving","Satoshi","Ordinals","Lightning Network","ETF"],
  ethereum:["Ethereum","The Merge","Gas","EIP-1559","Restaking","Layer 2"],
  solana:["Solana","Proof of History","Jito","Priority Fee (Solana)","SPL Token","Firedancer"],
  binancecoin:["BNB","Binance","BEP-20","CZ","Launchpad"],
  ripple:["XRP","Ripple","Destination Tag","RippleNet","SEC"],
  cardano:["Cardano","Proof of Stake","Epoch","Validator"],
  dogecoin:["Dogecoin","Memecoin","Elon Musk","Shiba Inu"],
  tron:["TRC-20","USDT","Tether"],
  chainlink:["Chainlink","Oracle","Price Feed","CCIP"],
  avalanche:["Avalanche","Subnet","Validator"],
  polkadot:["Polkadot","Parachain","Substrate","Gavin Wood"],
  litecoin:["Litecoin","SegWit","ASIC"]
};
function renderMarket(){
  $("#mkStats").innerHTML = skelStats();
  renderMarketData();
  if(!Net.online){
    $("#mkStats").innerHTML = '<div class="empty">The market view needs the WordVault backend.<br>Everything else in the app works offline.</div>';
    $("#coinGrid").innerHTML = ""; $("#movers").innerHTML = ""; $("#ggWrap").innerHTML = "";
  }
}
function skelStats(){
  return '<div class="skel"></div><div class="skel"></div><div class="skel"></div><div class="skel"></div>';
}
async function renderMarketData(force){
  if(!Net.online) return;
  if(!Net.prices) $("#mkStats").innerHTML = skelStats();
  var d = await Net.loadPrices(force);
  if(!d || !d.coins.length){
    $("#mkStats").innerHTML = '<div class="empty">Market data could not be reached. Try Refresh in a moment.</div>';
    return;
  }
  var g = d.global || {};
  $("#mkStats").innerHTML =
    '<div class="mkstat"><span>Total market cap</span><b>'+money(g.mcap)+'</b></div>'+
    '<div class="mkstat"><span>24h volume</span><b>'+money(g.vol)+'</b></div>'+
    '<div class="mkstat"><span>BTC dominance</span><b>'+(g.btcDom?g.btcDom+"%":"—")+'</b></div>'+
    '<div class="mkstat"><span>Tracked assets</span><b>'+(g.coins?fmt(g.coins):d.coins.length)+'</b></div>';
  $("#ggWrap").innerHTML = d.fearGreed ? gauge(d.fearGreed) : "";
  $("#coinGrid").innerHTML = d.coins.map(W.coinCard).join("");
  $("#mkCount").textContent = d.source === "kraken" ? "kraken fallback" : "coingecko";
  var note = $("#mkNote");
  if(note) note.innerHTML = d.source === "kraken" ? (
    '<div class="card glass" style="padding:11px 13px;font-size:12.6px;color:#c9d1e6;line-height:1.5">' +
    ICON("i-bolt") + ' <b style="color:#fde68a">Backup feed.</b> Prices come straight from Kraken. Market cap, ' +
    'dominance and the 7-day sparklines need CoinGecko, which is rate-limiting right now — the app keeps the last ' +
    'good values instead of blanking the screen.</div>') : "";
  var sorted = d.coins.filter(function(c){ return c.chg !== null && c.chg !== undefined; });
  sorted.sort(function(a,b){ return Math.abs(b.chg) - Math.abs(a.chg); });
  $("#movers").innerHTML = sorted.slice(0,6).map(function(c){
    var up = c.chg >= 0;
    return '<div class="rowitem ripple" data-coin="'+esc(c.id)+'"><div class="av '+(up?"c":"b")+'">'+esc(c.sym.slice(0,4))+'</div>'+
      '<div style="min-width:0"><div class="nm">'+esc(c.name)+'</div><div class="mt">'+money(c.price)+' · vol '+money(c.vol)+'</div></div>'+
      '<div class="go '+(up?"up":"down")+'" style="font-weight:740;font-size:13.5px">'+ICON(up?"i-trend-up":"i-trend-down")+(up?"+":"")+c.chg.toFixed(2)+'%</div></div>';
  }).join("");
  $("#mktAsOf").textContent = "updated " + W.when(d.ts);
  $("#tickBadge").textContent = d.source === "kraken" ? "kraken" : "live";
  buildTicker(d.coins);
  if(ST.view === "home") W.refreshHomeMarket();
}
function gauge(fg){
  var v = Math.max(0, Math.min(100, fg.value));
  var C = 2*Math.PI*29, off = C*(1 - v/100);
  var col = v < 25 ? "#fb7185" : v < 45 ? "#fbbf24" : v < 60 ? "#a78bfa" : v < 80 ? "#34d399" : "#22d3ee";
  return '<div class="gg"><div class="gauge"><svg width="74" height="74"><circle cx="37" cy="37" r="29" stroke="rgba(255,255,255,.12)" stroke-width="7" fill="none"/>'+
    '<circle cx="37" cy="37" r="29" stroke="'+col+'" stroke-width="7" fill="none" stroke-linecap="round" stroke-dasharray="'+C+'" stroke-dashoffset="'+off+'" transform="rotate(-90 37 37)"/></svg><b>'+v+'</b></div>'+
    '<div><div style="font-size:15px;font-weight:690">Fear &amp; Greed Index · '+esc(fg.label)+'</div>'+
    '<div style="font-size:12.3px;color:var(--muted);margin-top:4px">A 0–100 sentiment gauge. Extreme greed has historically been a warning; extreme fear a contrarian signal.</div></div></div>';
}
function buildTicker(coins){
  if(!coins || !coins.length || !ST.live){ $("#tickerWrap").hidden = true; return; }
  var items = coins.map(function(c){
    var up = (c.chg || 0) >= 0;
    return '<span class="tick"><span class="sym">'+esc(c.sym)+'</span><b>'+money(c.price)+'</b>'+
      '<span class="'+(up?"up":"down")+'">'+(c.chg===null||c.chg===undefined?"":(up?"▲":"▼")+Math.abs(c.chg).toFixed(2)+"%")+'</span></span>';
  }).join("");
  $("#tickRail").innerHTML = items + items;
  $("#tickerWrap").hidden = false;
}
$("#ticker").addEventListener("click", function(){ this.classList.toggle("paused"); haptic(6); });
$("#mkRefresh").addEventListener("click", function(){ renderMarketData(true); toast("Refreshing market data…", "i-refresh"); });
document.addEventListener("click", function(e){
  var el = e.target.closest && e.target.closest("[data-coin]");
  if(!el) return;
  openCoin(el.getAttribute("data-coin"));
});
async function openCoin(id){
  var d = Net.prices, c = d && d.coins.filter(function(x){ return x.id === id; })[0];
  if(!c) return;
  var rel = COIN_TERMS[id] || [];
  var termChips = rel.map(function(n){
    var t = BY_LOWER[n.toLowerCase()];
    return t ? '<button class="b" data-open-term="'+esc(t.n)+'">'+esc(t.n)+'</button>'
             : '<span class="b" style="pointer-events:none;opacity:.6">'+esc(n)+'</span>';
  }).join("");
  open2('<h3>'+esc(c.name)+' <span style="font-size:14px;color:var(--muted)">'+esc(c.sym)+'</span></h3>'+
    '<div class="cat"><span class="pill '+(c.chg>=0?"g":"r")+'">'+(c.chg===null?"—":(c.chg>=0?"+":"")+c.chg.toFixed(2)+"% 24h")+'</span>'+
    '<span class="pill n">'+money(c.price)+'</span></div>'+
    '<div id="coinChart" style="margin-top:14px"><div class="skel" style="height:96px"></div></div>'+
    '<div class="card glass" style="margin-top:12px"><div class="kv"><span>Market cap</span><b>'+money(c.cap)+'</b></div>'+
    '<div class="kv"><span>24h volume</span><b>'+money(c.vol)+'</b></div>'+
    '<div class="kv"><span>Source</span><b>'+esc(Net.prices.source||"coingecko")+'</b></div>'+
    '<div class="kv"><span>Updated</span><b>'+W.when(Net.prices.ts)+'</b></div></div>'+
    (termChips?'<div style="font-size:10.5px;color:var(--muted-2);text-transform:uppercase;letter-spacing:.08em;margin:16px 0 6px">Learn the words behind it</div><div class="bank">'+termChips+'</div>':'')+
    '<div class="acts"><button class="btn pri" data-close="1">Done</button></div>');
  try{
    var h = await Net.req("GET", "/api/prices/history?coin="+encodeURIComponent(id)+"&days=1", null, 9000);
    if(h && h.points && h.points.length > 4){
      var min = Math.min.apply(null,h.points), max = Math.max.apply(null,h.points), r = (max-min)||1;
      var pts = h.points.map(function(v,i){ return (i/(h.points.length-1)*100).toFixed(2)+","+(38-((v-min)/r)*34).toFixed(2); }).join(" ");
      var up = h.points[h.points.length-1] >= h.points[0];
      $("#coinChart").innerHTML = '<div class="card glass" style="padding:12px"><div style="font-size:11.5px;color:var(--muted);margin-bottom:6px">Last 24 hours</div>'+
        '<svg viewBox="0 0 100 40" preserveAspectRatio="none" style="width:100%;height:100px"><polyline points="'+pts+'" fill="none" stroke="'+(up?"#34d399":"#fb7185")+'" stroke-width="1.8" vector-effect="non-scaling-stroke"/></svg></div>';
    } else { $("#coinChart").innerHTML = ""; }
  }catch(e){ $("#coinChart").innerHTML = ""; }
}
function open2(html){ W.openSheet(html); haptic(); }

/* =====================================================================
   PULSE
   ===================================================================== */
var qFilter = "All";
function renderPulse(){
  var cats = ["All","Catchphrases","Wisdom","Safety","Market"];
  $("#quoteFilters").innerHTML = cats.map(function(c){
    return '<button class="s'+(qFilter===c?" on":"")+'" data-qc="'+c+'">'+c+'</button>'; }).join("");
  $$("#quoteFilters .s").forEach(function(b){ b.addEventListener("click", function(){ qFilter = b.dataset.qc; renderPulse(); haptic(); }); });
  var list = QUOTES.filter(function(q){ return qFilter === "All" || q.c === qFilter; });
  var daily = QUOTES[W.dailyPick(QUOTES.length, 5)];
  var html = "";
  if(qFilter === "All"){
    html += '<h2 class="sec">Quote of the day</h2><div class="quote card" data-quote="'+esc(daily.t)+'" style="background:linear-gradient(150deg,rgba(139,92,246,.24),rgba(34,211,238,.12))">'+
      '<div class="t" style="font-size:17px">'+esc(daily.t)+'</div><div class="a"><i></i>'+esc(daily.a)+' · tap to copy</div></div>';
  }
  html += '<h2 class="sec">'+list.length+' lines</h2>';
  list.forEach(function(q){ html += '<div class="quote ripple" data-quote="'+esc(q.t)+'"><div class="t">'+esc(q.t)+'</div><div class="a"><i></i>'+esc(q.a)+'</div></div>'; });
  $("#quoteList").innerHTML = html;
  renderPhraseGen();
}
var PH = ["not your keys","not your coins","cold storage forever","two backups minimum","test with dust",
  "revoke the approve","read before you sign","scam radar on","no DMs accepted","seed on paper",
  "verify the contract","small size first","bull market patience","bear market courage"];
function renderPhraseGen(){
  var picked = shuffle(PH.slice()).slice(0,12);
  $("#phraseGen").innerHTML =
    '<div class="warn" style="margin-bottom:12px">'+ICON("i-alert")+'<span><b>This is a joke, not a wallet.</b> Never use words suggested by an app, website or influencer to store real funds. Your real seed phrase belongs in your own wallet, offline, written by hand.</span></div>'+
    '<div class="slotwrap">'+picked.map(function(p){ return '<div class="slot f">'+esc(p)+'</div>'; }).join("")+'</div>'+
    '<div class="acts"><button class="btn" id="genNew">'+ICON("i-dice")+'Regenerate</button><button class="btn pri" id="genCopy">'+ICON("i-copy")+'Copy phrases</button></div>';
  $("#genNew").addEventListener("click", function(){ renderPhraseGen(); haptic(); });
  $("#genCopy").addEventListener("click", function(){ copy(picked.join(", "), "Copied (harmlessly)"); });
}

/* =====================================================================
   VAULT
   ===================================================================== */
function renderVault(){
  var read = Object.keys(ST.read).length, tot = ST.quizR + ST.quizW;
  $("#vaultStats").innerHTML =
    '<div class="stat">'+ICON("i-book")+'<b>'+read+'</b><span>entries read</span></div>'+
    '<div class="stat">'+ICON("i-key")+'<b>'+ST.known.length+'</b><span>seed words learned</span></div>'+
    '<div class="stat">'+ICON("i-star")+'<b>'+ST.saved.length+'</b><span>saved words</span></div>'+
    '<div class="stat">'+ICON("i-flame")+'<b>'+ST.streak+'</b><span>day streak</span></div>'+
    '<div class="stat">'+ICON("i-brain")+'<b>'+(tot?Math.round(ST.quizR/tot*100):0)+'%</b><span>quiz accuracy</span></div>'+
    '<div class="stat">'+ICON("i-database")+'<b>'+(Net.online?"on":"off")+'</b><span>backend sync</span></div>';
  var s = ST.saved.slice().reverse();
  $("#savedCount").textContent = ST.saved.length ? ST.saved.length + " saved" : "";
  $("#savedList").innerHTML = s.length ? '<div class="list">' + s.map(function(n,i){
      var t = BY_LOWER[n.toLowerCase()]; if(!t) return "";
      return '<div class="rowitem ripple" data-open-term="'+esc(n)+'"><div class="av '+"abcde"[i%5]+'">★</div>'+
        '<div style="min-width:0"><div class="nm">'+esc(n)+'</div><div class="mt">'+esc(t.c)+'</div></div>'+
        '<div class="go">'+ICON("i-right")+'</div></div>';
    }).join("") + '</div>'
    : '<div class="empty">Nothing saved yet.<br>Tap ☆ Save on any word and it lands here.</div>';
  W.refreshSyncLabel();
}
function bindVault(){
  var bos = $("#btnOpenSettings");
  if(bos) bos.addEventListener("click", function(){ W.closeSheet(); document.querySelector("#btnDrawer").click(); });
  $("#btnSync").addEventListener("click", async function(){
    if(!Net.online){ toast("No backend reachable — saved locally", "i-wifi-off"); return; }
    await Net.pushProgress(); await Net.pullProgress(); renderVault(); toast("Synced with backend", "i-check");
  });
  $("#btnExport").addEventListener("click", function(){
    var blob = { app:"WordVault", version:"2.0", uid:ST.uid, exported:new Date().toISOString(),
                 progress:{ saved:ST.saved, known:ST.known, read:ST.read, streak:ST.streak, quizR:ST.quizR, quizW:ST.quizW, last:ST.last } };
    var data = JSON.stringify(blob, null, 2);
    try{
      var a = document.createElement("a");
      a.href = URL.createObjectURL(new Blob([data], {type:"application/json"}));
      a.download = "wordvault-progress.json"; document.body.appendChild(a); a.click();
      setTimeout(function(){ URL.revokeObjectURL(a.href); a.remove(); }, 500);
      toast("Progress exported", "i-download");
    }catch(e){ copy(data, "Progress copied as JSON"); }
  });
  $("#btnImport").addEventListener("click", function(){ $("#filePick").click(); });
  $("#filePick").addEventListener("change", function(){
    var f = this.files && this.files[0]; if(!f) return;
    var rd = new FileReader();
    rd.onload = function(){
      try{
        var j = JSON.parse(rd.result), p = j.progress || j;
        (p.saved||[]).forEach(function(n){ if(BY_LOWER[String(n).toLowerCase()] && ST.saved.indexOf(n) < 0) ST.saved.push(n); });
        (p.known||[]).forEach(function(i){ if(typeof i === "number" && ST.known.indexOf(i) < 0) ST.known.push(i); });
        Object.keys(p.read||{}).forEach(function(k){ ST.read[k] = 1; });
        ST.streak = Math.max(ST.streak, p.streak||0);
        ST.quizR = Math.max(ST.quizR, p.quizR||0); ST.quizW = Math.max(ST.quizW, p.quizW||0);
        save(); W.buildDrawer(); renderVault(); refreshAll();
        toast("Progress imported", "i-upload");
      }catch(e){ toast("That file could not be read"); }
    };
    rd.readAsText(f); this.value = "";
  });
  $("#btnReset").addEventListener("click", function(){
    if(!confirm("Reset saved words, learned seed words, streaks and quiz stats?")) return;
    var uid = ST.uid;
    ST = Object.assign({}, ST, { saved:[], known:[], read:{}, last:"", streak:0, quizR:0, quizW:0 });
    save();
    if(Net.online) Net.req("DELETE", "/api/progress?uid="+encodeURIComponent(uid), null, 5000).catch(function(){});
    W.rendered.home = 0; W.rendered.words = 0; W.rendered.seeds = 0;
    W.buildDrawer(); refreshAll(); toast("Everything reset", "i-refresh");
  });
}
function refreshAll(){
  if(ST.view === "home") W.homeRender();
  else if(ST.view === "words") W.renderWords();
  else if(ST.view === "vault") renderVault();
  W.buildDrawer();
}

/* =====================================================================
   SAFETY
   ===================================================================== */
var SCAMS = [
  ["Urgency", "Four-minute deadlines, “last chance”, “only 3 spots”. Real opportunities survive an afternoon of thinking."],
  ["Unsolicited offers", "DMs, comments and Telegram invites are almost always bait. Real support never messages first."],
  ["Seed phrase requests", "Nobody legitimate ever needs your words. Not support, not a giveaway, not a dev, not a lover."],
  ["Too-good yields", "Ask why the yield exists. If the answer is “more people joining”, you are the yield."],
  ["Fake urgency in apps", "Cloned wallet apps and adverts are the most common mobile theft. Check the publisher before installing."],
  ["Links in notifications", "Never sign a transaction from a link you did not open yourself. Type the domain, or use a bookmark."]
];
function renderSafety(){
  $("#rulesList").innerHTML = RULES.map(function(r,i){
    return '<div class="rule"><i>'+(i+1)+'</i><p>'+esc(r)+'</p></div>';
  }).join("");
  $("#scamCard").innerHTML = SCAMS.map(function(s){
    return '<div class="kv" style="align-items:flex-start"><span style="flex:1"><b style="display:block;color:#fecdd3">'+s[0]+'</b>'+
      '<span style="font-size:12.6px;color:var(--muted)">'+esc(s[1])+'</span></span></div>';
  }).join("");
}

/* =====================================================================
   ABOUT
   ===================================================================== */
async function renderAbout(){
  var backend = $("#backendCard");
  if(Net.online && Net.health){
    await Net.loadPrices();
    var st = await Net.req("GET", "/api/stats", null, 6000).catch(function(){ return null; });
    var h = Net.health;
    backend.innerHTML =
      '<div class="kv"><span>Status</span><b style="color:#86efac">connected</b></div>'+
      '<div class="kv"><span>Backend version</span><b>v'+esc(h.version)+'</b></div>'+
      '<div class="kv"><span>Dictionary served</span><b>'+h.terms+' terms · '+h.categories+' categories</b></div>'+
      '<div class="kv"><span>Search engine</span><b>SQLite FTS5 (ranked, server-side)</b></div>'+
      '<div class="kv"><span>Seed list</span><b>'+h.seeds+' words · checksum validated server-side</b></div>'+
      '<div class="kv"><span>Price data</span><b>'+(Net.prices && Net.prices.source === "kraken" ? "Kraken (fallback)" : "CoinGecko")+'</b></div>'+
      (st ? ('<div class="kv"><span>Your device</span><b>'+esc(ST.uid.slice(0,14))+'</b></div>'+
             '<div class="kv"><span>Total API lookups</span><b>'+(st.counters.api_calls||0)+'</b></div>'+
             '<div class="kv"><span>Words read by everyone</span><b>'+(st.counters.words_read||0)+'</b></div>'+
             '<div class="kv"><span>Phrases validated</span><b>'+(st.counters.checks||0)+'</b></div>'+
             '<div class="kv"><span>Devices synced</span><b>'+st.devices+'</b></div>'+
             '<div class="kv"><span>Trending (real reads)</span><b>'+(st.trending && st.trending.length ? esc(st.trending[0].n)+' · '+st.trending[0].hits+' reads' : 'no reads yet')+'</b></div>'+
             '<div class="kv"><span>Reads tracked</span><b>'+(st.counters.words_read||0)+' word opens counted server-side</b></div>') : '')+
      '<div class="acts"><button class="btn" id="abCheck">'+ICON("i-refresh")+'Re-check now</button></div>';
  } else {
    backend.innerHTML = '<div class="kv"><span>Status</span><b style="color:#fde68a">offline library</b></div>'+
      '<div class="kv"><span>What still works</span><b>every word, all 2,048 seeds, trainers, progress</b></div>'+
      '<div class="kv"><span>What needs the server</span><b>live prices, cross-device sync, server FTS</b></div>'+
      '<div class="acts"><button class="btn" id="abCheck">'+ICON("i-refresh")+'Retry connection</button></div>';
  }
  var ac = $("#abCheck"); if(ac) ac.addEventListener("click", async function(){ await Net.boot(); renderAbout(); toast(Net.online?"Backend connected":"Still offline — local mode"); });
  $("#sourcesCard").innerHTML =
    '<div class="kv"><span>Seed word list</span><b>BIP-39, official 2,048 words</b></div>'+
    '<div class="kv"><span>Prices &amp; market cap</span><b>CoinGecko (Kraken fallback)</b></div>'+
    '<div class="kv"><span>Sentiment</span><b>alternative.me Fear &amp; Greed</b></div>'+
    '<div class="kv"><span>Dictionary</span><b>Curated, 2026-current</b></div>'+
    '<div class="kv"><span>Storage</span><b>Your device + your own backend row</b></div>';
  $("#bipCard").innerHTML =
    '<div style="font-size:13.4px;color:#dfe4f1;line-height:1.6">'+
    'A BIP-39 phrase is <b>128 or 256 bits of entropy</b> plus a checksum, sliced into 11-bit groups. Each group is an index into the official 2,048-word list — which is why 12 words equal 1,024 bits of entropy, and why a single wrong word makes the checksum fail.<br><br>'+
    '<b>12 words</b> = 128 bits · <b>24 words</b> = 256 bits. Every major wallet uses this standard, so the same words restore the same wallet everywhere — provided the order is exactly right.<br><br>'+
    'The Vault tab will validate any phrase you paste, using the same maths a wallet uses, entirely offline or through the backend.</div>'+
    '<div class="acts"><button class="btn pri" data-go="seeds">'+ICON("i-key")+'Open the trainer</button></div>';
}

/* =====================================================================
   ASSEMBLE + INIT
   ===================================================================== */
W.RENDER.home = function(){ W.homeRender(); };
W.RENDER.words = function(){ W.renderWords(); };
W.RENDER.seeds = renderSeeds;
W.RENDER.market = renderMarket;
W.RENDER.pulse = renderPulse;
W.RENDER.vault = function(){ renderVault(); bindVault(); };
W.renderVault = renderVault;
W.RENDER.safety = renderSafety;
W.RENDER.about = renderAbout;

/* polling */
setInterval(function(){
  if(!Net.online || !ST.live) return;
  if(ST.view === "market" || ST.view === "home") renderMarketData();
}, 60000);
document.addEventListener("visibilitychange", function(){
  if(document.visibilityState === "visible"){
    if(Net.online && ST.live) renderMarketData();
    refreshAll();
  } else if(dirty) persist();
});
window.addEventListener("pagehide", function(){ if(dirty) persist(); });

/* boot */
async function boot(){
  document.body.classList.toggle("lite", !ST.glow);
  document.body.classList.toggle("reduce", !!ST.reduce);
  document.body.classList.toggle("compact", !!ST.compact);
  W.buildDrawer();
  var tabIndex = ["home","words","seeds"].indexOf(ST.view);
  if(tabIndex < 0){ tabIndex = 0; }
  var ind = $("#tabInd");
  ind.style.transform = "translateX(" + (tabIndex * 100 + tabIndex * 4) + "%)";
  W.go(ST.view || "home");
  await Net.boot();
  W.buildDrawer();
  if(ST.view === "market" || ST.view === "home" || ST.view === "about") renderMarketData();
  Net.event("session");
}
boot();
})();
