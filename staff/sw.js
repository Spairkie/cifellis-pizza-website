/*
 * Staff Hub service worker.
 *
 * Same strategy as the Customer Kiosk's service worker (order/sw.js):
 * network-first for the app shell, falling back to cache only when
 * offline, and never touching Supabase requests (different origin) so
 * live order data is always read and written fresh.
 */
const CACHE_NAME = 'cifellis-staff-hub-v1';
const SHELL_FILES = [
  './',
  './index.html',
  '../order/db-supabase.js',
  '../order/supabase-config.js',
  './manifest.webmanifest',
  '../order/icons/icon-192.png',
  '../order/icons/icon-512.png',
];

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
  // Only handle same-origin GET requests for the app shell. Everything
  // else (Supabase API/realtime calls, fonts CDN, POST/PUT, etc.) passes
  // straight through to the network untouched.
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

  event.respondWith(
    fetch(req)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE_NAME).then((cache) => cache.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(req).then((cached) => cached || caches.match('./index.html')))
  );
});
