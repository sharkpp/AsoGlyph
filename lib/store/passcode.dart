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
  const KeychainSecretStore([this._storage = const FlutterSecureStorage()]);

  static const _key = 'admin-passcode';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}

/// 管理画面のパスコード（SPEC 7.6）。
///
/// 目的は「子供が親の画面に入らない」こと。取られて困る秘密を守る仕組みでは
/// ない。集めた字はここで守られていないし、守る必要もない（端末内で完結する）。
///
/// 既定は無効。設定して初めて掛かる。
class Passcode extends ChangeNotifier {
  Passcode(this._store);

  static Future<Passcode> open([SecretStore? store]) async {
    final passcode = Passcode(store ?? const KeychainSecretStore());
    await passcode.load();
    return passcode;
  }

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
