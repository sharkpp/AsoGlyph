# あそんでフォント

幼児に運筆（文字遊び）で文字を書かせ、それをそのままフォントにするアプリです。

- 何を作っているかは [SPEC.md](SPEC.md) に書いてあります。
- web 版: <https://sharkpp.github.io/AsoGlyph/>

## web 版

`main` に入ると [GitHub Actions](.github/workflows/pages.yml) が
`flutter analyze` と `flutter test` を通してから公開します。

サブパス（`/AsoGlyph/`）に置くので **`--base-href` が要ります**。手元で同じものを
作るときは:

```sh
flutter build web --release --base-href /AsoGlyph/
cd build/web && python3 -m http.server 8000   # http://localhost:8000/
```

ホーム画面に置けて、オフラインでも開けます（PWA、SPEC 10.1）。

**iOS でホーム画面に追加すると、Safari とは保存先が分かれます。** Safari で書いた字は
出てこないので、先に管理画面から控えを書き出してください（SPEC 7.5）。

## 単語帳

`assets/words/` に置いたものが内蔵の辞書になります。足しかた・直しかたは
[assets/words/README.md](assets/words/README.md)。
