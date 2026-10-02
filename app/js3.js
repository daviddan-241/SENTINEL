"use strict";
/* =========================================================================
   WordVault v3 — motion engine: reveal-on-scroll, counters, price flashes,
   sparkle bursts, directional view transitions, trending, and the word wall
   ========================================================================= */
(function(){
var W = window.WV;
var $ = W.$, $$ = W.$$, esc = W.esc, ICON = W.ICON, ST = W.ST, save = W.save, haptic = W.haptic;
var toast = W.toast, shuffle = W.shuffle, money = W.money, fmt = W.fmt, Net = W.Net;
var SEEDS = W.SEEDS, TERMS = W.TERMS, BY_LOWER = W.BY_LOWER, SEED_BY_WORD = W.SEED_BY_WORD;

/* =========================== 1. reveal-on-scroll =========================== */
var MOTION = !ST.reduce && !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
var SEL = [".card:not(.noanim)", ".rowitem", ".quote", ".rule", ".coin", ".mini", ".wcell", ".mkstat", ".qcard", ".stat", ".gg"];
var SELSTR = SEL.join(",");
var io = null;
if("IntersectionObserver" in window){
  io = new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      if(e.isIntersecting){ e.target.classList.add("in"); io.unobserve(e.target); }
    });
  }, {rootMargin:"0px 0px -4% 0px", threshold:0.01});
}
function prime(root){
  if(!MOTION || !io || !root.querySelectorAll) return;
  var nodes = root.querySelectorAll(SELSTR);
  var perParent = {};
  var limit = window.innerHeight * 2.2;          /* nothing taller than ~2 screens can cross a ratio threshold */
  Array.prototype.forEach.call(nodes, function(el){
    if(el.classList.contains("reveal")) return;
    if(el.offsetHeight > limit) return;
    var key = el.parentNode;
    var idx = perParent[key] = (perParent[key] || 0) + 1;
    el.classList.add("reveal");
    el.style.setProperty("--d", Math.min(idx - 1, 9));
    io.observe(el);
  });
}
/* animate everything the app renders from now on, without touching render code */
if(MOTION && "MutationObserver" in window){
  var mo = new MutationObserver(function(muts){
    for(var i=0;i<muts.length;i++){
      var added = muts[i].addedNodes;
      for(var j=0;j<added.length;j++){
        var n = added[j];
        if(n.nodeType !== 1) continue;
        if(n.matches && n.matches(SELSTR)) { if(!n.classList.contains("reveal")){ n.classList.add("reveal"); n.style.setProperty("--d",0); io.observe(n); } }
        if(n.childElementCount) prime(n);
      }
    }
  });
  mo.observe(document.body, {childList:true, subtree:true});
}

/* safety net: anything already scrolled into view gets its reveal, no matter what */
setInterval(function(){
  if(!MOTION) return;
  var pend = document.querySelectorAll(".reveal:not(.in)");
  for(var i=0;i<pend.length && i<80;i++){
    var r = pend[i].getBoundingClientRect();
    if(r.top < window.innerHeight * 0.98 && r.bottom > -20) pend[i].classList.add("in");
  }
}, 1200);

/* =========================== 2. number counters =========================== */
var COUNT_SEL = ".stat b, .mkstat b, .ring > b, .coin .px, .badge b, #dRing b";
function animateNumber(el){
  if(!MOTION) return;
  var raw = (el.textContent || "").trim();
  var m = raw.match(/^([^0-9]*)([0-9][0-9,.]*)([^0-9]*)$/);
  if(!m) return;
  var prefix = m[1], numTxt = m[2], suffix = m[3];
  var cleaned = numTxt.replace(/,/g, "");
  var target = parseFloat(cleaned);
  if(!isFinite(target) || target === 0) return;
  if(numTxt.indexOf(".") >= 0 && cleaned.split(".")[1].length > 2) return;  /* prices: leave to the flasher */
  var started = performance.now(), dur = Math.min(1000, 420 + Math.log10(Math.max(target,10)) * 120);
  var decimals = (cleaned.split(".")[1] || "").length;
  function frame(now){
    var t = Math.min(1, (now - started) / dur);
    var e = 1 - Math.pow(1 - t, 3);
    var v = target * e;
    if(prefix.indexOf("$") >= 0 || prefix.indexOf("$") === 0){
      el.textContent = prefix + v.toLocaleString(undefined, {minimumFractionDigits:decimals, maximumFractionDigits:decimals}) + suffix;
    } else {
      el.textContent = prefix + Math.round(v).toLocaleString() + suffix;
    }
    if(t < 1) requestAnimationFrame(frame);
    else el.textContent = raw;
  }
  el.textContent = prefix + (0).toFixed(decimals) + suffix;
  requestAnimationFrame(frame);
}
function animateAll(root){
  if(!MOTION) return;
  Array.prototype.forEach.call((root || document).querySelectorAll(COUNT_SEL), function(el){
    if(el.dataset.counted === el.textContent) return;
    el.dataset.counted = el.textContent;
    animateNumber(el);
  });
}

