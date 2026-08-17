#!/bin/bash
# 맥앱 빌드 — mac/Routine.swift 를 routine.app 으로 만든다 (D-016)
#
#   tools/build-mac-app.sh            빌드만  (mac/build.noindex/routine.app)
#   tools/build-mac-app.sh --install  빌드 + /Applications 에 설치
#
# 필요한 것: Xcode Command Line Tools (swiftc). Xcode 본체는 필요 없다.
#
# 산출물을 .noindex 폴더에 두는 이유 (D-021):
# 이름이 .noindex 로 끝나는 폴더는 Spotlight 가 색인하지 않는다. 그래야
# Alfred 에서 "routine" 을 쳤을 때 설치본(/Applications) 하나만 뜬다.
# 예전처럼 mac/routine.app 에 두면 빌드본과 설치본이 둘 다 앱으로 잡힌다.

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$HERE/mac/Routine.swift"
APP="$HERE/mac/build.noindex/routine.app"
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

# ── 2. 아이콘 ────────────────────────────────────────────────────────
# 맥 전용 아이콘을 쓴다 — 1024 캔버스 안에 824 둥근 사각형 + 투명 여백.
# 웹용(icon-512.png)은 꽉 차 있어서 맥에서는 다른 앱보다 커 보인다 (D-019)
MASTER="$HERE/mac/icon-mac-1024.png"
[ -f "$MASTER" ] || python3 "$HERE/tools/make-icons.py" >/dev/null

ICONSET="$(mktemp -d)/icon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$MASTER" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
  d=$((s*2))
  sips -z $d $d "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
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
  <key>CFBundleName</key>               <string>Routine</string>
  <key>CFBundleDisplayName</key>        <string>Routine</string>
  <key>CFBundleExecutable</key>         <string>$NAME</string>
  <key>CFBundleIdentifier</key>         <string>com.powerprana7.routine</string>
  <key>CFBundleIconFile</key>           <string>$NAME</string>
  <key>CFBundlePackageType</key>        <string>APPL</string>
  <key>CFBundleShortVersionString</key> <string>$(date '+%Y.%m.%d')</string>
  <key>CFBundleVersion</key>            <string>$(date '+%Y%m%d')</string>
  <key>LSMinimumSystemVersion</key>     <string>13.0</string>
  <key>NSHighResolutionCapable</key>    <true/>
  <key>NSHumanReadableCopyright</key>   <string></string>
  <key>NSAppleEventsUsageDescription</key>
  <string>루틴 변경을 클로드코드로 보내기 위해 터미널을 실행합니다.</string>
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
