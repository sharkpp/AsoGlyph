// Flutter の読み込みと、サービスワーカーの登録。
//
// 既定のブートストラップは Flutter 製のサービスワーカーを登録する。それは
// 3.44 で非推奨になり、中身は自分を登録解除するだけになった。同じ場所に
// 2 つは登録できないので、それを登録させたままだと自前のものが追い出される。
// ここでは Flutter 側の登録を頼まず（serviceWorkerSettings を渡さない）、
// 自分の sw.js を登録する。
{{flutter_js}}
{{flutter_build_config}}

if ('serviceWorker' in navigator) {
  // 読み込みの邪魔をしない。字が書けることが先で、オフラインは後でよい。
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('sw.js').catch((error) => {
      // 登録できなくてもアプリは動く（http で開いたときなど）。
      console.warn('service worker: ', error);
    });
  });
}

_flutter.loader.load();