/* =========================== 3. price flashes =========================== */
var lastPrice = {};
function flashPrices(root){
  if(!MOTION) return;
  Array.prototype.forEach.call((root || document).querySelectorAll(".coin[data-coin]"), function(card){
    var px = card.querySelector(".px"), sym = card.getAttribute("data-coin");
    if(!px) return;
    var now = (px.textContent || "").replace(/[^0-9.]/g, "");
    if(lastPrice[sym] && lastPrice[sym] !== now){
      var up = parseFloat(now) > parseFloat(lastPrice[sym]);
      px.classList.remove("flash-up", "flash-down");
      void px.offsetWidth;
      px.classList.add(up ? "flash-up" : "flash-down");
    }
    lastPrice[sym] = now;
  });
}

/* =========================== 4. sparkle bursts =========================== */
function sparkAt(x, y, n, colours){
  var tints = colours || ["#a78bfa", "#22d3ee", "#f472b6", "#34d399", "#fbbf24"];
  for(var i=0;i<n;i++){
    var s = document.createElement("i");
    s.className = "sparkle";
    var ang = (Math.PI * 2 * i / n) + Math.random() * 0.5;
    var dist = 30 + Math.random() * 46;
    s.style.left = x + "px"; s.style.top = y + "px";
    s.style.setProperty("--dx", (Math.cos(ang) * dist).toFixed(1) + "px");
    s.style.setProperty("--dy", (Math.sin(ang) * dist).toFixed(1) + "px");
    s.style.background = "radial-gradient(circle, #fff, " + tints[i % tints.length] + " 60%, transparent)";
    s.style.width = s.style.height = (5 + Math.random() * 6).toFixed(1) + "px";
    document.body.appendChild(s);
    (function(node){ setTimeout(function(){ node.remove(); }, 1000); })(s);
  }
}
W.spark = function(x, y, n, colours){ if(!MOTION) return; sparkAt(x, y, n || 6, colours); };
W.burst = function(el, colours){
  if(!MOTION || !el) return;
  var r = el.getBoundingClientRect ? el.getBoundingClientRect() : null;
  sparkAt(r ? r.left + r.width / 2 : window.innerWidth / 2,
          r ? r.top + r.height / 2 : window.innerHeight / 2, 12, colours);
};

/* =========================== 5. directional view transitions =========================== */
var ORDER = ["home","words","seeds","wallet","market","vault","about"];
var prevIdx = ORDER.indexOf(ST.view);
W.onGo = function(v){
  var idx = ORDER.indexOf(v);
  var fromLeft = idx >= 0 && prevIdx >= 0 && idx < prevIdx;
  var view = $("#v-" + v);
  if(view){
    view.classList.toggle("from-left", fromLeft);
    /* restart the animation so rapid tab switching always feels alive */
    view.style.animation = "none";
    void view.offsetWidth;
    view.style.animation = "";
  }
  prevIdx = idx;
  setTimeout(function(){ prime(view || document.body); animateAll(view || document); flashPrices(view || document); }, 30);
};

