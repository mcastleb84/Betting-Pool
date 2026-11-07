// Pool Board service worker: makes the site installable and lets the app open even on a weak connection.
// Pages and config are fetched fresh first (so updates show up right away) and fall back to the saved copy offline.
// Live data (Supabase) is never cached.
const VERSION = 'pool-board-v3';
const SHELL = [
  './',
  './index.html',
  './config.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/apple-touch-icon-180.png',
  './icons/favicon-32.png'
];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(VERSION).then(c => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== VERSION).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Never cache live pool data, logins or chat.
  if (url.hostname.endsWith('supabase.co') || url.hostname.endsWith('supabase.in')) return;

  // Fonts and the Supabase library from the CDN: serve the saved copy, refresh it in the background.
  if (url.hostname === 'cdn.jsdelivr.net' || url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    e.respondWith(caches.open(VERSION).then(async c => {
      const hit = await c.match(req);
      const net = fetch(req).then(r => { if (r.ok || r.type === 'opaque') c.put(req, r.clone()); return r; }).catch(() => hit);
      return hit || net;
    }));
    return;
  }

  // Our own files: network first, saved copy when offline.
  if (url.origin === self.location.origin) {
    e.respondWith(
      fetch(req).then(r => {
        if (r.ok) { const copy = r.clone(); caches.open(VERSION).then(c => c.put(req, copy)); }
        return r;
      }).catch(async () => {
        const c = await caches.open(VERSION);
        return (await c.match(req, { ignoreSearch: req.mode === 'navigate' })) || c.match('./index.html');
      })
    );
  }
});
