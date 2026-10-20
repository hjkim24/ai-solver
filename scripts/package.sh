#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
app="$PWD/build/Clipboard AI Solver.app"
binary="$app/Contents/MacOS/ClipboardAISolver"
[[ -f "$binary" ]] || { printf '%s\n' '먼저 bash scripts/build.sh로 앱을 빌드하세요.' >&2; exit 1; }
identifier=$(/usr/libexec/PlistBuddy -c 'Print:CFBundleIdentifier' "$app/Contents/Info.plist")
[[ "$identifier" == com.hjkim24.clipboard-ai-solver ]] || { printf '%s\n' '배포 대상 앱 식별자가 다릅니다.' >&2; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print:CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$version" =~ ^[0-9A-Za-z._-]+$ ]] || { printf '%s\n' '앱 버전 형식을 확인하세요.' >&2; exit 1; }
architectures=$(lipo -archs "$binary")
tag=${architectures// /-}
codesign --verify --deep --strict "$app"
mkdir -p dist
output="$PWD/dist/Clipboard-AI-Solver-$version-$tag.dmg"
[[ ! -e "$output" ]] || { printf '%s\n' "기존 배포 파일을 덮어쓰지 않습니다: $output" >&2; exit 1; }
stage=$(mktemp -d "$PWD/build/package.XXXXXX")
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/content"
# Package only the signed bundle; Keychain and UserDefaults stay on each user's Mac.
ditto "$app" "$stage/content/Clipboard AI Solver.app"
cmp "$binary" "$stage/content/Clipboard AI Solver.app/Contents/MacOS/ClipboardAISolver"
codesign --verify --deep --strict "$stage/content/Clipboard AI Solver.app"
ln -s /Applications "$stage/content/Applications"
cp docs/INSTALL.ko.txt "$stage/content/설치 안내.txt"
hdiutil create -fs HFS+ -format UDZO -volname 'Clipboard AI Solver' -srcfolder "$stage/content" "$stage/release.dmg"
hdiutil verify "$stage/release.dmg"
mv "$stage/release.dmg" "$output"
cd dist
shasum -a 256 "${output##*/}" > "${output##*/}.sha256"
printf '%s\n' "$output"
