/* UNO Airways — offline support (service worker)
   - pages: network first (3.5 s), then the saved copy, so updates still arrive
   - libraries, fonts, photos: saved copy first, refreshed in the background
   - dish photos and videos: the page downloads them all in advance into "uno-media";
     videos are served from it with byte ranges, so they play without internet
   - menu data and calls (Supabase API) are never cached here: the app keeps its own copy */
var VERSION = "uno-v138";
var MEDIA = "uno-media-v1";
var CORE = ["./", "index.html", "davomat.html", "manifest.webmanifest", "media/logo.png", "media/emblem.png", "icons/menu-192.png", "icons/menu-512.png", "icons/menu-180.png", "icons/menu-maskable-512.png", "icons/menu-maskable-192.png", "media/n-stars.webp", "media/n-stars2.webp", "media/n-starsr.webp", "media/n-aur1.webp", "media/n-aur2.webp", "media/n-aur1r.webp", "media/n-aur2r.webp", "media/n-waves.webp", "media/city-lights.svg"];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(VERSION).then(function (c) { return c.addAll(CORE).catch(function () {}); }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (keys) {
    return Promise.all(keys.filter(function (k) { return k !== VERSION && k !== MEDIA; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function timeout(ms) { return new Promise(function (_, rej) { setTimeout(function () { rej(new Error("timeout")); }, ms); }); }

function networkFirst(req, ms) {
  return caches.open(VERSION).then(function (cache) {
    /* bypass the browser's HTTP cache for pages, so a new version shows up on the next open */
    var fresh = new Request(req.url, { cache: "no-store", credentials: "same-origin" });
    return Promise.race([fetch(fresh), timeout(ms)]).then(function (res) {
      if (res && res.ok) cache.put(req, res.clone());
      return res;
    }).catch(function () {
      return cache.match(req, { ignoreSearch: req.mode === "navigate" }).then(function (hit) {
        return hit || cache.match("index.html") || cache.match("./") || Response.error();
      });
    });
  });
}

function cacheFirst(req, store) {
  return caches.match(req).then(function (hit) {
    var net = fetch(req).then(function (res) {
      if (res && (res.ok || res.type === "opaque")) caches.open(store || VERSION).then(function (c) { c.put(req, res.clone()); });
      return res;
    }).catch(function () { return hit || Response.error(); });
    if (hit) { net.catch(function () {}); return hit; }
    return net;
  });
}

/* uploaded photos never change under the same name: once saved, never download again */
function storedOnly(req) {
  return caches.match(req.url).then(function (hit) {
    if (hit) return hit;
    return fetch(req).then(function (res) {
      if (res && (res.ok || res.type === "opaque")) { var cp = res.clone(); caches.open(MEDIA).then(function (c) { c.put(req.url, cp); }); }
      return res;
    });
  });
}

/* serve a saved video, honouring "Range: bytes=a-b" so the <video> element can seek */
function rangeFromCache(req) {
  return caches.match(req.url).then(function (hit) {
    if (!hit) return fetch(req);
    var range = req.headers.get("range");
    if (!range) return hit;
    return hit.blob().then(function (blob) {
      var m = /bytes=(\d*)-(\d*)/.exec(range) || [], size = blob.size;
      var start = m[1] ? parseInt(m[1], 10) : 0;
      var end = m[2] ? Math.min(parseInt(m[2], 10), size - 1) : size - 1;
      if (!m[1] && m[2]) { start = Math.max(0, size - parseInt(m[2], 10)); end = size - 1; }
      if (start >= size) return new Response(null, { status: 416, headers: { "Content-Range": "bytes */" + size } });
      return new Response(blob.slice(start, end + 1), {
        status: 206,
        headers: {
          "Content-Type": hit.headers.get("Content-Type") || "video/mp4",
          "Content-Length": String(end - start + 1),
          "Content-Range": "bytes " + start + "-" + end + "/" + size,
          "Accept-Ranges": "bytes"
        }
      });
    });
  });
}

self.addEventListener("fetch", function (e) {
  var req = e.request;
  if (req.method !== "GET") return;
  var url = new URL(req.url);
  var isVideo = /\.(mp4|webm|mov|m4v)$/i.test(url.pathname);

  if (url.origin === self.location.origin) {
    if (req.mode === "navigate" || /\.(html|webmanifest)$/.test(url.pathname) || url.pathname.endsWith("/")) {
      e.respondWith(networkFirst(req, 3500));
    } else if (/seed\.json$/.test(url.pathname)) {
      return;
    } else if (isVideo || req.headers.has("range")) {
      e.respondWith(rangeFromCache(req));
    } else {
      e.respondWith(cacheFirst(req));
    }
    return;
  }
  if (url.hostname === "cdn.jsdelivr.net" || url.hostname === "unpkg.com" || url.hostname === "fonts.googleapis.com" || url.hostname === "fonts.gstatic.com") {
    e.respondWith(cacheFirst(req));
    return;
  }
  if (/\.supabase\.co$/.test(url.hostname) && url.pathname.indexOf("/storage/v1/object/public/") === 0) {
    if (isVideo || req.headers.has("range")) e.respondWith(rangeFromCache(req));
    else e.respondWith(storedOnly(req));
    return;
  }
  // everything else (Supabase API, realtime, Telegram…): straight to the network
});
