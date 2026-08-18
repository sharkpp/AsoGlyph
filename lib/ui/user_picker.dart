import 'package:flutter/material.dart';

import '../model/user.dart';
import '../store/passcode.dart';
import '../store/session.dart';
import 'passcode_gate.dart';

/// いま書いている人の印。押すと切り替えられる。
///
/// 1 人しかいないうちは出さない。使いようのないボタンを子供向け画面に
/// 置かない（SPEC 9）。
class CurrentUserButton extends StatelessWidget {
  const CurrentUserButton({
    super.key,
    required this.session,
    required this.lock,
  });

  final Session session;

  /// 切り替えのロック（SPEC 7.5）。既定は掛かっていない。
  final Passcode lock;

  @override
  Widget build(BuildContext context) {
    if (!session.users.hasMany) return const SizedBox.shrink();
    final user = session.current;

    return IconButton(
      iconSize: 28,
      tooltip: 'だれが かく？',
      icon: AvatarMark(avatar: user.avatar, size: 32),
      onPressed: () => showUserPicker(context, session, lock),
    );
  }
}

/// 誰が書くかを選ばせる。
///
/// 字が読めない子のために、印を大きく出す。名前は下に添えるだけ。
///
/// ロックが掛かっていれば、選ばせる前に聞く（SPEC 7.5）。選んでから断ると、
/// 押した印が使えないものだったのか、間違えたのかが子供に分からない。
///
/// 管理画面の一覧からの切り替えでは聞かない。そこまで入れる人は版も
/// 集める文字種も変えられる。そこを守るのは管理画面のパスコードの役目。
Future<void> showUserPicker(
  BuildContext context,
  Session session,
  Passcode lock,
) async {
  if (!await unlock(context, lock)) return;
  if (!context.mounted) return;

  final picked = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('だれが かく？', style: TextStyle(fontSize: 20)),
          ),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: [
              for (final user in session.users.all)
                _UserChoice(
                  user: user,
                  selected: user.id == session.current.id,
                  onTap: () => Navigator.of(context).pop(user.id),
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    ),
  );
  if (picked != null) await session.switchTo(picked);
}

class _UserChoice extends StatelessWidget {
  const _UserChoice({
    required this.user,
    required this.selected,
    required this.onTap,
  });

  final User user;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        // タップターゲットは 64dp 以上（SPEC 9）。
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvatarMark(avatar: user.avatar, size: 72, ring: selected),
            const SizedBox(height: 8),
            Text(user.displayName),
          ],
        ),
      ),
    );
  }
}

/// 人の印。丸の中に絵。
class AvatarMark extends StatelessWidget {
  const AvatarMark({
    super.key,
    required this.avatar,
    this.size = 48,
    this.ring = false,
  });

  final Avatar avatar;
  final double size;

  /// いま選ばれている印を付けるか。
  final bool ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: avatar.color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: ring ? Border.all(color: avatar.color, width: 3) : null,
      ),
      child: Icon(avatar.icon, size: size * 0.55, color: avatar.color),
    );
  }
}

/// 人を足す・名前と印を変える。管理画面から使う。
Future<({String name, Avatar avatar})?> askUserDetails(
  BuildContext context, {
  required String title,
  String initialName = '',
  Avatar initialAvatar = Avatar.cat,
}) {
  return showDialog<({String name, Avatar avatar})>(
    context: context,
    builder: (context) => _UserDetailsDialog(
      title: title,
      initialName: initialName,
      initialAvatar: initialAvatar,
    ),
  );
}

class _UserDetailsDialog extends StatefulWidget {
  const _UserDetailsDialog({
    required this.title,
    required this.initialName,
    required this.initialAvatar,
  });

  final String title;
  final String initialName;
  final Avatar initialAvatar;

  @override
  State<_UserDetailsDialog> createState() => _UserDetailsDialogState();
}

class _UserDetailsDialogState extends State<_UserDetailsDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  late var _avatar = widget.initialAvatar;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'なまえ'),
          ),
          const SizedBox(height: 16),
          const Text('しるし'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final avatar in Avatar.values)
                InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => setState(() => _avatar = avatar),
                  child: AvatarMark(avatar: avatar, ring: avatar == _avatar),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('やめる'),
        ),
        FilledButton(
          onPressed: () {
            final name = _controller.text.trim();
            if (name.isEmpty) return;
            Navigator.of(context).pop((name: name, avatar: _avatar));
          },
          child: const Text('決める'),
        ),
      ],
    );
  }
}
