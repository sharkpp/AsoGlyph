import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../store/passcode.dart';

/// 掛かっているロックを開けてもらう（SPEC 7.5 / 7.6）。
///
/// パスコードが掛かっていなければ、そのまま通す。既定は無効。
Future<bool> unlock(BuildContext context, Passcode passcode) async {
  if (!passcode.isSet) return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => _UnlockDialog(passcode: passcode),
  );
  return ok ?? false;
}

class _UnlockDialog extends StatefulWidget {
  const _UnlockDialog({required this.passcode});

  final Passcode passcode;

  @override
  State<_UnlockDialog> createState() => _UnlockDialogState();
}

class _UnlockDialogState extends State<_UnlockDialog> {
  final _controller = TextEditingController();
  var _wrong = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (widget.passcode.matches(_controller.text)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _wrong = true);
    }
  }

  /// パスコードを忘れたとき。
  ///
  /// 集めた字を人質にしない。外す前に、子供には解けない問いを 1 つ挟む。
  /// 守っているのは秘密ではなく「子供が入らないこと」なので、これで足りる。
  Future<void> _forgot() async {
    if (!await _askParentGate(context)) return;
    await widget.passcode.clear();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('パスコード'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 何のパスコードを聞かれているのかを出す。掛け先が 2 つあり、
          // 見出しが「パスコード」だけだとどちらか分からない。
          Align(
            alignment: Alignment.centerLeft,
            child: Text(widget.passcode.kind.asked),
          ),
          TextField(
            controller: _controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              errorText: _wrong ? 'ちがいます' : null,
              counterText: '',
            ),
            maxLength: 8,
            onChanged: (_) {
              if (_wrong) setState(() => _wrong = false);
            },
            onSubmitted: (_) => _submit(),
          ),
          // 「わすれた」は下のボタン列に混ぜない。3 つ並べるとスマホ幅で
          // 縦積みになり、どれが本筋か分からなくなる。
          TextButton(onPressed: _forgot, child: const Text('わすれた')),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
        FilledButton(onPressed: _submit, child: const Text('あける')),
      ],
    );
  }
}

/// おとなだけが通れる問い。
///
/// 子供向けカテゴリで使われている作り。掛け算は 4〜6 歳には解けない。
Future<bool> _askParentGate(BuildContext context) async {
  final random = Random();
  final a = 3 + random.nextInt(7);
  final b = 3 + random.nextInt(7);
  final controller = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('おうちの人ですか？'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('パスコードを外します。集めた字も版も消えません。'),
          const SizedBox(height: 16),
          Text('$a × $b は？', style: const TextStyle(fontSize: 20)),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (value) =>
                Navigator.of(context).pop(value == '${a * b}'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(controller.text == '${a * b}'),
          child: const Text('外す'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// パスコードを決めさせる。空で決めると外れる。
Future<void> showPasscodeSettings(
  BuildContext context,
  Passcode passcode,
) async {
  final controller = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(passcode.isSet ? 'パスコードを変える' : 'パスコードを決める'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${passcode.kind.asked}。'),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            maxLength: 8,
            decoration: const InputDecoration(counterText: ''),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('決める'),
        ),
      ],
    ),
  );

  if (code == null) return;
  // 空で決めたらパスコードを外す。掛けるのをやめる導線をここに寄せる。
  await (code.isEmpty ? passcode.clear() : passcode.set(code));
}
