/*
 * Order Hub service worker.
 *
 * Goal: let the app be installed and open instantly (even briefly offline),
 * while never serving stale data. It only ever caches the static app shell
 * (this page's own HTML/JS/icons); it never touches requests to Supabase
 * (a different origin) so orders are always read and written live.
 *
 * Strategy: network-first for the app shell, falling back to the cache
 * only when the network request fails (offline, or a flaky connection).
 * Bump CACHE_NAME when you deploy a change you want clients to pick up
 * a fresh shell for right away.
 */
const CACHE_NAME = 'cifellis-order-hub-v1';
const SHELL_FILES = [
  './',
  './index.html',
  './db-supabase.js',
  './supabase-config.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
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