/* =========================== 6. trending (real usage from the backend) =========================== */
var trendTries = 0, trendSeq = 0;
function renderTrendingWhenReady(){
  if(Net.online || Net.booted) return renderTrending();   /* probe finished → live or the offline note */
  if(trendTries++ > 30) return renderTrending();
  setTimeout(renderTrendingWhenReady, 200);
}
async function renderTrending(){
  var box = $("#trending");
  if(!box) return;
  var seq = ++trendSeq;                      /* an older, slower answer must never overwrite a newer one */
  if(!Net.online){
    box.innerHTML = '<div class="card glass"><div class="empty" style="padding:8px">Trending is powered by the backend — it shows which words people are actually opening. Offline, enjoy the full dictionary instead.</div></div>';
    return;
  }
  if(!box.querySelector(".list, .rowitem")){
    box.innerHTML = '<div class="coingrid"><div class="skel"></div><div class="skel"></div></div>';
  }
  var r = null;
  try{ r = await Net.req("GET", "/api/trending?limit=6", null, 6000, true); }catch(e){}
  if(seq !== trendSeq) return;               /* a newer render is already on its way */
  var items = (r && r.items) || [];
  if(!items.length){
    box.innerHTML = '<div class="card glass"><div class="empty" style="padding:8px">No reads recorded yet on this backend — open a few words and this table fills up with the real ranking.</div></div>';
    $("#trendNote") && ($("#trendNote").textContent = "live");
    setTimeout(function(){ if(seq === trendSeq) renderTrending(); }, 4000);   /* keep watching for the first read */
    return;
  }
  $("#trendNote") && ($("#trendNote").textContent = "live · " + items.length);
  box.innerHTML = '<div class="list">' + items.map(function(t, i){
    return '<div class="rowitem ripple" data-open-term="' + esc(t.n) + '">' +
      '<div class="av ' + "abcde"[i % 5] + '">' + (i + 1) + '</div>' +
      '<div style="min-width:0"><div class="nm">' + esc(t.n) + '</div><div class="mt">' + esc(t.c) + ' · ' + W.LEVELS[t.l] + '</div></div>' +
      '<span class="hits">' + t.hits + ' read' + (t.hits === 1 ? "" : "s") + '</span></div>';
  }).join("") + '</div>';
}

/* =========================== 7. the word wall =========================== */
function wallWords(filter, q){
  var out = [];
  for(var i=0;i<2048;i++){
    var s = SEEDS[i];
    if(q && s.w.indexOf(q) < 0) continue;
    if(filter === "known" && ST.known.indexOf(i) < 0) continue;
    if(filter === "def" && !s.t) continue;
    out.push(i);
  }
  return out;
}
W.paneWall = function(){
  var filter = W.wallFilter || "all", q = (W.wallQ || "").trim().toLowerCase();
  var ids = wallWords(filter, q);
  var learned = ST.known.length;
  var html =
    '<div class="card glass tint">' +
      '<span class="pill c">The word wall</span>' +
      '<h3 style="margin:10px 0 5px;font-size:20px;letter-spacing:-.03em;font-weight:800">All 2,048 words, one wall</h3>' +
      '<p style="margin:0;font-size:13px;color:#c9d1e6">The complete BIP-39 list laid out flat — the same 2,048 words every wallet on earth uses to build a recovery phrase. Tap any word for its position, neighbours and meaning.</p>' +
      '<div class="acts"><button class="btn pri" id="wallStart">' + ICON("i-key") + 'Start reading the wall</button>' +
      '<button class="btn" id="wallRandom">' + ICON("i-dice") + 'Random word</button></div>' +
    '</div>' +
    '<div class="search" style="position:static;margin-top:12px">' + ICON("i-search") +
      '<input id="wq" type="search" placeholder="Find a word on the wall…" value="' + esc(W.wallQ || "") + '" autocapitalize="off" autocorrect="off" spellcheck="false">' +
      '<button class="clr' + (W.wallQ ? "" : "") + '" id="wqClear">✕</button></div>' +
    '<div class="filters" style="padding:10px 0 4px">' +
      [["all","All 2,048"],["known",learned + " learned"],["def",W.stats.seedDefs + " defined"]].map(function(p){
        return '<button class="s' + (filter === p[0] ? " on" : "") + '" data-wf="' + p[0] + '">' + p[1] + '</button>';
      }).join("") +
      '<span class="s" style="pointer-events:none">' + ids.length + ' shown</span>' +
    '</div>' +
    '<div class="wall" id="wall">' + ids.map(function(i){
      var s = SEEDS[i], kn = ST.known.indexOf(i) >= 0;
      return '<span class="ww' + (kn ? " known" : "") + (s.t ? " def" : "") + '" data-fill-seed="' + i + '">' + esc(s.w) + '</span>';
    }).join("") + '</div>';
  $("#seedPane").innerHTML = html;
  $$("#seedPane [data-wf]").forEach(function(b){
    b.addEventListener("click", function(){ W.wallFilter = b.dataset.wf; W.paneWall(); haptic(); });
  });
  var wq = $("#wq");
  wq.addEventListener("input", function(){
    W.wallQ = this.value; var pos = this.selectionStart;
    W.paneWall();
    var n = $("#wq"); if(n){ n.focus(); try{ n.setSelectionRange(pos, pos); }catch(e){} }
  });
  $("#wqClear").addEventListener("click", function(){ W.wallQ = ""; W.paneWall(); });
  $("#wallRandom").addEventListener("click", function(){
    var i = Math.floor(Math.random() * 2048);
    W.openSeed(i); W.burst($("#wallRandom"));
  });
  $("#wallStart").addEventListener("click", function(){
    var wall = $("#wall");
    if(!wall) return;
    var first = wall.querySelectorAll(".ww.known").length ? 0 : 0;
    var idx = ST.known.length ? Math.max.apply(null, ST.known) + 1 : 0;
    var target = wall.children[Math.min(idx, wall.children.length - 1)];
    if(target){
      target.scrollIntoView({behavior:"smooth", block:"center"});
      target.classList.add("known");
      setTimeout(function(){ W.openSeed(Math.min(idx, 2047)); }, 420);
    }
  });
  prime($("#seedPane"));
  if(MOTION) $("#seedPane").classList.add("in");
};
function wallPreview(){
  var box = $("#wallPreview");
  if(!box) return;
  var pool = shuffle(SEEDS.map(function(s){ return s.w; })).slice(0, 60);
  var rail = pool.concat(pool).map(function(w){
    var s = SEED_BY_WORD[w], kn = s && ST.known.indexOf(s.i) >= 0;
    return '<span class="' + (kn ? "k" : (s && s.t ? "d" : "")) + '">' + esc(w) + '</span>';
  }).join("");
  box.innerHTML =
    '<div class="spread"><span class="pill">2,048 words · the world list</span><span style="font-size:11px;color:var(--muted-2)">' + ST.known.length + ' learned</span></div>' +
    '<div class="wordrail" style="margin-top:12px"><div class="inner">' + rail + '</div></div>' +
    '<div class="prog"><i style="width:' + (ST.known.length / 2048 * 100) + '%"></i></div>' +
    '<div class="acts"><button class="btn pri" id="openWall">' + ICON("i-key") + 'Open the wall</button>' +
    '<button class="btn" id="wallShuffle">' + ICON("i-refresh") + 'Reshuffle</button></div>';
  $("#openWall").addEventListener("click", function(){
    ST.seedTab = "wall"; save();
    W.rendered.seeds = 0; W.go("seeds");
  });
  $("#wallShuffle").addEventListener("click", function(){ wallPreview(); haptic(); });
}

