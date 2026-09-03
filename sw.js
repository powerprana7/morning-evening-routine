/* 서비스 워커 — 오프라인 실행용 (B-14)
 *
 * 전략: 네트워크 우선, 실패하면 캐시.
 *   캐시 우선으로 하면 GitHub 에 push 한 수정이 기기에 며칠씩 안 내려간다.
 *   이 앱에서 "전 기기가 같은 루틴을 본다"는 것이 오프라인보다 중요하므로,
 *   항상 새것을 먼저 받아보고 안 되면(비행기 모드 등) 캐시를 쓴다.
 */
const CACHE = 'routine-v4';
const ASSETS = ['./', './index.html', './manifest.webmanifest',
                './icon-192.png', './icon-512.png',
                './icon-inset-192.png', './icon-inset-512.png'];

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
  const req = e.request;
  if (req.method !== 'GET') return;
  if (new URL(req.url).origin !== location.origin) return;

  // cache: 'reload' 로 브라우저 HTTP 캐시를 건너뛴다.
  //   GitHub Pages 가 max-age=600 을 보내기 때문에, 그냥 fetch 하면 10분 동안
  //   낡은 파일이 돌아올 수 있다. 파일이 40KB 남짓이라 매번 받아도 부담이 없고,
  //   "전 기기가 같은 루틴을 본다"(D-014)가 절약보다 중요하다.
  const fresh = new Request(req.url, { cache: 'reload', credentials: 'same-origin' });

  e.respondWith(
    fetch(fresh)
      .then((res) => {
        // 받아온 것을 캐시에 갱신해 둔다 (다음 오프라인 대비)
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      })
      .catch(() => caches.match(req).then((hit) => hit || caches.match('./index.html')))
  );
});
