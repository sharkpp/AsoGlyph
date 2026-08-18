// あそんでフォントのサービスワーカー。
//
// Flutter が用意していたものは 3.44 で非推奨になり、中身は「自分を登録解除
// するだけ」になった。オフラインで開けるようにするには自前で持つしかない。
//
// **取りに行ってから、駄目ならキャッシュ**（network-first）にしてある。
// 逆（cache-first）は速いが、こちらの作りとは相性が悪い:
//
//   - Flutter の出力はファイル名に中身の指紋が付かない。main.dart.js も
//     assets/ も、新しくしても名前が変わらない
//   - だからキャッシュを先に見ると、直したはずのものが古いまま出続ける。
//     しかも直す手立てが利用者側にしかない（サイトのデータを消す）
//
// network-first なら、こちらが直せば次にオンラインで開いたときに必ず治る。
// 速さは HTTP キャッシュ（304）に任せる。
const CACHE = 'asoglyph-v1';

self.addEventListener('install', () => {
  // 前のものを待たずに入れ替える。古い版を配り続ける時間を短くする。
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    (async () => {
      for (const key of await caches.keys()) {
        if (key !== CACHE) await caches.delete(key);
      }
      await self.clients.claim();
    })()
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;

  // 触るのは自分のところの GET だけ。
  if (request.method !== 'GET') return;
  if (new URL(request.url).origin !== self.location.origin) return;
  // 途中だけを求める要求（canvaskit の wasm など）は、そのまま通す。
  // 部分的な応答を溜めると、次に丸ごと欲しいときに壊れて返る。
  if (request.headers.has('range')) return;

  event.respondWith(
    (async () => {
      try {
        const response = await fetch(request);
        // 丸ごと返ってきた自分のところの応答だけ溜める。
        if (response && response.status === 200 && response.type === 'basic') {
          const cache = await caches.open(CACHE);
          await cache.put(request, response.clone());
        }
        return response;
      } catch (error) {
        const cached = await caches.match(request);
        if (cached) return cached;
        // 画面を開こうとしているなら、入口を返す。オフラインで
        // ホーム画面から起動したときにここへ来る。
        if (request.mode === 'navigate') {
          const shell = await caches.match('index.html');
          if (shell) return shell;
        }
        throw error;
      }
    })()
  );
});
