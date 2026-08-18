import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../store/word_book_store.dart';
import '../word/word_image.dart';

/// 語に添えた絵（SPEC 7.4）。
///
/// 字が読めない子は、絵でしか語を選べない。
///
/// 絵は端末の中にしかない。読み込みは一度きりで、あとは持っておいたものを
/// 出す（[WordBookStore.cachedImage]）。一覧では同じ絵が何度も並ぶ。
class WordImageView extends StatelessWidget {
  const WordImageView({
    super.key,
    required this.image,
    required this.books,
    required this.size,
  });

  /// 絵の id。
  final String image;

  final WordBookStore books;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cached = books.cachedImage(image);
    if (cached != null) return _build(cached);

    return FutureBuilder<Uint8List?>(
      future: books.readImage(image),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        // 読めるまでは場所だけ空けておく。出たり消えたりすると並びが動く。
        if (bytes == null) return SizedBox(width: size, height: size);
        return _build(bytes);
      },
    );
  }

  Widget _build(Uint8List bytes) {
    return SizedBox(
      width: size,
      height: size,
      child: isSvg(image)
          ? SvgPicture.memory(bytes, fit: BoxFit.contain)
          // 絵の縦横比は変えない。伸びた絵はそれだけで別のものに見える。
          : Image.memory(bytes, fit: BoxFit.contain),
    );
  }
}
