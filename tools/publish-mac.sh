#!/bin/bash
# 맥앱 새 판을 Startpage(R2 mac-apps) 에 올린다 → 맥의 앱이 켤 때·「업데이트 확인…」 때 받는다 (2026-11-08)
# note-reader/mac/publish.sh 를 가져왔다.
# 순서: 빌드(설치 안 함) → zip 올림 → version.json 을 맨 마지막에 올림. 열쇠는 ~/.hb-key (Startpage HB_TOKEN).
# 여기서는 이 맥의 설치본을 바꾸지 않는다 — 이 맥도 앱 안의 버튼으로 받는다.
#   tools/publish-mac.sh
set -euo pipefail
cd "$(dirname "$0")/.."
APPID=routine
SERVER=${UPDATE_SERVER:-https://start.comms.ms/apps/$APPID}
HB=$(cat "$HOME/.hb-key")
APP="mac/build.noindex/routine.app"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

up() {  # up <파일> <올릴 이름>
  curl -fsS -m 300 -X POST "$SERVER/up?file=$2" -H "X-HB-Token: $HB" --data-binary "@$1" >/dev/null
}

tools/build-mac-app.sh >/dev/null
PL="$APP/Contents/Info.plist"
CODE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PL")
NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PL")
ZIP="$TMP/app.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"      # ditto 여야 서명이 산다
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1); SIZE=$(stat -f%z "$ZIP")
FILE="Routine-mac-$CODE.zip"                                 # 판마다 이름이 달라 받는 사이에 바뀌지 않는다
up "$ZIP" "$FILE"
PATHPART=$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urlparse(sys.argv[1]).path)' "$SERVER")
python3 - "$TMP/version.json" "$CODE" "$NAME" "$SIZE" "$SHA" "$PATHPART/$FILE" <<'PY'
import json, sys, datetime
out, code, name, size, sha, url = sys.argv[1:]
j = {"mac": {"versionCode": int(code), "versionName": name, "size": int(size), "sha256": sha, "url": url},
     "publishedAt": datetime.datetime.now().astimezone().isoformat(timespec="seconds")}
json.dump(j, open(out, "w"), ensure_ascii=False, indent=2)
PY
up "$TMP/version.json" version.json
GOT=$(curl -fsS -m 20 "$SERVER/version.json")
echo "$GOT" | python3 -c 'import sys,json; m=json.load(sys.stdin)["mac"]; print("올림:", m["versionName"], "(%d, %dKB)" % (m["versionCode"], m["size"]//1024))'
