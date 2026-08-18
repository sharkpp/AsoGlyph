import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// パスコードの置き場。
///
/// 端末の安全な領域（Keychain / Keystore）に預ける（SPEC 7.6）。
/// 差し替えられるようにしてあるのは、テストでプラットフォームチャネルを
/// 使わないため（[Speaker] と同じ形）。
abstract interface class SecretStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Keychain / Keystore を使う [SecretStore]。
class KeychainSecretStore implements SecretStore {
  const KeychainSecretStore(this.key, [this._storage = const FlutterSecureStorage()]);

  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: key);
}

/// パスコードの掛け先。
///
/// 掛ける先が 2 つあり、それぞれ別のパスコードにする（SPEC 7.5 / 7.6）。
/// 同じにすると、管理画面のパスコードを覚えた子が人の切り替えも通せる。
enum PasscodeKind {
  /// 保護者向け画面のロック（SPEC 7.6）。
  admin(key: 'admin-passcode', asked: 'おうちの人の画面に入るときに聞きます'),

  /// 書く人を切り替えるときのロック（SPEC 7.5）。
  switching(key: 'switch-passcode', asked: '書く人を切り替えるときに聞きます');

  const PasscodeKind({required this.key, required this.asked});

  /// 置き場の鍵。
  final String key;

  /// いつ聞かれるか。設定画面と、聞くときの説明に使う。
  final String asked;
}

/// パスコード（SPEC 7.5 / 7.6）。
///
/// 目的は「子供が親の画面に入らない」「よその人の記録に書かない」こと。
/// 取られて困る秘密を守る仕組みではない。集めた字はここで守られていないし、
/// 守る必要もない（端末内で完結する）。
///
/// 既定は無効。設定して初めて掛かる。
class Passcode extends ChangeNotifier {
  Passcode(this.kind, this._store);

  static Future<Passcode> open(PasscodeKind kind, [SecretStore? store]) async {
    final passcode = Passcode(kind, store ?? KeychainSecretStore(kind.key));
    await passcode.load();
    return passcode;
  }

  final PasscodeKind kind;

  final SecretStore _store;

  String? _code;

  /// パスコードが掛かっているか。
  bool get isSet => _code != null;

  Future<void> load() async {
    _code = await _store.read();
    notifyListeners();
  }

  bool matches(String code) => _code == code;

  Future<void> set(String code) async {
    await _store.write(code);
    _code = code;
    notifyListeners();
  }

  /// パスコードを外す。集めた字も版も消えない。
  Future<void> clear() async {
    await _store.delete();
    _code = null;
    notifyListeners();
  }
}

/// アプリに掛けられるロックひとそろい。
///
/// 画面へ 2 つ別々に配って回すと、片方だけ渡し忘れた画面ができる。
class Locks {
  const Locks({required this.admin, required this.switching});

  static Future<Locks> open() async => Locks(
    admin: await Passcode.open(PasscodeKind.admin),
    switching: await Passcode.open(PasscodeKind.switching),
  );

  /// 保護者向け画面のロック（SPEC 7.6）。
  final Passcode admin;

  /// 書く人の切り替えのロック（SPEC 7.5）。
  final Passcode switching;
}
