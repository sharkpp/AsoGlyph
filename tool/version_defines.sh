#!/bin/sh
# ビルドに焼き込む版の情報（日付＋ショートハッシュ）。
#
#   flutter build web --release --base-href /AsoGlyph/ $(tool/version_defines.sh)
#
# 出すのは --dart-define の並び。読むのは lib/app_version.dart。
#
# 日付は **コミットの日付**にする。ビルドした日にすると、同じものを流し直す
# たびに違う版に見える。どのコミットから作ったかが分かればよい。
#
# ここ 1 つに置くのは、CI と手元で違うものが焼かれないようにするため。
set -eu

echo "--dart-define=BUILD_DATE=$(git show -s --format=%cd --date=format:%Y-%m-%d HEAD)" \
     "--dart-define=BUILD_COMMIT=$(git rev-parse --short=7 HEAD)"
