import 'package:asoglyph/audio/speaker.dart';

/// 読み上げの代わりに文言を控えるだけの [Speaker]。
///
/// 本物は端末の読み上げエンジンを叩くため、テストでは使えない。
class RecordingSpeaker implements Speaker {
  final spoken = <String>[];
  var stopped = 0;

  @override
  Future<void> speak(String text) async => spoken.add(text);

  @override
  Future<void> stop() async => stopped++;
}
