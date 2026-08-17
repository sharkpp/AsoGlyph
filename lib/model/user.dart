import 'package:flutter/material.dart';

/// 書く人（SPEC 4.4）。
///
/// 情報は人ごとに完全に分離する（SPEC 7.5）。記録も版も、必ずどれか 1 人に属する。
class User {
  const User({
    required this.id,
    required this.displayName,
    required this.avatar,
    required this.createdAt,
    this.birthMonth,
  });

  final String id;

  /// 親が付けた名前。子供が読めるとは限らない。
  final String displayName;

  /// 字が読めなくても自分を見つけられるようにする印（SPEC 2）。
  final Avatar avatar;

  final DateTime createdAt;

  /// 難易度統計の補正にだけ使う。任意（SPEC 4.4）。
  final DateTime? birthMonth;

  User copyWith({String? displayName, Avatar? avatar, DateTime? birthMonth}) =>
      User(
        id: id,
        displayName: displayName ?? this.displayName,
        avatar: avatar ?? this.avatar,
        createdAt: createdAt,
        birthMonth: birthMonth ?? this.birthMonth,
      );
}

/// 人を見分ける印。
///
/// 名前は読めない子がいるので、絵と色で選ばせる。決まった組から選ぶだけにして、
/// 写真は撮らせない。子供の顔写真を持つと、端末内で完結する利点が薄れる。
enum Avatar {
  cat('ねこ', Icons.pets, Color(0xffe8863c)),
  rabbit('うさぎ', Icons.cruelty_free, Color(0xffd96b8b)),
  bird('とり', Icons.flutter_dash, Color(0xff4a9ed6)),
  star('ほし', Icons.star, Color(0xffe0b400)),
  flower('はな', Icons.local_florist, Color(0xff6bab5a)),
  car('くるま', Icons.directions_car, Color(0xff8a6ad6)),
  cake('ケーキ', Icons.cake, Color(0xffd95f5f)),
  ball('ボール', Icons.sports_baseball, Color(0xff3fa9a0));

  const Avatar(this.label, this.icon, this.color);

  final String label;
  final IconData icon;
  final Color color;
}
