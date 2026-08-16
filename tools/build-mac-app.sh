#!/bin/bash
# 맥앱 빌드 — mac/Routine.swift 를 routine.app 으로 만든다 (D-016)
#
#   tools/build-mac-app.sh            빌드만  (mac/routine.app)
#   tools/build-mac-app.sh --install  빌드 + /Applications 에 설치
#
# 필요한 것: Xcode Command Line Tools (swiftc). Xcode 본체는 필요 없다.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/mac/Routine.swift"
APP="$HERE/mac/routine.app"
NAME="Routine"

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }

command -v swiftc >/dev/null || { red "✗ swiftc 가 없습니다. xcode-select --install"; exit 1; }
[ -f "$SRC" ] || { red "✗ 소스가 없습니다: $SRC"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# ── 1. 실행 파일 ──────────────────────────────────────────────────────
swiftc -O -o "$APP/Contents/MacOS/$NAME" "$SRC" \
  -framework Cocoa -framework WebKit -target arm64-apple-macos13.0

# ── 2. 아이콘 (icon-512.png → .icns) ─────────────────────────────────
ICONSET="$(mktemp -d)/icon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s "$HERE/icon-512.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
  d=$((s*2))
  sips -z $d $d "$HERE/icon-512.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$NAME.icns"
rm -rf "$(dirname "$ICONSET")"

# ── 3. 오프라인 대비 사본 ─────────────────────────────────────────────
# 네트워크가 안 될 때만 쓰인다. 평소에는 URL 을 본다 (D-016)
cp "$HERE/index.html" "$APP/Contents/Resources/index.html"

# ── 4. Info.plist ────────────────────────────────────────────────────
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>               <string>routine</string>
  <key>CFBundleDisplayName</key>        <string>routine</string>
  <key>CFBundleExecutable</key>         <string>$NAME</string>
  <key>CFBundleIdentifier</key>         <string>com.powerprana7.routine</string>
  <key>CFBundleIconFile</key>           <string>$NAME</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$(date '+%Y.%m.%d')</string>
  <key>CFBundleVersion</key>            <string>$(date '+%Y%m%d')</string>
  <key>LSMinimumSystemVersion</key>     <string>13.0</string>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>NSHumanReadableCopyright</key>   <string></string>
</dict>
</plist>
PLIST

touch "$APP"
green "✓ 빌드 완료: $APP"

if [ "${1:-}" = "--install" ]; then
  DEST="/Applications/routine.app"
  if [ -w /Applications ]; then
    rm -rf "$DEST"; cp -R "$APP" "$DEST"
    green "✓ 설치 완료: $DEST"
  else
    DEST="$HOME/Applications/routine.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"; cp -R "$APP" "$DEST"
    green "✓ 설치 완료: $DEST  (/Applications 에 쓸 수 없어 사용자 폴더에 넣었습니다)"
  fi
fi
