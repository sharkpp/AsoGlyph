/// このビルドが何かを言う 1 行（日付＋ショートハッシュ）。
///
/// 版の番号ではなく **どのコミットから作ったか**を出す。web は同じ URL の
/// ものが黙って入れ替わる（SPEC 10.1 の network-first）ので、「直したものが
/// 来ているか」を確かめる手立てがないと、直したのに古いまま見ている、
/// という取り違えが起きる。
///
/// 焼き込むのはビルドのときだけ。
///
/// ```sh
/// flutter build web --release --base-href /AsoGlyph/ $(tool/version_defines.sh)
/// ```
///
/// 焼き込まなければ「開発中」と出る。手元で流したものを、配ったものと
/// 見分けるためにそのままにしておく（空にすると、出ていないのか
/// 焼き忘れたのかが分からない）。
library;

/// コミットの日付（`2026-08-21`）。
const _buildDate = String.fromEnvironment('BUILD_DATE');

/// コミットのショートハッシュ（`2a5c0b3`）。
const _buildCommit = String.fromEnvironment('BUILD_COMMIT');

/// 焼き込まれた版の情報。無ければ「開発中」。
const appVersionLabel = (_buildDate == '' && _buildCommit == '')
    ? '開発中'
    : '$_buildDate $_buildCommit';

/// ビルドのときに焼き込まれたか。
const isReleaseBuild = !(_buildDate == '' && _buildCommit == '');
