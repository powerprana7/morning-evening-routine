#!/bin/bash
# 정해진 시각 알림 — 맥 쪽 설치 (D-033)
#
# 하는 일은 셋이다.
#   1. 열쇠 한 쌍이 없으면 만든다 (`~/.routine-push/vapid_private.pem`)
#   2. `push-send.py` 를 `~/.routine-push/` 로 복사한다
#   3. 7:30 · 20:30 에 그것을 부르는 launchd 항목을 걸어 준다
#
# **왜 복사하는가** — launchd 는 고정된 경로를 요구하는데, 이 저장소를 어디에
# 내려받았는지는 그때그때 다르다. 대신 사본이 낡을 수 있으므로 `tools/check.sh`
# 가 원본과 다르면 알려 준다. 코드를 고쳤으면 이 스크립트를 다시 돌린다.
#
#   tools/push-setup.sh            설치하거나 갱신한다 (몇 번을 돌려도 안전하다)
#   tools/push-setup.sh --remove   걷어낸다

set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$HOME/.routine-push"
LABEL="com.powerprana.routine-push"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "걷어냈습니다. 열쇠와 등록 정보는 $DEST 에 그대로 둡니다."
  echo "그것까지 지우려면: rm -rf $DEST"
  exit 0
fi

PY="$(command -v python3 || true)"
[ -n "$PY" ] || { echo "python3 을 찾지 못했습니다"; exit 1; }
"$PY" -c 'import cryptography' 2>/dev/null || {
  echo "python 의 cryptography 모듈이 필요합니다:  $PY -m pip install cryptography"; exit 1; }

mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
cp "$HERE/tools/push-send.py" "$DEST/push-send.py"
chmod +x "$DEST/push-send.py"

# 열쇠가 없으면 만든다. 있으면 그대로 둔다 —
# 다시 만들면 폰에 등록된 알림 주소가 전부 못 쓰게 된다.
if [ ! -f "$DEST/vapid_private.pem" ]; then
  "$PY" "$DEST/push-send.py" keygen
  echo
  echo "⚠ 공개키가 새로 생겼습니다. index.html 의 VAPID_PUBLIC 을 위 값으로 바꾸고"
  echo "  push 해야 폰이 알림을 받을 수 있습니다."
  echo
fi

cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$PY</string>
    <string>$DEST/push-send.py</string>
    <string>send</string>
  </array>
  <!-- 시각을 여기서 고치면 push-send.py 의 SCHEDULE 도 같이 고쳐야 한다.
       한쪽만 고치면 launchd 는 깨우는데 스크립트가 "지금이 아니다"라며
       안 보낸다 — 아무 소리 없이 실패한다 -->
  <key>StartCalendarInterval</key>
  <array>
    <dict><key>Hour</key><integer>7</integer><key>Minute</key><integer>30</integer></dict>
    <dict><key>Hour</key><integer>20</integer><key>Minute</key><integer>30</integer></dict>
  </array>
  <key>RunAtLoad</key><false/>
  <key>StandardOutPath</key><string>$DEST/launchd.log</string>
  <key>StandardErrorPath</key><string>$DEST/launchd.log</string>
</dict>
</plist>
PLISTEOF

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo "걸었습니다 — 07:30 · 20:30"
echo
"$PY" "$DEST/push-send.py" status
