import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../export/backup.dart';
import '../store/session.dart';
import 'file_types.dart';

/// 控えの書き出しと読み込み（SPEC 7.5）。
///
/// 端末が壊れて子供の字が消えることは許容できない。おうちの人の画面に置く。
class BackupSection extends StatelessWidget {
  const BackupSection({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.save_alt),
          title: const Text('控えを書き出す'),
          subtitle: const Text('書く人・集めた字・版をまとめて 1 つのファイルにします'),
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
    final bytes = await exportBackup(session.db);
    final now = DateTime.now();
    final name =
        'asoglyph-${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}.asoglyph';

    // 送り先は共有シートに任せる。こちらからどこかへ送ることはしない（SPEC 3）。
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: name,
            mimeType: 'application/json',
          ),
        ],
        fileNameOverrides: [name],
        text: 'あそんでフォントの控え',
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: [backupTypeGroup],
    );
    if (file == null || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.restoreFrom(await file.readAsBytes());
      messenger.showSnackBar(const SnackBar(content: Text('控えから戻しました')));
    } on FormatException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('控えの読み込みに失敗: $error');
      messenger.showSnackBar(const SnackBar(content: Text('この控えは読み込めません')));
    }
  }
}
