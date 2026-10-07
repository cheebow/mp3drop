#!/bin/bash
# MP3Drop のリリースビルドを作成し、Developer ID 署名 → 公証 → GitHub Release 添付まで行う。
# (WaveScope の Scripts/release.sh と同じ流れ)
#
# 前提:
#   - キーチェーンに "Developer ID Application" 証明書があること
#   - notarytool の認証プロファイル "notarytool" が保存済みであること
#     (xcrun notarytool store-credentials notarytool --apple-id ... --team-id ...)
#   - gh CLI でログイン済みであること
#   - xcodegen がインストール済みであること(xcodeproj は project.yml から生成する)
#
# 使い方(リポジトリルートから):
#   ./Scripts/release.sh              # ビルド〜公証〜タグ作成〜GitHub Release 作成まで
#   ./Scripts/release.sh --no-release # タグ作成・GitHub Release をスキップ(zip 生成まで)
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARY_PROFILE="notarytool"
SCHEME="MP3Drop"
OUT="build/release"
ARCHIVE="$OUT/MP3Drop.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/MP3Drop.app"

echo "==> xcodeproj を生成"
xcodegen generate --quiet

VERSION=$(xcodebuild -project MP3Drop.xcodeproj -scheme "$SCHEME" -showBuildSettings 2>/dev/null |
    awk '/MARKETING_VERSION/ { print $3; exit }')
TAG="v$VERSION"
ZIP="$OUT/MP3Drop-$VERSION.zip"

if [[ "${1:-}" != "--no-release" ]]; then
    echo "==> リリース前チェック"
    BRANCH=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$BRANCH" != "master" ]]; then
        echo "リリースは master ブランチから行ってください(現在: $BRANCH)。" >&2
        exit 1
    fi
    if [[ -n $(git status --porcelain) ]]; then
        echo "作業ツリーに未コミットの変更があります。コミットしてから再実行してください。" >&2
        exit 1
    fi
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null ||
        git ls-remote --exit-code --tags origin "$TAG" >/dev/null 2>&1; then
        echo "タグ $TAG は既に存在します。MARKETING_VERSION を上げてから再実行してください。" >&2
        exit 1
    fi
fi

echo "==> リリースビルド $TAG"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "==> アーカイブ"
xcodebuild archive \
    -project MP3Drop.xcodeproj -scheme "$SCHEME" -configuration Release \
    -archivePath "$ARCHIVE" -quiet

echo "==> Developer ID でエクスポート"
cat > "$OUT/exportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$OUT/exportOptions.plist" -quiet

echo "==> 公証(notarization)"
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
# notarytool は結果が Invalid でも exit 0 で返ることがあるため、status を明示的に確認する
SUBMIT_JSON=$(xcrun notarytool submit "$OUT/notarize.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
echo "$SUBMIT_JSON"
STATUS=$(plutil -extract status raw -o - - <<< "$SUBMIT_JSON" 2>/dev/null || true)
if [[ "$STATUS" != "Accepted" ]]; then
    echo "公証が失敗しました (status: ${STATUS:-不明})。ログ:" >&2
    SUBMISSION_ID=$(plutil -extract id raw -o - - <<< "$SUBMIT_JSON" 2>/dev/null || true)
    if [[ -n "$SUBMISSION_ID" ]]; then
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" >&2
    fi
    exit 1
fi
xcrun stapler staple "$APP"

echo "==> 検証"
spctl -a -vv "$APP"

echo "==> 配布用 zip 作成"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP"

if [[ "${1:-}" == "--no-release" ]]; then
    echo "==> --no-release 指定のため タグ作成・GitHub Release はスキップ"
    exit 0
fi

echo "==> タグ $TAG を作成して master と共に push"
git tag -a "$TAG" -m "$TAG"
git push origin master "$TAG"

echo "==> GitHub Release $TAG を作成"
gh release create "$TAG" "$ZIP" --title "$TAG" --generate-notes
echo "==> 完了"
