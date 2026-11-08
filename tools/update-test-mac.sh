#!/bin/bash
# 맥앱 자체 업데이트 시험 — 설치본·실제 서버를 건드리지 않는다 (note-reader/mac/update_test.sh 를 가져왔다).
# 옛 판을 임시 자리에 두고, 이 맥 안의 시험 서버에 새 판을 올리고, 옛 판이 받아 자기를 바꾸는지 본다.
# 해시가 틀린 version.json 이면 바꾸지 않는 것도 본다. 창은 띄우지 않는다 (--updatetest).
#   tools/update-test-mac.sh
set -u
cd "$(dirname "$0")/.."
FAIL=0; ok() { echo "  ✓ $1"; }; bad() { echo "  ✗ $1"; FAIL=$((FAIL+1)); }
T=$(mktemp -d); SRV="$T/srv/apps/routine"; mkdir -p "$SRV"
APP="mac/build.noindex/routine.app"
EXE="$T/old/routine.app/Contents/MacOS/Routine"
code() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist"; }
echo "┌ 맥앱 자체 업데이트 시험"
tools/build-mac-app.sh >/dev/null && mkdir -p "$T/old" && ditto "$APP" "$T/old/routine.app"
OLD=$(code "$T/old/routine.app"); echo "  │ 옛 판 $OLD"
sleep 61
tools/build-mac-app.sh >/dev/null; NEW=$(code "$APP"); echo "  │ 새 판 $NEW"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$SRV/new.zip"
SHA=$(shasum -a 256 "$SRV/new.zip" | cut -d' ' -f1)
vj() { printf '{"mac":{"versionCode":%s,"versionName":"test","size":1,"sha256":"%s","url":"/apps/routine/new.zip"}}' "$NEW" "$1" > "$SRV/version.json"; }
PORT=$((40000 + RANDOM % 9000))
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$T/srv" >/dev/null 2>&1 & PID=$!; sleep 1
export UPDATE_BASE="http://127.0.0.1:$PORT/apps/routine"

vj 0000000000000000000000000000000000000000000000000000000000000000
perl -e 'alarm 120; exec @ARGV' "$EXE" --updatetest 2>&1 | sed 's/^/  │ /'
[ "$(code "$T/old/routine.app")" = "$OLD" ] && ok "해시가 틀리면 바꾸지 않는다" || bad "해시가 틀렸는데 바꿨다"

vj "$SHA"
perl -e 'alarm 120; exec @ARGV' "$EXE" --updatetest 2>&1 | sed 's/^/  │ /'
GOT=$(code "$T/old/routine.app"); echo "  │ 지금 판 $GOT"
[ "$GOT" = "$NEW" ] && ok "옛 판이 새 판으로 바뀌었다" || bad "판이 그대로다"
codesign -v "$T/old/routine.app" 2>/dev/null && ok "바뀐 앱의 서명이 살아 있다" || bad "서명이 깨졌다"
perl -e 'alarm 60; exec @ARGV' "$EXE" --updatetest 2>&1 | grep -q "새 판 없음" && ok "바뀐 앱이 돌고, 새 판이 없다고 본다" || bad "바뀐 앱이 안 돈다"
kill $PID 2>/dev/null; rm -rf "$T"
echo "└ $( [ $FAIL = 0 ] && echo 통과 || echo "실패 $FAIL" )"
exit $FAIL
