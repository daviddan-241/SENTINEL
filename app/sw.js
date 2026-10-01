/* =========================================================================
   WordVault service worker — build __VERSION__
   Only one job: keep the app itself available when there is no network.

   * navigations and .html  -> network first, cache fallback (always fresh when online)
   * /api/ or cross-origin  -> never touched, the app already handles offline itself
   * everything else        -> cache first, refreshed in the background
   ========================================================================= */
var VERSION = "__VERSION__";
var CACHE = "wordvault-" + VERSION;
var SHELL = ["./", "./index.html", "./manifest.webmanifest"];

self.addEventListener("install", function(e){
  e.waitUntil(
    caches.open(CACHE)
      .then(function(c){ return c.addAll(SHELL); })
      .catch(function(){})
      .then(function(){ return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function(e){
  e.waitUntil(
    caches.keys()
      .then(function(keys){
        return Promise.all(keys.filter(function(k){ return k !== CACHE; })
                               .map(function(k){ return caches.delete(k); }));
      })
      .then(function(){ return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function(e){
  var req = e.request;
  if(req.method !== "GET") return;

  var url;
  try{ url = new URL(req.url); }catch(err){ return; }
  if(url.origin !== self.location.origin) return;            /* prices are fetched by the server, not the page */
  if(url.pathname.indexOf("/api/") >= 0) return;             /* live data must never come from a cache */

  var isDoc = req.mode === "navigate" ||
              /\.html?$/.test(url.pathname) ||
              url.pathname.slice(-1) === "/";

  if(isDoc){
    e.respondWith(
      fetch(req).then(function(r){
        var copy = r.clone();
        caches.open(CACHE).then(function(c){ c.put("./index.html", copy); }).catch(function(){});
        return r;
      }).catch(function(){
        return caches.match("./index.html").then(function(hit){
          return hit || caches.match("./") || new Response(
            "<!doctype html><meta name=viewport content='width=device-width,initial-scale=1'>" +
            "<body style='background:#06070c;color:#e8ecf6;font:16px/1.6 -apple-system,system-ui;padding:28px'>" +
            "<h2>WordVault</h2><p>This device has not finished saving the offline copy yet. " +
            "Open the app once with a connection, then it will work offline.</p></body>",
            {headers: {"Content-Type": "text/html; charset=utf-8"}});
        });
      })
    );
    return;
  }

  e.respondWith(
    caches.match(req).then(function(hit){
      var live = fetch(req).then(function(r){
        if(r && r.ok){
          var copy = r.clone();
          caches.open(CACHE).then(function(c){ c.put(req, copy); }).catch(function(){});
        }
        return r;
      }).catch(function(){ return hit; });
      return hit || live;
    })
  );
});
