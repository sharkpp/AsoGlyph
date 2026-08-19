import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetManifest, AssetBundle, rootBundle;

import '../word/word_book_export.dart';

/// アプリに入っている辞書の読み出し口（SPEC 7.4.3）。
///
/// 差し替えられるようにしてあるのは、テストで資産そのものを入れ替えるため。
/// 資産は実行ファイルの中にあり、テストからは書き換えられない。
abstract interface class BundledAssets {
  /// 辞書として読む資産の並び。
  Future<List<String>> list();

  Future<String> loadString(String path);
  Future<Uint8List> load(String path);
}

/// アプリに焼き込まれた資産を読む [BundledAssets]。
class AppBundledAssets implements BundledAssets {
  const AppBundledAssets([AssetBundle? bundle]) : _bundle = bundle;

  /// 内蔵の辞書を置く場所。
  static const dir = 'assets/words/';

  /// 動作確認用の辞書の目印。
  ///
  /// **ファイル名が `_` で始まるものは、デバッグでだけ読む。**
  /// リポジトリにも入れない（`.gitignore`）ので、素の取得から作った
  /// リリースには存在しない。手元で試す辞書を、配るものに混ぜないため。
  static bool isDebugAsset(String path) => path.split('/').last.startsWith('_');

  static bool isWordBook(String path) =>
      path.endsWith('.yaml') ||
      path.endsWith('.yml') ||
      path.endsWith('.$wordBookBundleExtension');

  /// 省くとアプリの資産（[rootBundle]）を読む。
  final AssetBundle? _bundle;

  AssetBundle get _from => _bundle ?? rootBundle;

  /// 一覧は資産そのものから引く。並びを手で持つと、辞書を足したときに
  /// 書き足し忘れて出てこない。
  @override
  Future<List<String>> list() async {
    final manifest = await AssetManifest.loadFromAssetBundle(_from);
    final assets =
        manifest
            .listAssets()
            .where((path) => path.startsWith(dir))
            .where(isWordBook)
            // 動作確認用はデバッグでだけ読む。
            .where((path) => kDebugMode || !isDebugAsset(path))
            .toList()
          ..sort();
    // 動作確認用はうしろに寄せる。配る辞書の並びを、手元の都合で崩さない。
    return [
      ...assets.where((path) => !isDebugAsset(path)),
      ...assets.where(isDebugAsset),
    ];
  }

  @override
  Future<String> loadString(String path) => _from.loadString(path);

  @override
  Future<Uint8List> load(String path) async =>
      (await _from.load(path)).buffer.asUint8List();
}
