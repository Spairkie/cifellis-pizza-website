/*
 * Marketing site service worker: network-first app shell caching so the
 * page still opens if a phone briefly loses signal, but always prefers a
 * fresh copy when online. Bump CACHE_NAME on a deploy you want picked up
 * immediately.
 */
const CACHE_NAME = 'cifellis-site-v2';
const SHELL_FILES = ['./', './index.html', './manifest.webmanifest', './icons/icon-192.png', './icons/icon-512.png'];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(SHELL_FILES)).catch(() => {})
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((names) =>
      Promise.all(names.filter((n) => n !== CACHE_NAME).map((n) => caches.delete(n)))
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(async () => {
        // The app-shell fallback (index.html) only ever makes sense for a
        // page navigation -- a failed JS/CSS/image/font/etc. request must
        // stay a normal network failure, never silently receive HTML back
        // (a script tag getting an HTML response for its .js request fails
        // with a confusing parse error, not a clear "offline" signal).
        const cached = await caches.match(req);
        if (cached) return cached;
        if (req.mode === 'navigate') {
          const shell = await caches.match('./index.html');
          if (shell) return shell;
        }
        throw new Error('Network request failed and nothing cached for ' + req.url);
      })
  );
});
