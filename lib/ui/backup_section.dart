import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../export/backup.dart';
import '../export/file_save.dart';
import '../store/session.dart';
import 'file_types.dart';

/// 控えの書き出しと読み込み（SPEC 7.5）。
///
/// 端末が壊れて子供の字が消えることは許容できない。おうちの人の画面に置く。
class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.session});

  final Session session;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  Session get session => widget.session;

  /// 書き出している間。集めた字ぜんぶを 1 つのファイルにまとめるので、
  /// 字が多いと待つ。何も出ないと、押せていないのかどうかが分からない。
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.save_alt),
          title: const Text('控えを書き出す'),
          subtitle: const Text('書く人・集めた字・版をまとめて 1 つのファイルにします'),
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
          enabled: !_busy,
          onTap: () => _export(context),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.restore),
          title: const Text('控えから戻す'),
          subtitle: const Text('いまある字は消えません。同じ字は控えのもので上書きします'),
          onTap: () => _import(context),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await exportBackup(session.db);
      final now = DateTime.now();
      final name =
          'asoglyph-${now.year}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}.asoglyph';

      // 送り先は共有シートに任せる。こちらからどこかへ送ることはしない
      // （SPEC 3）。フォントや単語帳と同じ道を通る。
      await saveFile(
        bytes: bytes,
        fileName: name,
        mimeType: 'application/json',
        subject: 'あそんでフォントの控え',
      );
    } catch (error) {
      // 黙って何も起きないと、押せていないのか失敗したのかが分からない。
      debugPrint('控えの書き出しに失敗: $error');
      messenger.showSnackBar(
        SnackBar(content: Text('控えを書き出せませんでした（$error）')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // 選ぶ画面そのものが開けないこともある（種類の宣言と食い違うなど）。
      // そこで黙ると、押しても何も起きない画面になる。
      final file = await openFile(acceptedTypeGroups: [backupTypeGroup]);
      if (file == null || !mounted) return;

      await session.restoreFrom(await file.readAsBytes());
      messenger.showSnackBar(const SnackBar(content: Text('控えから戻しました')));
    } on FormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('控えの読み込みに失敗: $error');
      messenger.showSnackBar(SnackBar(content: Text('控えを読み込めませんでした（$error）')));
    }
  }
}
