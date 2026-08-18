import 'package:flutter/material.dart';

import 'char_set.dart';

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
    this.collecting = const {},
  });

  final String id;

  /// 親が付けた名前。子供が読めるとは限らない。
  final String displayName;

  /// 字が読めなくても自分を見つけられるようにする印（SPEC 2）。
  final Avatar avatar;

  final DateTime createdAt;

  /// 難易度統計の補正にだけ使う。任意（SPEC 4.4）。
  final DateTime? birthMonth;

  /// いま集めている文字種（SPEC 5）。
  ///
  /// 出力対象（版）とは別に決める。収集は広く、出力は絞る、という非対称が
  /// 「あの頃の文字」の前提。空のときは全部を集める。
  ///
  /// 4 歳にカタカナ 81 字まで見せると、目の前の字を探せなくなる。
  /// まだ書かせない文字種は、子供向け画面から丸ごと消す。
  final Set<CharSet> collecting;

  /// 子供向け画面に出す文字種。
  List<CharSet> get visibleCharSets => [
    for (final charSet in CharSet.values)
      if (collecting.isEmpty || collecting.contains(charSet)) charSet,
  ];

  User copyWith({
    String? displayName,
    Avatar? avatar,
    DateTime? birthMonth,
    Set<CharSet>? collecting,
  }) => User(
    id: id,
    displayName: displayName ?? this.displayName,
    avatar: avatar ?? this.avatar,
    createdAt: createdAt,
    birthMonth: birthMonth ?? this.birthMonth,
    collecting: collecting ?? this.collecting,
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