/* =========================== 8. wrap the home renderer =========================== */
var origHome = W.RENDER.home;                 /* the function the router actually calls */
W.RENDER.home = W.homeRender = function(){
  origHome.apply(this, arguments);
  wallPreview();
  renderTrendingWhenReady();
};

/* give every meaningful tap its sparkle */
document.addEventListener("click", function(e){
  var c = e.target.closest; if(!c) return;
  var el = c.call(e.target, "[data-know]");
  if(el && /Learned/.test(el.textContent)) W.burst(el, ["#34d399","#22d3ee","#a78bfa"]);
  var sv = c.call(e.target, "[data-save]");
  if(sv && /Saved/.test(sv.textContent)) W.burst(sv, ["#fbbf24","#a78bfa","#22d3ee"]);
  var rnd = c.call(e.target, "#btnRandom, #wallRandom, #wallShuffle");
  if(rnd) W.burst(rnd);
  var tab = c.call(e.target, ".tabbtn");
  if(tab){
    var r = tab.getBoundingClientRect();
    W.spark(r.left + r.width / 2, r.top + 4, 5);
  }
  if(c.call(e.target, "#seedSeg button")) haptic();
});
["#pCheck","#fKnow"].forEach(function(sel){
  document.addEventListener("click", function(e){
    var el = e.target.closest && e.target.closest(sel);
    if(el) setTimeout(function(){ if($("#pMsg") && /Correct order/.test($("#pMsg").textContent)) W.burst(el); }, 60);
  });
});

/* =========================== 9. periodic motion housekeeping =========================== */
setInterval(function(){ animateAll(document); flashPrices(document); }, 60000);
setInterval(function(){
  if(!Net.online) return;
  var b = $("#trending");
  if(b && /backend|No reads recorded/.test(b.textContent)) { trendTries = 0; renderTrending(); }
}, 20000);

/* first paint: fill the two home widgets the earlier scripts don't know about,
   then run one reveal/number/flash pass over whatever is on screen */
if((ST.view || "home") === "home"){ wallPreview(); renderTrendingWhenReady(); }
setTimeout(function(){ prime(document.body); animateAll(document); flashPrices(document); }, 60);
console.log("%cWordVault", "color:#a78bfa;font-weight:700", "motion engine online · " + TERMS.length + " terms · 2,048 seed words");
})();
