/* UNO Airways — offline cache (service worker)
   - pages: network first (3.5 s), then the saved copy, so updates still arrive
   - libraries, fonts, photos: saved copy first, refreshed in the background
   - menu data and calls (Supabase API) are never cached here: the app keeps its own copy */
var VERSION = "uno-v1";
var CORE = ["./", "index.html", "manifest.webmanifest", "media/logo.png", "icons/menu-192.png", "icons/menu-512.png", "icons/menu-180.png"];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(CORE).catch(function () {}); }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== VERSION; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function timeout(ms) { return new Promise(function (_, rej) { setTimeout(function () { rej(new Error("timeout")); }, ms); }); }

function networkFirst(req, ms) {
  return caches.open(VERSION).then(function (cache) {
    return Promise.race([fetch(req), timeout(ms)]).then(function (res) {
      if (res && res.ok) cache.put(req, res.clone());
      return res;
    }).catch(function () {
      return cache.match(req, { ignoreSearch: req.mode === "navigate" }).then(function (hit) {
        return hit || cache.match("index.html") || cache.match("./") || Response.error();
      });
    });
  });
}

function cacheFirst(req) {
  return caches.open(VERSION).then(function (cache) {
    return cache.match(req).then(function (hit) {
      var net = fetch(req).then(function (res) {
        if (res && (res.ok || res.type === "opaque")) cache.put(req, res.clone());
        return res;
      }).catch(function () { return hit || Response.error(); });
      return hit || net;
    });
  });
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);

  // videos use range requests: leave them to the network
  if (req.headers.has("range") || /\.(mp4|webm|mov|m4v)(\?|$)/i.test(url.pathname)) return;

  if (url.origin === self.location.origin) {
    if (req.mode === "navigate" || /\.(html|webmanifest)$/.test(url.pathname) || url.pathname.endsWith("/")) {
      e.respondWith(networkFirst(req, 3500));
    } else if (/seed\.json$/.test(url.pathname)) {
      return;
    } else {
      e.respondWith(cacheFirst(req));
    }
    return;
  }
  if (url.hostname === "cdn.jsdelivr.net" || url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
    e.respondWith(cacheFirst(req));
    return;
  }
  if (/\.supabase\.co$/.test(url.hostname) && url.pathname.indexOf("/storage/v1/object/public/") === 0) {
    e.respondWith(cacheFirst(req));
    return;
  }
  // everything else (Supabase API, realtime, Telegram…): straight to the network
});
