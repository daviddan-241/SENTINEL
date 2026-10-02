"use strict";
/* =========================================================================
   WordVault v2 — core, backend client, navigation, home & words
   ========================================================================= */
(function(){
var V = window.__VAULT__;
var TERMS = V.terms, SEEDS = V.seeds, CATS = V.cats, LEVELS = V.levels, QUOTES = V.quotes.map(function(q){return {t:q[0],a:q[1],c:q[2]};}), RULES = V.rules;
var BY_LOWER = {}, SEED_BY_WORD = {};
TERMS.forEach(function(t){ BY_LOWER[t.n.toLowerCase()] = t; });
SEEDS.forEach(function(s){ SEED_BY_WORD[s.w] = s; });

var $ = function(s,r){ return (r||document).querySelector(s); };
var $$ = function(s,r){ return Array.prototype.slice.call((r||document).querySelectorAll(s)); };
var esc = function(s){ return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;"); };
var DAY = Math.floor(Date.now()/864e5);
var ICON = function(id, cls){ return '<svg class="i '+(cls||"")+'" viewBox="0 0 24 24"><use href="#'+id+'"/></svg>'; };

/* ------------------------------- state ------------------------------- */
var DEF = { view:"home", saved:[], known:[], read:{}, last:"", streak:0, quizR:0, quizW:0,
            haptic:true, glow:true, live:true, reduce:false, compact:false, uid:"", seedTab:"list" };
var ST = Object.assign({}, DEF);
try { var raw = localStorage.getItem("wordvault.v2"); if(raw) ST = Object.assign(ST, JSON.parse(raw)); } catch(e){}
if(!ST.uid){ ST.uid = "wv_" + Math.random().toString(36).slice(2,10) + Date.now().toString(36); }
var saveT = null, dirty = false;
function save(now){
  dirty = true;
  clearTimeout(saveT);
  saveT = setTimeout(function(){ persist(); }, now ? 0 : 160);
}
function persist(){
  try { localStorage.setItem("wordvault.v2", JSON.stringify(ST)); } catch(e){}
  dirty = false;
  if(Net.online && Net.progressOk) Net.pushProgress();
}
function today(){ var d = new Date(); return d.getFullYear()+"-"+String(d.getMonth()+1).padStart(2,"0")+"-"+String(d.getDate()).padStart(2,"0"); }
(function streak(){
  var t = today();
  if(ST.last !== t){
    var y = new Date(Date.now()-864e5);
    var ys = y.getFullYear()+"-"+String(y.getMonth()+1).padStart(2,"0")+"-"+String(y.getDate()).padStart(2,"0");
    ST.streak = (ST.last === ys) ? (ST.streak||0)+1 : 1;
    ST.last = t; save(1);
  }
})();
function applyLook(){
  document.body.classList.toggle("lite", !ST.glow);
  document.body.classList.toggle("reduce", !!ST.reduce);
  document.body.classList.toggle("compact", !!ST.compact);
}
function haptic(p){ if(ST.haptic && navigator.vibrate){ try{ navigator.vibrate(p||9); }catch(e){} } }
var toastT = null;
function toast(msg, icon){
  var el = $("#toast");
  el.innerHTML = (icon ? ICON(icon) : "") + "<span>" + esc(msg) + "</span>";
  el.style.display = "flex"; el.style.alignItems = "center"; el.style.gap = "8px"; el.style.justifyContent = "center";
  el.classList.add("on");
  clearTimeout(toastT); toastT = setTimeout(function(){ el.classList.remove("on"); }, 2000);
}
function shuffle(a){ for(var i=a.length-1;i>0;i--){ var j=Math.floor(Math.random()*(i+1)), t=a[i]; a[i]=a[j]; a[j]=t; } return a; }
function copy(text, msg){
  var done = function(){ toast(msg||"Copied", "i-copy"); haptic(); };
  if(navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(done, fb);
  else fb();
  function fb(){ try{ var ta=document.createElement("textarea"); ta.value=text; ta.style.position="fixed"; ta.style.opacity="0";
    document.body.appendChild(ta); ta.select(); document.execCommand("copy"); document.body.removeChild(ta); done(); }catch(e){ toast("Copy unavailable"); } }
}
function share(title, text){
  if(navigator.share) navigator.share({title:title, text:text}).catch(function(){});
  else copy(text, "Copied instead");
}
var _nf = {compact:0};
function fmt(n, dec){
  if(n === null || n === undefined || isNaN(n)) return "—";
  if(Math.abs(n) >= 1e12) return (n/1e12).toFixed(2)+"T";
  if(Math.abs(n) >= 1e9) return (n/1e9).toFixed(2)+"B";
  if(Math.abs(n) >= 1e6) return (n/1e6).toFixed(2)+"M";
  if(Math.abs(n) >= 1e3) return n.toLocaleString(undefined,{maximumFractionDigits:0});
  var d = dec !== undefined ? dec : (Math.abs(n) < 1 ? 4 : 2);
  return n.toLocaleString(undefined,{minimumFractionDigits:d, maximumFractionDigits:d});
}
function money(n){ return n === null || n === undefined ? "—" : "$"+fmt(n); }
function catPill(c){
  var m = {Basics:"",Mining:"",Bitcoin:"y",Ethereum:"c",Tech:"",Tokens:"c",DeFi:"g",Scaling:"c",Trading:"y",
           Security:"r",Culture:"",Names:"n",Metrics:"g",Regulation:"y",Web3:"c","AI x Crypto":"",Privacy:"n",Data:"n",History:"y",TradFi:"g"};
  return '<span class="pill '+(m[c]||"")+'">'+esc(c)+'</span>';
}
function levDots(l){ var s='<span class="levdots">'; for(var i=1;i<=3;i++) s+='<i class="'+(i<=l?"on":"")+'"></i>'; return s+"</span>"; }
function when(ts){ var d=new Date(ts*1000); return d.toLocaleTimeString([], {hour:"2-digit",minute:"2-digit"}); }
function dailyPick(n, salt){ return (DAY*(salt||7)+(salt||0)) % n; }

/* ------------------------------- NET (backend) ------------------------------- */
var Net = {
  online:false, booted:false, version:null, stats:null, prices:null, priceTs:0, health:null,
  progressOk:true, lastSync:0, pending:false,

  async boot(){
    try{
      var r = await this.req("GET", "/api/health", null, 3500);
      if(r && r.ok){
        this.online = true; this.health = r; this.version = r.version;
        NetUI(true, "backend " + r.version);
        this.pullProgress();
        this.booted = true;
        return true;
      }
    }catch(e){}
    // No backend. That no longer means no live data: the static snapshot and the public APIs
    // can both feed the market screen, so say which of those is actually happening.
    var market = null;
    try{ market = await this.loadPrices(true); }catch(e){}
    NetUI(false, market && market.coins.length ? "static host · live market" : "offline library");
    this.booted = true;
    return false;
  },
  async req(method, path, body, timeout, fresh){
    var ctl = new AbortController();
    var t = setTimeout(function(){ ctl.abort(); }, timeout || 8000);
    try{
      var opt = { method:method, signal:ctl.signal, headers:{} };
      if(fresh) opt.cache = "no-store";
      if(body !== null && body !== undefined){ opt.headers["Content-Type"] = "application/json"; opt.body = JSON.stringify(body); }
      var r = await fetch(path, opt);
      clearTimeout(t);
      if(!r.ok && r.status !== 404) throw new Error("HTTP "+r.status);
      return await r.json();
    } finally { clearTimeout(t); }
  },
  async pullProgress(){
    try{
      var r = await this.req("GET", "/api/progress?uid="+encodeURIComponent(ST.uid), null, 5000);
      if(r && r.found && r.blob){
        var b = r.blob, changed = false;
        (b.saved||[]).forEach(function(n){ if(ST.saved.indexOf(n) < 0){ ST.saved.push(n); changed = true; } });
        (b.known||[]).forEach(function(i){ if(typeof i === "number" && ST.known.indexOf(i) < 0){ ST.known.push(i); changed = true; } });
        Object.keys(b.read||{}).forEach(function(k){ if(!ST.read[k]){ ST.read[k] = 1; changed = true; } });
        if((b.streak||0) > (ST.streak||0)){ ST.streak = b.streak; changed = true; }
        ST.quizR = Math.max(ST.quizR||0, b.quizR||0); ST.quizW = Math.max(ST.quizW||0, b.quizW||0);
        this.lastSync = r.updated_at || 0;
        if(changed){ save(1); }
        refreshAll();
      }
    }catch(e){ this.progressOk = false; }
  },
  async pushProgress(){
    if(this.pending){ this.queued = true; return; }
    var since = Date.now() - (this.pushTs || 0);
    if(since < 8000){
      clearTimeout(this._pt);
      var self2 = this;
      this._pt = setTimeout(function(){ self2.pushProgress(); }, 8200 - since);
      return;
    }
    this.pending = true; this.pushTs = Date.now();
    try{
      var blob = { saved:ST.saved, known:ST.known, read:ST.read, streak:ST.streak,
                   quizR:ST.quizR, quizW:ST.quizW, last:ST.last, v:2 };
      var r = await this.req("POST", "/api/progress", { uid:ST.uid, blob:blob }, 7000);
      if(r && r.ok){ this.lastSync = r.updated_at; this.progressOk = true; }
    }catch(e){ this.progressOk = false; }
    this.pending = false;
    if(this.queued){ this.queued = false; this.pushProgress(); }
    if($("#syncInfo")) refreshSyncLabel();
  },
  // Market data has three possible homes, tried in order of how much infrastructure is awake:
  //   1. the backend, when one is deployed and reachable
  //   2. market.json in the repo — a static file refreshed by a scheduled GitHub Action
  //   3. the public APIs straight from this browser (Kraken and alternative.me for prices and
  //      sentiment, CoinGecko opportunistically for caps and sparklines)
  // On GitHub Pages only 2 and 3 exist, and the app is fully usable there because of them.
  marketMode: "none",
  async loadPrices(force){
    if(!ST.live) return null;
    if(!force && this.prices && Date.now() - this.priceTs < 50000) return this.prices;
    var got = null;
    if(this.online){
      try{
        var d = await this.req("GET", "/api/prices", null, 9000);
        if(d && d.coins && d.coins.length){ got = d; this.marketMode = "backend"; }
      }catch(e){}
    }
    if(!got){
      try{
        var snap = await this.req("GET", "market.json?v=" + Math.floor(Date.now()/60000), null, 6000, true);
        if(snap && snap.coins && snap.coins.length){ got = snap; this.marketMode = "snapshot"; }
      }catch(e){}
    }
    if(!got){
      try{
        var direct = await this.marketDirect();
        if(direct && direct.coins && direct.coins.length){ got = direct; this.marketMode = "direct"; }
      }catch(e){}
    }
    if(got){ this.prices = got; this.priceTs = Date.now(); }
    return this.prices || null;
  },
  // No proxy, no key: Kraken's public ticker reflects the browser's origin, so a static page
  // can read it directly. XBT and XDG are Kraken's spellings of BTC and DOGE.
  async marketDirect(){
    var PAIRS = [["BTC","XBTUSD"],["ETH","ETHUSD"],["SOL","SOLUSD"],["BNB","BNBUSD"],["XRP","XRPUSD"],
                 ["ADA","ADAUSD"],["DOGE","XDGUSD"],["TRX","TRXUSD"],["LINK","LINKUSD"],
                 ["AVAX","AVAXUSD"],["DOT","DOTUSD"],["LTC","LTCUSD"]];
    var NAMES = {BTC:"Bitcoin",ETH:"Ethereum",SOL:"Solana",BNB:"BNB",XRP:"XRP",ADA:"Cardano",
                 DOGE:"Dogecoin",TRX:"Tron",LINK:"Chainlink",AVAX:"Avalanche",DOT:"Polkadot",LTC:"Litecoin"};
    function norm(k){
      k = k.toUpperCase();
      if(k.length > 6 && k.charAt(0) === "X" && k.indexOf("ZUSD") > 0) k = k.slice(1).replace("ZUSD","USD");
      return k.replace("XBT","BTC").replace("XDG","DOGE");
    }
    var out = { source:"browser", coins:[], global:{}, fearGreed:null, ts:Math.floor(Date.now()/1000) };
    var seen = {};
    try{
      var kr = await (await fetch("https://api.kraken.com/0/public/Ticker?pair=" +
                PAIRS.map(function(p){ return p[1]; }).join(","))).json();
      var res = kr.result || {};
      var byPair = {}; Object.keys(res).forEach(function(k){ byPair[norm(k)] = res[k]; });
      PAIRS.forEach(function(p){
        var v = byPair[norm(p[1])];
        if(!v || !v.c) return;
        var last = parseFloat(v.c[0]), open = parseFloat(v.o || v.c[0]);
        out.coins.push({ id:p[0].toLowerCase(), sym:p[0], name:NAMES[p[0]],
                         price:last, chg: open ? Math.round((last-open)/open*10000)/100 : null,
                         cap:null, vol: v.v ? parseFloat(v.v[1])*last : null, spark:[] });
        seen[p[1]] = 1;
      });
      if(out.coins.length) out.source = "browser-kraken";
    }catch(e){}
    try{
      var fg = await (await fetch("https://api.alternative.me/fng/?limit=1")).json();
      if(fg && fg.data && fg.data[0])
        out.fearGreed = { value: parseInt(fg.data[0].value,10), label: fg.data[0].value_classification };
    }catch(e){}
    try{
      var mk = await (await fetch("https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=" +
               PAIRS.map(function(p){ return p[0].toLowerCase(); }).join(",") +
               "&price_change_percentage=24h&sparkline=true")).json();
      if(mk && mk.length){
        var byId = {}; out.coins.forEach(function(c){ byId[c.id] = c; });
        mk.forEach(function(c){
          var t = byId[c.id];
          if(!t) return;
          t.price = c.current_price; t.chg = Math.round((c.price_change_percentage_24h||0)*100)/100;
          t.cap = c.market_cap; t.vol = c.total_volume; t.name = c.name;
          t.spark = ((c.sparkline_in_7d||{}).price||[]).map(function(x){ return Math.round(x*1e6)/1e6; })
                      .filter(function(_,i){ return i%8 === 0; }).slice(0,40);
        });
        out.source = "browser-coingecko";
      }
    }catch(e){}
    try{
      var g = await (await fetch("https://api.coingecko.com/api/v3/global")).json();
      if(g && g.data) out.global = { mcap:g.data.total_market_cap.usd, vol:g.data.total_volume.usd,
        btcDom:Math.round(g.data.market_cap_percentage.btc*10)/10,
        ethDom:Math.round(g.data.market_cap_percentage.eth*10)/10,
        coins:g.data.active_cryptocurrencies };
    }catch(e){}
    return out;
  },
  async search(q, cat, level, limit){
    if(!this.online) return null;
    try{
      var url = "/api/terms?q="+encodeURIComponent(q)+"&cat="+encodeURIComponent(cat||"All")+
                "&level="+(level||0)+"&limit="+(limit||300);
      var r = await this.req("GET", url, null, 6000);
      return r && r.engine === "fts5" ? r : null;
    }catch(e){ return null; }
  },
  async validate(phrase){
    if(this.online){
      try{ var r = await this.req("POST", "/api/seeds/validate", { phrase:phrase, uid:ST.uid }, 7000);
           if(r && r.state) return r; }catch(e){}
    }
    return BIP.validate(phrase);
  },
  async makePhrase(n){
    if(this.online){
      try{ var r = await this.req("POST", "/api/seeds/generate", { n:n }, 7000);
           if(r && r.words && r.words.length) return r.words; }catch(e){}
    }
    return BIP.make(n);
  },
  event(kind, name){ if(this.online) this.req("POST", "/api/event", { kind:kind, name:name||null, uid:ST.uid }, 4000).catch(function(){}); }
};


function NetUI(online, label){
  var dot = $("#netDot"), d = $("#dDot"), b = $("#badgeNet");
  if(dot){ dot.className = "dot " + (online ? "live" : "off"); }
  if(d){ d.className = "dot " + (online ? "live" : "off"); }
  if(b) b.innerHTML = ICON(online ? "i-bolt" : "i-wifi-off") + (online ? "live data" : "offline ready");
  var st = $("#dStatus");
  if(st) st.textContent = online ? ("Connected · backend v" + (Net.version||"?") + " · sync on") : "Offline mode · everything still works";
  if($("#backendCard") && ST.view === "about" && window.WV && WV.RENDER && WV.RENDER.about){
    WV.RENDER.about();            /* the About card lives in part 2 — reach it through the registry */
  }
  refreshSyncLabel();
}
function refreshSyncLabel(){
  var el = $("#syncInfo"); if(!el) return;
  if(!Net.online){ el.textContent = "offline — saved on this device only"; return; }
  el.textContent = Net.lastSync ? ("last synced " + when(Net.lastSync) + " · device " + ST.uid.slice(0,10)) : "connected · not synced yet";
}

/* ------------------------------- BIP-39 (offline fallback engine) ------------------------------- */
var BIP = (function(){
  var K=[0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2];
  function rotr(x,n){ return (x>>>n)|(x<<(32-n)); }
  function sha256(bytes){
    var H=[0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19];
    var len=bytes.length, bit=len*8;
    var b=new Uint8Array((((len+9)>>6)+1)<<6); b.set(bytes); b[len]=0x80;
    var dv=new DataView(b.buffer); dv.setUint32(b.length-4, bit>>>0); dv.setUint32(b.length-8, Math.floor(bit/4294967296));
    var w=new Array(64);
    for(var off=0; off<b.length; off+=64){
      for(var i=0;i<16;i++) w[i]=dv.getUint32(off+i*4);
      for(i=16;i<64;i++){
        var s0=rotr(w[i-15],7)^rotr(w[i-15],18)^(w[i-15]>>>3), s1=rotr(w[i-2],17)^rotr(w[i-2],19)^(w[i-2]>>>10);
        w[i]=(w[i-16]+s0+w[i-7]+s1)>>>0;
      }
      var a=H[0],bb=H[1],c=H[2],d=H[3],e=H[4],f=H[5],g=H[6],h=H[7];
      for(i=0;i<64;i++){
        var S1=rotr(e,6)^rotr(e,11)^rotr(e,25), ch=(e&f)^(~e&g), t1=(h+S1+ch+K[i]+w[i])>>>0;
        var S0=rotr(a,2)^rotr(a,13)^rotr(a,22), maj=(a&bb)^(a&c)^(bb&c), t2=(S0+maj)>>>0;
        h=g;g=f;f=e;e=(d+t1)>>>0;d=c;c=bb;bb=a;a=(t1+t2)>>>0;
      }
      H=[(H[0]+a)>>>0,(H[1]+bb)>>>0,(H[2]+c)>>>0,(H[3]+d)>>>0,(H[4]+e)>>>0,(H[5]+f)>>>0,(H[6]+g)>>>0,(H[7]+h)>>>0];
    }
    var out=new Uint8Array(32), o=new DataView(out.buffer);
    for(var k=0;k<8;k++) o.setUint32(k*4, H[k]);
    return out;
  }
  function bits(by){ var s=""; for(var i=0;i<by.length;i++) s+=by[i].toString(2).padStart(8,"0"); return s; }
  function bytesFromBits(x){ var o=new Uint8Array(x.length>>3); for(var i=0;i<o.length;i++) o[i]=parseInt(x.substr(i*8,8),2); return o; }
  function wb(w){ var s=SEED_BY_WORD[w]; return s ? s.i.toString(2).padStart(11,"0") : null; }
  return {
    make:function(n){
      n = n===24?24:12;
      var pool = shuffle(SEEDS.map(function(s){return s.w;})).slice(0,n-1);
      var b = pool.map(wb).join(""), cs=n/3, el=11*n-cs;
      for(var c=0;c<2048;c++){
        var full=b+c.toString(2).padStart(11,"0"), ent=full.slice(0,el), sum=full.slice(el);
        if(bits(sha256(bytesFromBits(ent))).slice(0,cs)===sum) return pool.concat([SEEDS[c].w]);
      }
      return pool;
    },
    validate:function(text){
      var words = String(text||"").trim().toLowerCase().split(/[\s,;]+/).filter(Boolean);
      if(!words.length) return {ok:false,state:"empty",msg:"Type or paste a phrase to check."};
      if([12,15,18,21,24].indexOf(words.length)<0)
        return {ok:false,state:"bad",msg:"A BIP-39 phrase has 12, 15, 18, 21 or 24 words — you typed "+words.length+"."};
      var b="", bad=[];
      words.forEach(function(w,i){ var s=SEED_BY_WORD[w]; if(!s) bad.push("#"+(i+1)+" "+w); else b+=s.i.toString(2).padStart(11,"0"); });
      if(bad.length) return {ok:false,state:"bad",unknown:bad,msg:"Not in the 2,048-word list: "+bad.slice(0,5).join(", ")+(bad.length>5?" and "+(bad.length-5)+" more":"")};
      var cs=words.length/3, el=b.length-cs;
      var calc=bits(sha256(bytesFromBits(b.slice(0,el)))).slice(0,cs);
      if(calc===b.slice(el)) return {ok:true,state:"good",words:words,msg:"Valid BIP-39 phrase — every word is in the list and the checksum matches."};
      return {ok:false,state:"sum",words:words,msg:"All words are in the list, but the checksum fails — usually two swapped words or one written down wrongly."};
    }
  };
})();

/* ------------------------------- navigation ------------------------------- */
var VIEWS = {
  home:    {title:"Home",     sub:"today's words · live market",     icon:"i-home",  drawer:"Explore"},
  words:   {title:"Words",    sub:TERMS.length+" dictionary entries", icon:"i-book",  drawer:"Explore"},
  seeds:   {title:"Seeds",    sub:"BIP-39 · 2,048 words",            icon:"i-key",   drawer:"Explore"},
  market:  {title:"Market",   sub:"live prices · sentiment",         icon:"i-chart", drawer:"Explore"},
  pulse:   {title:"Pulse",    sub:"culture · quotes · slang",        icon:"i-wave",  drawer:"Explore"},
  safety:  {title:"Safety",   sub:"rules · scam checklist",          icon:"i-shield",drawer:"Explore"},
  vault:   {title:"Vault",    sub:"progress · sync · settings",      icon:"i-vault", drawer:"Your data"},
  about:   {title:"About",    sub:"backend · data sources",          icon:"i-info",  drawer:"Your data"}
};
var TABORDER = ["home","words","seeds"];
var rendered = {}, RENDER = {};
function go(v){
  if(!VIEWS[v]) v = "home";
  ST.view = v; save();
  $$(".view").forEach(function(s){ s.classList.toggle("on", s.id === "v-"+v); });
  var ti = TABORDER.indexOf(v), ind = $("#tabInd");
  if(ti >= 0){
    ind.style.opacity = "1";
    ind.style.transform = "translateX(" + (ti * 100 + ti * 4) + "%)";
    $$("#tabs .tabbtn").forEach(function(b,i){ b.classList.toggle("on", i === ti); });
  } else {
    ind.style.opacity = "0";
    $$("#tabs .tabbtn").forEach(function(b){ b.classList.remove("on"); });
  }
  $("#barSub").textContent = VIEWS[v].sub;
  window.scrollTo(0,0);
  if(typeof WV.onGo === "function") WV.onGo(v);
  if(!rendered[v]){ rendered[v] = 1; (RENDER[v] || function(){})(); }
  buildDrawer();
  haptic();
}
$$("#tabs .tabbtn").forEach(function(b){ b.addEventListener("click", function(){ go(b.dataset.v); }); });

/* ------------------------------- drawer ------------------------------- */
var DRAWER = [
  {v:"market", icon:"i-chart", t:"Market pulse",  s:"live prices & sentiment"},
  {v:"pulse",  icon:"i-wave",  t:"Pulse",         s:"culture, quotes, slang"},
  {v:"safety", icon:"i-shield",t:"Safety rules",  s:"12 rules + scam checklist"},
  {v:"vault",  icon:"i-vault", t:"Your vault",    s:"progress, sync, export", grp:"data"},
  {v:"about",  icon:"i-info",  t:"About",         s:"backend & data sources", grp:"data"}
];
function drow(d){
  return '<div class="drow ripple'+(ST.view===d.v?" on":"")+'" data-go="'+d.v+'">'+
    '<span class="ic">'+ICON(d.icon)+'</span><div class="txt"><b>'+d.t+'</b><span>'+d.s+'</span></div>'+
    ICON("i-right", "i")+'</div>';
}
function trow(id, icon, t, sub, on){
  return '<div class="drow ripple" data-toggle="'+id+'"><span class="ic">'+ICON(icon)+'</span>'+
    '<div class="txt"><b>'+t+'</b><span>'+sub+'</span></div>'+
    '<span class="st'+(on?"":" off")+'">'+(on?"On":"Off")+'</span></div>';
}
function buildDrawer(){
  $("#drawerTools").innerHTML = DRAWER.filter(function(d){ return d.grp !== "data"; }).map(drow).join("");
  if($("#drawerData")) $("#drawerData").innerHTML =
    DRAWER.filter(function(d){ return d.grp === "data"; }).map(drow).join("") +
    trow("ticker", "i-chart", "Live market data", "ticker, prices, sentiment", !!ST.live);
  if($("#drawerLook")) $("#drawerLook").innerHTML =
    trow("glow", "i-sun", "Glow background", "drifting aurora", !!ST.glow) +
    trow("haptic", "i-bolt", "Haptic taps", "vibrate on interaction", !!ST.haptic) +
    trow("reduce", "i-eye-off", "Reduce motion", "stops all animation", !!ST.reduce) +
    trow("compact", "i-sliders", "Compact layout", "tighter spacing", !!ST.compact);
  var known = ST.known.length, pct = Math.round(known/2048*100), C = 2*Math.PI*25;
  $("#dRing").innerHTML = '<svg width="62" height="62"><circle cx="31" cy="31" r="25" stroke="rgba(255,255,255,.14)" stroke-width="5" fill="none"/>'+
    '<circle cx="31" cy="31" r="25" stroke="url(#dg)" stroke-width="5" fill="none" stroke-linecap="round" stroke-dasharray="'+C+'" stroke-dashoffset="'+(C*(1-known/2048))+'"/>'+
    '<defs><linearGradient id="dg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#a78bfa"/><stop offset="1" stop-color="#22d3ee"/></linearGradient></defs></svg>'+
    '<b>'+pct+'%</b>';
  $("#dTitle").textContent = ST.streak > 1 ? (ST.streak + "-day streak") : "WordVault";
  $("#dSub").textContent = known + " of 2,048 seed words · " + ST.saved.length + " saved";
}
function openDrawer(){ $("#drawer").classList.add("on"); $("#scrim").classList.add("on"); haptic(); }
function closeDrawer(){ $("#drawer").classList.remove("on"); $("#scrim").classList.remove("on"); }
$("#btnDrawer").addEventListener("click", openDrawer);
$("#scrim").addEventListener("click", closeDrawer);
document.addEventListener("click", function(e){
  var goEl = e.target.closest && e.target.closest("[data-go]");
  if(goEl){ closeDrawer(); rendered[goEl.dataset.go] = 0; go(goEl.dataset.go); return; }
  var tg = e.target.closest && e.target.closest("[data-toggle]");
  if(tg){
    var k = tg.dataset.toggle;
    if(k === "ticker"){ ST.live = !ST.live; save(); if(!ST.live){ $("#tickerWrap").hidden = true; toast("Live market data off", "i-wifi-off"); } else { toast("Live market data on", "i-bolt"); Net.loadPrices(true).then(renderHomeMarket); } }
    else if(k === "glow"){ ST.glow = !ST.glow; save(); applyLook(); toast(ST.glow ? "Glow on" : "Glow off", "i-sun"); }
    else if(k === "haptic"){ ST.haptic = !ST.haptic; save(); haptic(14); }
    else if(k === "reduce"){ ST.reduce = !ST.reduce; save(); applyLook(); }
    else if(k === "compact"){ ST.compact = !ST.compact; save(); applyLook(); }
    buildDrawer();
    if(WV.renderVault && ST.view === "vault") WV.renderVault();
    return;
  }
});

/* ------------------------------- ripples, sheets, actions ------------------------------- */
document.addEventListener("pointerdown", function(e){
  var el = e.target.closest && e.target.closest(".ripple");
  if(!el) return;
  var r = el.getBoundingClientRect(), s = document.createElement("span");
  s.className = "rp"; s.style.left = (e.clientX - r.left) + "px"; s.style.top = (e.clientY - r.top) + "px";
  el.appendChild(s); setTimeout(function(){ s.remove(); }, 560);
}, {passive:true});

function openSheet(html){ $("#sheetIn").innerHTML = '<div class="grab"></div>' + html; $("#sheet").classList.add("on"); }
function closeSheet(){ $("#sheet").classList.remove("on"); }
$("#sheet").addEventListener("click", function(e){ if(e.target.id === "sheet" || e.target.classList.contains("grab")) closeSheet(); });
(function swipe(){
  var y0 = null;
  $("#sheet").addEventListener("touchstart", function(e){
    if(e.target.id === "sheet" || (e.target.closest && e.target.closest(".grab"))) y0 = e.touches[0].clientY; else y0 = null;
  }, {passive:true});
  $("#sheet").addEventListener("touchend", function(e){
    if(y0 !== null && e.changedTouches[0].clientY - y0 > 60) closeSheet();
    y0 = null;
  }, {passive:true});
  var x0 = null, yd = null;
  $("#drawer").addEventListener("touchstart", function(e){ x0 = e.touches[0].clientX; yd = e.touches[0].clientY; }, {passive:true});
  $("#drawer").addEventListener("touchend", function(e){
    if(x0 === null) return;
    if(x0 - e.touches[0].clientX > 60 && Math.abs(e.touches[0].clientY - yd) < 60) closeDrawer();
    x0 = null;
  }, {passive:true});
})();
document.addEventListener("keydown", function(e){ if(e.key === "Escape"){ closeSheet(); closeDrawer(); } });

function termHTML(t, extra){
  var seed = SEED_BY_WORD[t.n.toLowerCase()];
  var h = '<h3>'+esc(t.n)+'</h3><div class="cat">'+catPill(t.c)+levDots(t.l)+
    '<span style="font-size:10.5px;color:var(--muted-2);text-transform:uppercase;letter-spacing:.07em">'+esc(LEVELS[t.l]||"")+'</span></div>'+
    '<p class="d">'+esc(t.d)+'</p>';
  if(t.e) h += '<div class="ex"><b style="color:#c4b5fd">Example · </b>'+esc(t.e)+'</div>';
  if(seed) h += '<div class="seedbox">'+ICON("i-key")+'<b style="margin-left:7px">Also BIP-39 seed word #'+(seed.i+1)+'</b><br>Recovery phrases are drawn from the same 2,048 words, so you already half-know this one.</div>';
  var rel = TERMS.filter(function(x){ return x.c === t.c && x.n !== t.n; }).slice(0,6);
  if(rel.length) h += '<div style="font-size:10.5px;color:var(--muted-2);text-transform:uppercase;letter-spacing:.08em;margin:16px 0 8px">More in '+esc(t.c)+'</div><div class="bank">'+
    rel.map(function(r){ return '<button class="b" data-open-term="'+esc(r.n)+'">'+esc(r.n)+'</button>'; }).join("")+'</div>';
  h += '<div class="acts"><button class="btn '+(ST.saved.indexOf(t.n)>=0?"on":"")+'" data-save="'+esc(t.n)+'">'+
       ICON(ST.saved.indexOf(t.n)>=0?"i-star-f":"i-star")+(ST.saved.indexOf(t.n)>=0?"Saved":"Save")+'</button>'+
       '<button class="btn" data-copy="'+esc(t.n)+'">'+ICON("i-copy")+'Copy</button>'+
       '<button class="btn" data-share="'+esc(t.n)+'">'+ICON("i-share")+'Share</button></div>'+
       '<div class="acts"><button class="btn pri" data-close="1">Done</button></div>';
  return h;
}
function openTerm(name){
  var t = BY_LOWER[String(name).toLowerCase()]; if(!t) return;
  if(!ST.read[t.n]){ ST.read[t.n] = 1; save(); }
  Net.event("word_read", t.n);
  openSheet(termHTML(t)); haptic();
}
function openSeed(i){
  var s = SEEDS[i]; if(!s) return;
  var t = BY_LOWER[s.w];
  var h = '<h3 style="font-size:34px">'+esc(s.w)+'</h3><div class="cat"><span class="pill c">BIP-39 word #'+(s.i+1)+'</span>'+
    (t ? catPill(t.c) : '<span class="pill y">recognition</span>')+'</div>';
  h += t ? '<p class="d">'+esc(t.d)+'</p>'+(t.e?'<div class="ex"><b style="color:#c4b5fd">Example · </b>'+esc(t.e)+'</div>':'')
         : '<p class="d">Part of the official 2,048-word list every wallet draws recovery phrases from. No crypto-jargon meaning — what matters is recognising it in a phrase and spelling it exactly right.</p>';
  h += '<div class="ex"><b style="color:#c4b5fd">Alphabet neighbours · </b>'+(s.i>0?esc(SEEDS[s.i-1].w):"—")+' · <b>'+esc(s.w)+'</b> · '+(s.i<2047?esc(SEEDS[s.i+1].w):"—")+
       '<br><b style="color:#c4b5fd">Shape · </b>'+s.w.length+' letters · starts with “'+esc(s.w[0].toUpperCase())+'” · position '+(s.i+1)+' of 2,048</div>';
  h += '<div class="acts"><button class="btn '+(ST.known.indexOf(s.i)>=0?"ok":"")+'" data-know="'+s.i+'">'+
       ICON("i-check")+(ST.known.indexOf(s.i)>=0?"Learned":"Mark as learned")+'</button>'+
       '<button class="btn" data-copy="'+esc(s.w)+'">'+ICON("i-copy")+'Copy</button></div>'+
       (t?'<div class="acts"><button class="btn" data-term="'+esc(t.n)+'">Open full entry: '+esc(t.n)+'</button></div>':'')+
       '<div class="acts"><button class="btn pri" data-close="1">Done</button></div>';
  openSheet(h); haptic();
}
document.addEventListener("click", function(e){
  var el = e.target.closest ? e.target.closest("[data-open-term],[data-term],[data-save],[data-copy],[data-share],[data-close],[data-know],[data-fill-seed],[data-quote],[data-sheet]") : null;
  if(!el) return;
  if(el.hasAttribute("data-close")) return closeSheet();
  if(el.hasAttribute("data-open-term")){ openTerm(el.getAttribute("data-open-term")); buildDrawer(); return; }
  if(el.hasAttribute("data-term")) return openTerm(el.getAttribute("data-term"));
  if(el.hasAttribute("data-copy")) return copy(el.getAttribute("data-copy"));
  if(el.hasAttribute("data-quote")) return copy(el.getAttribute("data-quote"));
  if(el.hasAttribute("data-fill-seed")) return openSeed(+el.getAttribute("data-fill-seed"));
  if(el.hasAttribute("data-share")){
    var nm = el.getAttribute("data-share"), t = BY_LOWER[nm.toLowerCase()], s = SEED_BY_WORD[nm];
    return share("WordVault · "+nm, nm + (t?" — "+t.d:(s?" — a BIP-39 seed word.":"")) + "\n\nvia WordVault");
  }
  if(el.hasAttribute("data-save")){
    var n = el.getAttribute("data-save"), k = ST.saved.indexOf(n);
    if(k >= 0) ST.saved.splice(k,1); else ST.saved.push(n);
    save(); el.classList.toggle("on", k < 0);
    el.innerHTML = ICON(k<0?"i-star-f":"i-star") + (k<0?"Saved":"Save");
    if(k<0) Net.event("word_saved");
    toast(k<0?"Saved to your vault":"Removed from vault", "i-star"); haptic(); buildDrawer(); return;
  }
  if(el.hasAttribute("data-know")){
    var i = +el.getAttribute("data-know"), j = ST.known.indexOf(i);
    if(j >= 0){ ST.known.splice(j,1); el.classList.remove("ok"); toast("Unmarked"); }
    else { ST.known.push(i); el.classList.add("ok"); toast("Learned · " + ST.known.length + " / 2,048", "i-check"); haptic(14); Net.event("seed_learned"); }
    el.innerHTML = ICON("i-check") + (j<0?"Learned":"Mark as learned");
    save(); buildDrawer(); return;
  }
});

/* ------------------------------- HOME ------------------------------- */
function statTile(icon, num, label, id){
  return '<div class="stat">'+ICON(icon)+'<b'+(id?' id="'+id+'"':'')+'>'+num+'</b><span>'+label+'</span></div>';
}
function renderHome(){
  $("#bTermCount").textContent = TERMS.length;
  $("#badgeSeedDefs").textContent = V.stats.seedDefs + " seed words explained";
  $("#ftTerms").textContent = TERMS.length;
  $("#heroStats").innerHTML =
    statTile("i-book", TERMS.length, "crypto terms")+
    statTile("i-key", "2,048", "seed words")+
    statTile("i-sliders", CATS.length, "categories")+
    statTile("i-flame", ST.streak, "day streak", "statStreak");
  var t = TERMS[dailyPick(TERMS.length, 3)];
  var d = new Date();
  $("#wodDate").textContent = d.toLocaleDateString([], {month:"short", day:"numeric"});
  $("#wodCard").innerHTML =
    '<div style="display:flex;align-items:center;gap:8px">'+catPill(t.c)+levDots(t.l)+'<span style="margin-left:auto;font-size:10.5px;color:var(--muted-2)">#'+((TERMS.indexOf(t))+1)+' of '+TERMS.length+'</span></div>'+
    '<h3>'+esc(t.n)+'</h3><div class="def">'+esc(t.d)+'</div>'+
    (t.e?'<div class="ex">'+esc(t.e)+'</div>':'')+
    '<div class="acts"><button class="btn pri" data-open-term="'+esc(t.n)+'">'+ICON("i-right")+'Open entry</button>'+
    '<button class="btn '+(ST.saved.indexOf(t.n)>=0?"on":"")+'" data-save="'+esc(t.n)+'">'+
    ICON(ST.saved.indexOf(t.n)>=0?"i-star-f":"i-star")+(ST.saved.indexOf(t.n)>=0?"Saved":"Save")+'</button></div>';
  renderDaily(t);
  renderWatch();
  renderCatChips();
  renderProgressCard();
  refreshHomeMarket();
}
function renderDaily(t){
  var opts = TERMS.filter(function(x){ return x.n !== t.n && x.c === t.c; });
  if(opts.length < 3) opts = TERMS.filter(function(x){ return x.n !== t.n; });
  opts = shuffle(shuffle(opts.slice()).slice(0,3).concat([t]));
  var answered = false;
  var html = '<div class="qcard glass"><div style="display:flex;align-items:center;gap:9px"><span class="pill c">Daily challenge</span><span style="font-size:11.5px;color:var(--muted)">'+ST.streak+'-day streak</span></div>'+
    '<div class="q">What does “'+esc(t.n)+'” mean?</div>';
  opts.forEach(function(o,i){ html += '<button class="opt ripple" data-i="'+i+'">'+esc(o.d.length>150?o.d.slice(0,148)+"…":o.d)+'</button>'; });
  html += '<div id="dailyRes" style="font-size:12.5px;color:var(--muted);margin-top:4px">Pick the best definition.</div></div>';
  $("#dailyQuiz").innerHTML = html;
  $$("#dailyQuiz .opt").forEach(function(b){
    b.addEventListener("click", function(){
      if(answered) return; answered = true;
      var chosen = opts[+b.dataset.i], right = chosen.n === t.n;
      b.classList.add(right ? "right" : "wrong");
      $$("#dailyQuiz .opt").forEach(function(bb){ if(opts[+bb.dataset.i].n === t.n) bb.classList.add("right"); });
      if(right){ ST.quizR++; Net.event("quiz_correct"); $("#dailyRes").innerHTML = '<b style="color:#86efac">Correct.</b> '+esc(t.n)+' — '+TERMS.length+' words in the vault.'; haptic(14); }
      else { ST.quizW++; Net.event("quiz_wrong"); $("#dailyRes").innerHTML = '<b style="color:#fca5a5">Not quite.</b> The answer is marked above — '+esc(t.n)+'.'; haptic([10,40,10]); }
      save(); buildDrawer();
    });
  });
}
var WATCH = ["x402","Agentic Commerce","Prediction Market","RWA","Stablecoin","Restaking","Perp DEX","AI Agent","Intent","DePIN","Tokenised Treasuries","Hyperliquid","Polymarket","CLARITY Act","GENIUS Act","Blob","Bitcoin ETF","Chain Abstraction"];
function renderWatch(){
  var seen = {};
  $("#watchlist").innerHTML = WATCH.map(function(n){
    var t = BY_LOWER[n.toLowerCase()];
    if(!t || seen[n]) return ""; seen[n] = 1;
    return '<div class="mini ripple" data-open-term="'+esc(t.n)+'"><b>'+esc(t.n)+'</b><span>'+esc(t.c)+'</span><p>'+esc(t.d)+'</p></div>';
  }).join("") || '<div class="empty">—</div>';
}
function renderCatChips(){
  var out = '<button class="chip" data-cat="__all">All '+TERMS.length+'</button>';
  CATS.forEach(function(c){
    var n = TERMS.filter(function(t){ return t.c === c; }).length;
    out += '<button class="chip ripple" data-cat="'+esc(c)+'">'+esc(c)+' · '+n+'</button>';
  });
  $("#catChips").innerHTML = out;
  $$("#catChips .chip").forEach(function(b){
    b.addEventListener("click", function(){
      var c = b.dataset.cat;
      filt.cat = (c === "__all") ? "All" : c; filt.q = ""; filt.level = 0; filt.letter = ""; visible = 200;
      if($("#q")){ $("#q").value = ""; $("#searchWrap").classList.remove("has"); }
      rendered.words = 0; go("words");
    });
  });
}
function renderProgressCard(){
  var known = ST.known.length, read = Object.keys(ST.read).length, tot = ST.quizR + ST.quizW;
  var C = 2*Math.PI*27;
  $("#progressCard").innerHTML =
    '<div style="display:flex;gap:14px;align-items:center">'+
      '<div class="ring" style="width:66px;height:66px"><svg width="66" height="66">'+
      '<circle cx="33" cy="33" r="27" stroke="rgba(255,255,255,.12)" stroke-width="6" fill="none"/>'+
      '<circle cx="33" cy="33" r="27" stroke="url(#pg)" stroke-width="6" fill="none" stroke-linecap="round" stroke-dasharray="'+C+'" stroke-dashoffset="'+(C*(1-known/2048))+'"/>'+
      '<defs><linearGradient id="pg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#a78bfa"/><stop offset="1" stop-color="#22d3ee"/></linearGradient></defs></svg>'+
      '<b>'+Math.round(known/2048*100)+'%</b></div>'+
      '<div style="flex:1;min-width:0">'+
        '<div style="font-size:15px;font-weight:690">'+known+' / 2,048 seed words learned</div>'+
        '<div style="font-size:12.3px;color:var(--muted);margin-top:3px">'+read+' dictionary entries read · '+ST.saved.length+' saved</div>'+
        '<div style="font-size:12.3px;color:var(--muted);margin-top:3px">Challenges: '+ST.quizR+' right, '+ST.quizW+' wrong'+(tot?' ('+Math.round(ST.quizR/tot*100)+'%)':'')+'</div>'+
      '</div></div>'+
    '<div class="acts"><button class="btn" id="pGoCards">'+ICON("i-key")+'Train seeds</button>'+
    '<button class="btn" id="pGoWords">'+ICON("i-book")+'Browse words</button></div>';
  $("#pGoCards").addEventListener("click", function(){ rendered.seeds = 0; go("seeds"); });
  $("#pGoWords").addEventListener("click", function(){ rendered.words = 0; go("words"); });
}
function refreshHomeMarket(){
  var el = $("#homeMarket");
  if(!ST.live){ el.innerHTML = '<div class="empty">Live market data is switched off in Settings.</div>'; return; }
  if(!Net.online){ el.innerHTML = '<div class="card glass"><div class="empty" style="padding:10px">'+'Live prices need the backend. This page is running offline — every word, the whole seed list and the trainers still work perfectly.'+'</div></div>'; return; }
  if(!Net.prices){ el.innerHTML = '<div class="coingrid"><div class="skel"></div><div class="skel"></div><div class="skel"></div><div class="skel"></div></div>'; return; }
  var coins = Net.prices.coins.slice(0,4);
  el.innerHTML = '<div class="coingrid">' + coins.map(coinCard).join("") + '</div>' +
    '<div class="acts"><button class="btn ghost" data-go="market">'+ICON("i-chart")+'Open market view</button></div>';
}
function coinCard(c){
  var up = (c.chg||0) >= 0;
  return '<div class="coin ripple" data-coin="'+esc(c.id)+'">'+
    '<div class="top2"><span class="sym">'+esc(c.sym.slice(0,4))+'</span><span class="name">'+esc(c.name)+'</span></div>'+
    '<div class="px">'+money(c.price)+'</div>'+
    '<div class="chg '+(up?"up":"down")+'">'+ICON(up?"i-trend-up":"i-trend-down")+(c.chg===null||c.chg===undefined?"—":(up?"+":"")+c.chg.toFixed(2)+"%")+'</div>'+
    spark(c, up)+'</div>';
}
function spark(c, up){
  if(!c.spark || c.spark.length < 4) return "";
  var min = Math.min.apply(null,c.spark), max = Math.max.apply(null,c.spark), r = (max-min)||1, W = 100, H = 30;
  var pts = c.spark.map(function(v,i){ return (i/(c.spark.length-1)*W).toFixed(2)+","+(H-((v-min)/r)*H*0.86-1).toFixed(2); }).join(" ");
  return '<svg class="spark" viewBox="0 0 100 30" preserveAspectRatio="none"><polyline points="'+pts+'" fill="none" stroke="'+(up?"#34d399":"#fb7185")+'" stroke-width="1.6" vector-effect="non-scaling-stroke"/></svg>';
}

/* ------------------------------- WORDS ------------------------------- */
var filt = { q:"", level:0, cat:"All", letter:"" }, visible = 200, serverBusy = false;
function termRow(t, alt){
  return '<div class="rowitem ripple" data-open-term="'+esc(t.n)+'"><div class="av '+alt+'">'+esc(t.n[0].toUpperCase())+'</div>'+
    '<div style="min-width:0"><div class="nm">'+esc(t.n)+'</div><div class="mt">'+esc(t.c)+' · '+esc(LEVELS[t.l])+
    (SEED_BY_WORD[t.n.toLowerCase()]?(' · <span style="color:#c4b5fd">seed word</span>'):'')+'</div></div>'+
    '<div class="go">'+levDots(t.l)+ICON("i-right")+'</div></div>';
}
function localMatch(){
  var q = filt.q.trim().toLowerCase();
  var out = TERMS.filter(function(t){
    if(filt.level && t.l !== filt.level) return false;
    if(filt.cat !== "All" && t.c !== filt.cat) return false;
    if(filt.letter && t.n[0].toUpperCase() !== filt.letter) return false;
    if(!q) return true;
    return t.n.toLowerCase().indexOf(q) >= 0 || t.d.toLowerCase().indexOf(q) >= 0;
  });
  out.sort(function(a,b){
    if(q){
      var as = a.n.toLowerCase().indexOf(q) === 0 ? 0 : 1, bs = b.n.toLowerCase().indexOf(q) === 0 ? 0 : 1;
      if(as !== bs) return as - bs;
    }
    return a.n.toLowerCase().localeCompare(b.n.toLowerCase());
  });
  return out;
}
function renderWords(){
  $("#lvlFilters").innerHTML = [["0","All levels"],["1","Basic"],["2","Intermediate"],["3","Advanced"]].map(function(p){
    return '<button class="s'+(String(filt.level)===p[0]?" on":"")+'" data-lv="'+p[0]+'">'+p[1]+'</button>'; }).join("");
  $("#catFilters").innerHTML = '<button class="s'+(filt.cat==="All"?" on":"")+'" data-c="All">All categories</button>' +
    CATS.map(function(c){ return '<button class="s'+(filt.cat===c?" on":"")+'" data-c="'+esc(c)+'">'+esc(c)+'</button>'; }).join("");
  $("#letterRail").innerHTML = '<button data-letter="">★</button>' +
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("").map(function(ch){
      return '<button data-letter="'+ch+'" class="'+(filt.letter===ch?"on":"")+'">'+ch+'</button>'; }).join("");
  $$("#lvlFilters .s").forEach(function(b){ b.addEventListener("click", function(){
    filt.level = +b.dataset.lv; visible = 200; renderWords(); }); });
  $$("#catFilters .s").forEach(function(b){ b.addEventListener("click", function(){
    filt.cat = b.dataset.c; visible = 200; renderWords(); haptic(); }); });
  $$("#letterRail button").forEach(function(b){ b.addEventListener("click", function(){
    filt.letter = b.dataset.letter; visible = 200; renderWords(); haptic(); }); });
  paintList();
}
var qT = null;
function paintList(){
  var items = localMatch();
  if(filt.q && Net.online && filt.q.trim().length > 2 && !filt.letter){
    clearTimeout(qT);
    qT = setTimeout(async function(){
      var r = await Net.search(filt.q, filt.cat, filt.level, 300);
      if(r && r.items && r.items.length && filt.q.trim().length > 2){
        paintItems(r.items, "server FTS5");
      }
    }, 220);
  }
  paintItems(items, Net.online ? "local index" : "offline index");
}
function paintItems(items, engine){
  if(!items.length){
    $("#termList").innerHTML = '<div class="empty">No word matches that.<br>Try “staking”, “rug”, “gas”, “airdrop” or “seed”.</div>';
    return;
  }
  var html = '<h2 class="sec">'+items.length+' word'+(items.length===1?"":"s")+
    '<span class="n">'+engine+(filt.q?' · “'+esc(filt.q)+'”':'')+'</span></h2>', shown = 0;
  if(filt.letter) html += '<div class="let">'+filt.letter+'</div>';
  for(var i=0;i<items.length && shown<visible;i++){
    var t = items[i];
    if(!filt.q && !filt.letter && i>0 && items[i-1].n[0].toUpperCase() !== t.n[0].toUpperCase())
      html += '<div class="let">'+esc(t.n[0].toUpperCase())+'</div>';
    html += termRow(t, "abcde"[shown % 5]); shown++;
  }
  if(items.length > shown) html += '<div class="acts"><button class="btn pri" id="moreBtn">Show '+
    Math.min(200, items.length-shown)+' more of '+(items.length-shown)+'</button></div>';
  $("#termList").innerHTML = html;
  var mb = $("#moreBtn"); if(mb) mb.addEventListener("click", function(){ visible += 200; paintItems(items, engine); });
}
$("#q").placeholder = "Search " + TERMS.length + " words…";
$("#q").addEventListener("input", function(){
  var v = this.value; $("#searchWrap").classList.toggle("has", !!v);
  clearTimeout(qT); qT = setTimeout(function(){ filt.q = v; filt.letter = ""; visible = 200; renderWords(); }, 120);
});
$("#qClear").addEventListener("click", function(){ $("#q").value = ""; filt.q = ""; $("#searchWrap").classList.remove("has"); renderWords(); $("#q").focus(); });

/* ------------------------------- top bar actions ------------------------------- */
$("#btnRandom").addEventListener("click", function(){
  openTerm(TERMS[Math.floor(Math.random()*TERMS.length)].n); toast("Random word", "i-dice");
});
$("#btnTheme").addEventListener("click", function(){
  ST.glow = !ST.glow; save(); applyLook();
  toast(ST.glow ? "Glow on" : "Glow off", "i-sun"); haptic();
});

/* ------------------------------- offline app shell ------------------------------- */
if("serviceWorker" in navigator && /^https?:$/.test(location.protocol)){
  window.addEventListener("load", function(){
    try{
      navigator.serviceWorker.register("sw.js").catch(function(){ /* sandboxed or file:// — the app is offline anyway */ });
    }catch(e){}
  });
}

/* exports for part 2 */
window.WV = { $:$, $$:$$, esc:esc, ICON:ICON, ST:ST, save:save, haptic:haptic, toast:toast, copy:copy, share:share,
  shuffle:shuffle, fmt:fmt, money:money, catPill:catPill, levDots:levDots, when:when, dailyPick:dailyPick,
  TERMS:TERMS, SEEDS:SEEDS, CATS:CATS, LEVELS:LEVELS, QUOTES:QUOTES, RULES:RULES, BY_LOWER:BY_LOWER, stats:V.stats,
  SEED_BY_WORD:SEED_BY_WORD, Net:Net, BIP:BIP, go:go, VIEWS:VIEWS, rendered:rendered, RENDER:RENDER,
  openTerm:openTerm, openSeed:openSeed, openSheet:openSheet, closeSheet:closeSheet, buildDrawer:buildDrawer,
  filt:filt, renderWords:renderWords, refreshHomeMarket:refreshHomeMarket, refreshSyncLabel:refreshSyncLabel,
  coinCard:coinCard, spark:spark, netUI:NetUI, homeRender:renderHome, applyLook:applyLook, closeDrawer:closeDrawer,
  onGo:null };
})();
