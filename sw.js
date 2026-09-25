// Service worker for Daily Climb. The HTML is fetched network-first so code updates
// land immediately; static assets (dictionary, icons) are cache-first for a
// fast, offline-capable launch. Firebase / Datamuse / gstatic always hit the
// network.
const CACHE = "wadder-shell-v5"; // bump to re-fetch cached assets (v5: climbs.js 765->746 seeds; Daily Ascent colors in manifest + icons)
const ASSETS = [
  "./words.js",
  "./freq.js",
  "./climbs.js",
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
    // Network-first, and skip the browser's HTTP cache entirely — GitHub Pages
    // serves HTML with ~10min max-age, which otherwise lets a stale page through
    // even on a "network-first" fetch. Fall back to the cached shell offline.
    e.respondWith(
      fetch("./index.html", { cache: "no-store" })
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

// ---- Daily reminders ----
// The hourly sender (tools/reminders/send.mjs, run by GitHub Actions) pushes
// through Firebase Cloud Messaging. We don't load Firebase's own SW script,
// so this handler shows the notification itself. Every push must show one
// (Safari revokes push permission from sites that stay silent).
self.addEventListener("push", (e) => {
  let p = {};
  try { p = e.data ? e.data.json() : {}; } catch (err) {}
  const n = p.notification || {};
  const d = p.data || {};
  // One line only: "Today's climb is waiting ⛰️" (the phone shows the app name above it).
  const title = n.title || d.title || "Today's climb is waiting ⛰️";
  const body = n.body || d.body || "";
  e.waitUntil(self.registration.showNotification(title, {
    body,
    icon: "./icon-192.png",
    badge: "./icon-192.png",
    tag: "daily-reminder", // a newer reminder replaces an unread one
    data: { url: d.url || "./" },
  }));
});

// Tapping the reminder focuses the game if it's already open, else opens it.
self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./", self.registration.scope).href;
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
      for (const c of list) {
        if (c.url.startsWith(self.registration.scope) && "focus" in c) return c.focus();
      }
      return self.clients.openWindow(url);
    })
  );
});
