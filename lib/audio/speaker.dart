import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 音声読み上げ。
///
/// 3〜4歳を入口に含めるため、子供向け画面は字が読めなくても操作できなければ
/// ならない（SPEC 2）。画面が伝えることは、必ず音声でも伝える。
abstract interface class Speaker {
  /// 読み上げる。読み上げ中なら打ち切って言い直す。
  Future<void> speak(String text);

  /// 読み上げを止める。
  Future<void> stop();
}

/// 端末の読み上げエンジンを使う [Speaker]。
///
/// 合成は端末内で完結する。子供の声も字も外に出さない（SPEC 3）。
class TtsSpeaker implements Speaker {
  TtsSpeaker._(this._tts);

  final FlutterTts _tts;

  static Future<TtsSpeaker> open() async {
    final tts = FlutterTts();
    await _quietly(() async {
      await tts.setLanguage('ja-JP');
      await tts.setSpeechRate(_normalRate * _slowdown);
      await tts.setPitch(_pitch);
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        // 消音スイッチが入っていても鳴らす。音声は装飾ではなく操作の一部。
        await tts.setSharedInstance(true);
        await tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
        );
      }
    });
    return TtsSpeaker._(tts);
  }

  @override
  Future<void> speak(String text) => _quietly(() async {
    await _tts.stop();
    await _tts.speak(text);
  });

  @override
  Future<void> stop() => _quietly(() => _tts.stop());

  /// 「ふつうの速さ」に当たる値。尺度がプラットフォームで違う。
  /// Android と iOS は 0.5 が等倍、web の SpeechSynthesis は 1.0 が等倍。
  static double get _normalRate => kIsWeb ? 1.0 : 0.5;

  /// 幼児が聞き取れるよう、ふつうより少しゆっくり読む。
  static const _slowdown = 0.85;

  /// 少し高い声のほうが子供には届く。
  static const _pitch = 1.2;

  /// 読み上げの失敗で画面を止めない。
  ///
  /// エンジンを持たない Android 端末や、SpeechSynthesis の無いブラウザがある。
  /// 音が出ないことはあっても、字が書けなくなってはいけない。
  static Future<void> _quietly(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      debugPrint('tts: $error');
    }
  }
}
