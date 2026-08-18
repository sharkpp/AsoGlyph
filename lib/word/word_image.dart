/// 語に添える絵（SPEC 7.4）。
///
/// 字が読めない子は、絵でしか語を選べない。読みを声で聞かせるだけでは、
/// 一覧から選ぶという操作が成り立たない。
library;

/// 受ける形式。
///
/// 写真そのものではなく「その語を表す絵」を入れてもらうためのもの。
/// SVG も受けるのは、線画のほうが小さくて幼児にも分かりやすいため。
///
/// WebP は同じ絵が PNG・JPEG より小さくなる。容量で切っている（[maxImageBytes]）
/// ので、同じ絵でも WebP なら通ることがある。
const imageExtensions = ['png', 'jpg', 'jpeg', 'webp', 'svg'];

/// 1 枚の上限（バイト）。
///
/// **大きさ（画素数）ではなく容量で切る。** 画素数で切ると、線画の SVG のように
/// 画素を持たない絵を測れない。容量なら、どの形式でも同じ物差しで測れる。
///
/// 512 KB は、その語が分かる絵には十分で、30 語入れても 15 MB に収まる線。
/// 端末の中だけで完結する（SPEC 3）ので、通信量ではなく端末の空きが上限になる。
const maxImageBytes = 512 * 1024;

/// 縮小はしない。入れた絵がそのまま残る。
///
/// 勝手に縮めると、親が選んだ絵と出てくる絵が違うものになる。大きすぎる絵は
/// 断って、何 KB あったかを見せる。
String describeSize(int bytes) => '${(bytes / 1024).round()} KB';

/// この拡張子を受けるか。
bool isSupportedImage(String fileName) =>
    imageExtensions.contains(extensionOf(fileName));

/// ファイル名から拡張子（小文字・ドット無し）。
String extensionOf(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
}

/// SVG は描き方が違う。ラスタと同じ部品では出せない。
bool isSvg(String fileName) => extensionOf(fileName) == 'svg';
