// Service worker for 3·2·1. The HTML is fetched network-first so code updates
// land immediately; static assets (dictionary, icons) are cache-first for a
// fast, offline-capable launch. Firebase / Datamuse / gstatic always hit the
// network.
const CACHE = "three21-shell-v2";
const ASSETS = [
  "./words.js",
  "./freq.js",
  "./firebase-config.js",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  // Only same-origin GETs — never intercept Firestore, Datamuse, the Firebase CDN, etc.
  if (req.method !== "GET" || url.origin !== location.origin) return;

  const isHTML = req.mode === "navigate" ||
    (req.headers.get("accept") || "").includes("text/html") ||
    url.pathname.endsWith("/") || url.pathname.endsWith(".html");

  if (isHTML) {
    // Network-first: always try for the latest page, fall back to cache offline.
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put("./index.html", copy));
          return res;
        })
        .catch(() => caches.match("./index.html"))
    );
    return;
  }

  // Everything else: cache-first, fill the cache on miss.
  e.respondWith(
    caches.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        if (res && res.ok) {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put(req, copy));
        }
        return res;
      });
    })
  );
});
