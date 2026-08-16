/* 서비스 워커 — 오프라인 실행용 (B-14)
 *
 * 전략: 네트워크 우선, 실패하면 캐시.
 *   캐시 우선으로 하면 GitHub 에 push 한 수정이 기기에 며칠씩 안 내려간다.
 *   이 앱에서 "전 기기가 같은 루틴을 본다"는 것이 오프라인보다 중요하므로,
 *   항상 새것을 먼저 받아보고 안 되면(비행기 모드 등) 캐시를 쓴다.
 */
const CACHE = 'routine-v1';
const ASSETS = ['./', './index.html', './manifest.webmanifest',
                './icon-192.png', './icon-512.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET') return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        // 받아온 것을 캐시에 갱신해 둔다 (다음 오프라인 대비)
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(e.request).then((hit) => hit || caches.match('./index.html')))
  );
});
