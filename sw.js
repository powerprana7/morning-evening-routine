/* 서비스 워커 — 오프라인 실행용 (B-14)
 *
 * 전략: 네트워크 우선, 실패하면 캐시.
 *   캐시 우선으로 하면 GitHub 에 push 한 수정이 기기에 며칠씩 안 내려간다.
 *   이 앱에서 "전 기기가 같은 루틴을 본다"는 것이 오프라인보다 중요하므로,
 *   항상 새것을 먼저 받아보고 안 되면(비행기 모드 등) 캐시를 쓴다.
 */
const CACHE = 'routine-v6';

/* 미리 담아 둘 것. **아이콘 이름은 여기에 적지 않는다** — 매니페스트에서 읽는다 (D-029).
 *   두 곳에 적어 두면 아이콘이 늘거나 이름이 바뀔 때 한쪽을 잊게 되고,
 *   그 어긋남은 오프라인에서만 조용히 드러나 알아채기 어렵다.
 *   매니페스트의 `src` 에는 지문(`?v=`)이 붙어 있으므로 그대로 가져다 쓴다. */
const BASE = ['./', './index.html', './manifest.webmanifest'];

async function assetList() {
  try {
    const res = await fetch('./manifest.webmanifest', { cache: 'reload' });
    const icons = (await res.json()).icons || [];
    return BASE.concat(icons.map((i) => './' + i.src));
  } catch (e) {
    return BASE;          // 매니페스트를 못 읽어도 설치는 된다
  }
}

self.addEventListener('install', (e) => {
  e.waitUntil(
    assetList()
      .then((list) => caches.open(CACHE).then((c) => c.addAll(list)))
      // 하나라도 못 받으면 캐시는 비워 둔 채 넘어간다. 미리 담기에 실패했다고
      // 서비스워커 설치까지 실패하면, 온라인인데도 앱이 갱신을 못 받게 된다
      .catch(() => {})
      .then(() => self.skipWaiting())
  );
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

/* ═══════════════════════════════════════════════════════════════════
   정해진 시각 알림 — 받는 쪽 (D-033)

   보내는 쪽은 맥의 launchd 다 (`tools/push-send.py`). GitHub Pages 는 정적
   호스팅이라 스스로 시각을 지킬 수 없어서, 시각을 지키는 몫을 맥이 맡는다.

   **오는 신호는 비어 있다.** 문구를 여기서 정하는 이유가 둘이다 —
     ① 내용을 실어 보내려면 보낼 때마다 암호화를 해야 한다. 그 단계가 통째로 없어진다
     ② 문구가 이 파일 안에 있으므로 push 한 번이면 전 기기에 반영된다 (D-014)

   어느 루틴인지는 **받은 시각**으로 가린다. 앱의 `suggestKey()` 와 같은 규칙
   (정오 기준)이라 둘이 어긋나지 않는다.

   ⚠ 이 판단이 옳으려면 **늦게 온 신호가 없어야** 한다. 맥이 잠들었다 깨어나
   오후 1시에 아침 몫을 보내면 여기서는 '이브닝'으로 읽힌다. 그래서 보내는 쪽이
   예정 시각에서 30분이 지나면 아예 안 보낸다 (`GRACE_MINUTES`).
   ═══════════════════════════════════════════════════════════════════ */

const NOTICE = {
  morning: { title: '모닝 루틴',   body: '하루를 여는 자리입니다. 눌러서 시작하세요.' },
  evening: { title: '이브닝 루틴', body: '하루를 닫는 자리입니다. 눌러서 시작하세요.' },
};

/* 알림에 쓸 아이콘 — **이름을 여기에 적지 않는다.** 매니페스트에서 읽는다 (D-029).
   두 곳에 적으면 아이콘 이름이 바뀔 때 한쪽을 잊고, 그 어긋남은 알림에서만
   조용히 드러난다. 먼저 캐시를 보므로 오프라인에서도 되고 빠르다. */
async function noticeIcon() {
  try {
    const c = await caches.open(CACHE);
    const res = (await c.match('./manifest.webmanifest'))
             || (await fetch('./manifest.webmanifest', { cache: 'reload' }));
    const icons = (await res.json()).icons || [];
    const pick = icons.find((i) => (i.purpose || 'any').indexOf('any') >= 0) || icons[0];
    return pick ? './' + pick.src : undefined;
  } catch (err) {
    return undefined;      // 못 읽으면 아이콘 없이 뜬다. 알림 자체는 뜬다
  }
}

self.addEventListener('push', (e) => {
  // 신호는 비어 있는 것이 정상이다. 다만 나중에 내용을 실어 보내게 되더라도
  // 이 코드를 고치지 않아도 되도록, 들어 있으면 그것을 우선한다
  let key = null;
  try {
    if (e.data) key = (e.data.json() || {}).routine || null;
  } catch (err) { /* 내용이 JSON 이 아니면 그냥 시각으로 간다 */ }
  if (key !== 'morning' && key !== 'evening') {
    key = new Date().getHours() < 12 ? 'morning' : 'evening';
  }

  const n = NOTICE[key];
  e.waitUntil(
    noticeIcon().then((icon) =>
      self.registration.showNotification(n.title, {
        body: n.body,
        icon: icon,
        badge: icon,
        tag: 'routine-' + key,   // 같은 루틴 알림이 쌓이지 않고 갈아끼워진다
        renotify: true,
        requireInteraction: true, // 손대기 전까지 안 사라진다. 루틴을 놓치지 않게
        vibrate: [200, 100, 200],
        data: { routine: key },
      })
    )
  );
});

/* 알림을 누르면 그 루틴이 바로 열린다.
   이미 앱이 떠 있으면 그 창을 쓰고, 없으면 새로 연다. */
self.addEventListener('notificationclick', (e) => {
  e.notification.close();
  const key = (e.notification.data || {}).routine || 'morning';
  const target = './?routine=' + key;

  e.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then((list) => {
        for (const c of list) {
          if (c.url.indexOf(self.registration.scope) === 0 && 'focus' in c) {
            // 떠 있는 창에 어느 루틴인지 알려 준다. 새로 여는 것보다 빠르고,
            // 진행 중이던 화면을 날리지 않는다
            c.postMessage({ type: 'open-routine', routine: key });
            return c.focus();
          }
        }
        return self.clients.openWindow(target);
      })
  );
});
