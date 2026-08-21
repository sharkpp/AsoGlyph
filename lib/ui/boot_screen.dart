import 'package:flutter/material.dart';

import '../app_version.dart';
import '../boot.dart';
import 'app_mark.dart';

/// 起動中の画面。
///
/// 読み終わるのを待って `runApp` すると、そのあいだ画面が真っ白のまま止まって
/// 見える（web では読み込みが終わるまで、端末では起動画面のまま）。書き順
/// データだけで 1 MB を超えるので、端末が遅いほど長い。**先に画面を出して、
/// どこまで進んだかを見せる。**
///
/// 印を大きく出すのは、字が読めない子にも「これはあのアプリだ」と分かる
/// ようにするため（SPEC 2）。進み具合は帯が持つので、段取りの名前が読めなくても
/// 動いていることは分かる。
class BootScreen extends StatefulWidget {
  const BootScreen({super.key, required this.boot, required this.builder});

  /// 何を読むか。テストでは差し替える。
  final Boot boot;

  /// 読み終わったら、これで本体を作る。
  final Widget Function(AppServices services) builder;

  @override
  State<BootScreen> createState() => _BootScreenState();
}

class _BootScreenState extends State<BootScreen> {
  AppServices? _services;
  Object? _error;

  var _done = 0;
  var _total = 1;
  var _step = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _done = 0;
      _step = '';
    });
    try {
      final services = await widget.boot((done, total, step) {
        // 読み終わったあとにも報せが来ることがある。画面が無ければ捨てる。
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
          _step = step;
        });
      });
      if (!mounted) return;
      setState(() => _services = services);
    } catch (error, stack) {
      // 開けなかったことを黙っていると、進み具合の帯が止まったまま残る。
      // 何が起きたのかは、直せる人（親）が見るところに出す。
      debugPrint('起動できませんでした: $error\n$stack');
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services != null) return widget.builder(services);

    return Scaffold(
      backgroundColor: appCream,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppMark(size: 128),
                    const SizedBox(height: 24),
                    const Text(
                      'あそんでフォント',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: Color(0xff6f665c),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_error == null) _buildProgress() else _buildError(),
                  ],
                ),
              ),
            ),
            // どのビルドが動いているか。web は同じ URL のものが黙って
            // 入れ替わるので、確かめる手立てが要る（SPEC 10.1）。
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  appVersionLabel,
                  style: const TextStyle(fontSize: 11, color: Color(0xffbdb4a6)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgress() {
    return Column(
      children: [
        SizedBox(
          width: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              // 段取りの数は決まっている。どこまで来たかを出せるので、
              // ぐるぐる回すだけにはしない（あと何回かが目で分かる）。
              value: _done / _total,
              minHeight: 10,
              backgroundColor: const Color(0xffe4dfd4),
              color: appOrange,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          // 読める人には、いま何を読んでいるかも出す。止まったときに、
          // どこで止まったかが分かる。
          _step,
          style: const TextStyle(fontSize: 13, color: Color(0xff9c948a)),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        const Text(
          'うまく ひらけませんでした',
          style: TextStyle(fontSize: 16, color: Color(0xffc4553c)),
        ),
        const SizedBox(height: 8),
        // 直せる人（親）に見せる。何が起きたか分からないと、報せようがない。
        Text(
          '$_error',
          textAlign: TextAlign.center,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Color(0xff9c948a)),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
          onPressed: _start,
          icon: const Icon(Icons.refresh),
          label: const Text('もういちど'),
        ),
      ],
    );
  }
}
