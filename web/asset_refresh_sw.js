// Render serves /assets/* as immutable for a year, so a phone keeps the
// fonts and manifests of its first visit. Revalidate them on every load;
// fall back to the cached copy when offline.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;
  if (!url.pathname.includes('/assets/')) return;
  event.respondWith(
    fetch(request, { cache: 'no-cache' }).catch(() =>
      fetch(request, { cache: 'force-cache' })
    )
  );
});
