#!/usr/bin/env python3
"""정해진 시각에 폰으로 알림을 보낸다 (D-033).

이 파일은 **맥에서 돈다.** GitHub Pages 는 정적 호스팅이라 스스로 시각을 지킬 수
없어서, 시각을 지키는 몫을 맥의 launchd 가 맡는다.

의존성은 `cryptography` 하나뿐이다. 통신은 표준 라이브러리(`urllib`)로 한다 —
이 프로젝트의 '의존성 0' 을 완전히는 못 지키지만, 웹 푸시는 보낼 때마다 전자 서명을
새로 만들어야 하고(규격상 유효기간 최대 24시간) 그것만은 손으로 못 짠다.

**알림 내용을 여기서 보내지 않는다.** 빈 신호만 보내고 문구는 `sw.js` 가 정한다.
  - 암호화(ECDH·HKDF·AES-GCM) 단계가 통째로 없어진다. 실패할 곳이 줄어든다
  - 문구가 앱 파일 안에 있으므로 push 한 번으로 전 기기에 반영된다 (D-014)

비밀값은 저장소에 들어가지 않는다. `~/.routine-push/` 에만 둔다.

  push-send.py keygen              열쇠 한 쌍을 만든다 (맨 처음 한 번)
  push-send.py pubkey              앱에 박을 공개키를 찍는다
  push-send.py register '<json>'   폰에서 복사한 알림 주소를 등록한다
  push-send.py send [--force]      지금 보낸다 (launchd 가 부르는 것이 이것)
  push-send.py status              지금 상태를 본다
"""

import base64
import json
import os
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

# ── 보내는 시각. 여기를 고치면 launchd 설정(`com.powerprana.routine-push.plist`)도
#    같이 고쳐야 한다. 한쪽만 고치면 launchd 는 깨우는데 이 파일이 "지금이 아니다"
#    라며 안 보낸다 — 조용히 실패한다.
SCHEDULE = [(7, 30), (20, 30)]

# 예정 시각에서 이만큼 지나면 보내지 않는다.
#
# 맥이 잠들어 있었으면 launchd 는 깨어난 뒤에 밀린 작업을 뒤늦게 부른다. 그때
# 두 가지가 한꺼번에 잘못된다 — ①오후 1시에 오는 아침 알림은 쓸모가 없고
# ②`sw.js` 는 받은 시각으로 모닝/이브닝을 가리므로 **엉뚱한 루틴**을 띄운다.
# 늦은 것은 아예 안 보내는 편이 낫다.
GRACE_MINUTES = 30

HOME = os.path.expanduser("~/.routine-push")
KEY_PATH = os.path.join(HOME, "vapid_private.pem")
SUB_PATH = os.path.join(HOME, "subscription.json")
LOG_PATH = os.path.join(HOME, "push.log")

# VAPID 의 `sub` 는 푸시 서비스가 문제 생겼을 때 연락할 곳이다. 메일 주소도 되지만
# 앱 주소를 쓴다 — 남의 서버에 개인 메일을 남길 이유가 없다.
CONTACT = "https://powerprana7.github.io/morning-evening-routine/"


def b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def ssl_context() -> ssl.SSLContext:
    """인증서 꾸러미를 확실히 물린 컨텍스트를 만든다.

    python.org 에서 받은 파이썬은 **맥의 인증서 저장소를 안 쓴다.** 자기 몫의
    `cert.pem` 을 따로 두는데, `Install Certificates.command` 를 안 돌렸으면
    그 파일이 아예 없다. 그러면 `CERTIFICATE_VERIFY_FAILED` 로 전부 막힌다.

    2026-09-04 첫 발송에서 실제로 걸렸다 (기본 컨텍스트의 CA 가 0개였다).
    맥마다 다르므로 **여기서 세어 보고 비었을 때만** certifi 로 갈아탄다 —
    시스템 파이썬처럼 이미 갖춰진 곳에서는 그대로 쓴다."""
    ctx = ssl.create_default_context()
    if ctx.cert_store_stats().get("x509_ca", 0) > 0:
        return ctx
    try:
        import certifi
    except ImportError:
        raise RuntimeError(
            "이 파이썬에 인증서가 없습니다. 둘 중 하나를 하세요 — "
            f"`{sys.executable} -m pip install certifi` 또는 "
            "`/Applications/Python 3.x/Install Certificates.command` 실행")
    return ssl.create_default_context(cafile=certifi.where())


def log(msg: str) -> None:
    line = f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}  {msg}"
    os.makedirs(HOME, exist_ok=True)
    with open(LOG_PATH, "a") as f:
        f.write(line + "\n")
    print(line)


def shout(msg: str) -> None:
    """조용히 실패하지 않게 한다 (D-017 의 교훈).

    알림이 안 오는 것은 아무 소리도 안 나는 고장이라 몇 주씩 모르고 지나간다.
    보내기가 실패하면 맥 알림으로 알린다."""
    log("⚠ " + msg)
    try:
        body = msg.replace('"', "'")
        subprocess.run(
            ["osascript", "-e",
             f'display notification "{body}" with title "루틴 알림이 실패했습니다"'],
            check=False, capture_output=True, timeout=10)
    except Exception:
        pass


# ── 열쇠 ──────────────────────────────────────────────────────────────

def load_key():
    if not os.path.exists(KEY_PATH):
        return None
    with open(KEY_PATH, "rb") as f:
        return serialization.load_pem_private_key(f.read(), password=None)


def public_key_b64(key) -> str:
    raw = key.public_key().public_bytes(
        serialization.Encoding.X962,
        serialization.PublicFormat.UncompressedPoint)
    return b64(raw)


def cmd_keygen() -> int:
    if os.path.exists(KEY_PATH):
        print(f"이미 있습니다: {KEY_PATH}")
        print("공개키:", public_key_b64(load_key()))
        print()
        print("다시 만들면 폰에 등록된 알림 주소가 전부 못 쓰게 됩니다.")
        print("정말 다시 만들려면 그 파일을 먼저 지우세요.")
        return 1
    os.makedirs(HOME, exist_ok=True)
    key = ec.generate_private_key(ec.SECP256R1())
    pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption())
    fd = os.open(KEY_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "wb") as f:
        f.write(pem)
    print("열쇠를 만들었습니다:", KEY_PATH)
    print("공개키:", public_key_b64(key))
    return 0


def cmd_pubkey() -> int:
    key = load_key()
    if not key:
        print("열쇠가 없습니다. 먼저 `push-send.py keygen` 을 실행하세요.")
        return 1
    print(public_key_b64(key))
    return 0


# ── 알림 주소 등록 ────────────────────────────────────────────────────

def cmd_register(arg: str) -> int:
    try:
        sub = json.loads(arg)
    except json.JSONDecodeError as e:
        print("알림 주소를 읽지 못했습니다:", e)
        return 1
    if not isinstance(sub, dict) or not sub.get("endpoint"):
        print("`endpoint` 가 없습니다. 폰에서 복사한 것이 맞는지 확인하세요.")
        return 1
    os.makedirs(HOME, exist_ok=True)
    fd = os.open(SUB_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(sub, f, indent=2)
    log(f"알림 주소를 등록했습니다 ({sub['endpoint'][:60]}…)")
    print()
    print("이제 `push-send.py send --force` 로 지금 바로 보내 확인해 보세요.")
    return 0


# ── 보내기 ────────────────────────────────────────────────────────────

def vapid_header(key, endpoint: str) -> dict:
    """푸시 서비스에 낼 신분증(VAPID)을 만든다.

    서명은 ECDSA P-256/SHA-256 인데, 라이브러리가 주는 DER 을 그대로 쓰면 안 된다.
    JWT 규격은 r 과 s 를 32바이트씩 이어 붙인 64바이트 날것을 요구한다."""
    from urllib.parse import urlparse
    u = urlparse(endpoint)
    claims = {
        "aud": f"{u.scheme}://{u.netloc}",
        "exp": int(time.time()) + 12 * 3600,   # 규격상 최대 24시간
        "sub": CONTACT,
    }
    header = {"typ": "JWT", "alg": "ES256"}
    signing_input = (
        b64(json.dumps(header, separators=(",", ":")).encode()) + "." +
        b64(json.dumps(claims, separators=(",", ":")).encode())
    ).encode()

    der = key.sign(signing_input, ec.ECDSA(hashes.SHA256()))
    r, s = decode_dss_signature(der)
    sig = r.to_bytes(32, "big") + s.to_bytes(32, "big")

    jwt = signing_input.decode() + "." + b64(sig)
    return {"Authorization": f"vapid t={jwt}, k={public_key_b64(key)}"}


def due_now(force: bool) -> bool:
    if force:
        return True
    now = datetime.now()
    for hh, mm in SCHEDULE:
        target = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
        late = (now - target).total_seconds() / 60
        if 0 <= late <= GRACE_MINUTES:
            return True
    return False


def cmd_send(force: bool) -> int:
    if not due_now(force):
        log(f"예정 시각이 아니라 보내지 않습니다 (지금 {datetime.now():%H:%M}, "
            f"예정 {', '.join(f'{h:02d}:{m:02d}' for h, m in SCHEDULE)}). "
            f"맥이 잠들었다 늦게 깨어난 경우입니다")
        return 0

    key = load_key()
    if not key:
        shout("열쇠가 없습니다. `push-send.py keygen` 을 실행하세요")
        return 1
    if not os.path.exists(SUB_PATH):
        shout("폰이 등록돼 있지 않습니다. 폰에서 앱을 열고 '알림 켜기' 를 누르세요")
        return 1

    with open(SUB_PATH) as f:
        sub = json.load(f)
    endpoint = sub["endpoint"]

    headers = vapid_header(key, endpoint)
    headers["TTL"] = "1800"        # 30분 안에 못 넣으면 버린다. 늦은 알림은 방해다
    headers["Urgency"] = "high"    # 절전 모드를 뚫고 지금 깨우라는 뜻
    headers["Content-Length"] = "0"

    req = urllib.request.Request(endpoint, data=b"", headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20, context=ssl_context()) as res:
            log(f"보냈습니다 ({res.status})")
            return 0
    except urllib.error.HTTPError as e:
        if e.code in (404, 410):
            shout("폰의 알림 주소가 만료됐습니다. 폰에서 앱을 열고 "
                  "'알림 켜기' 를 다시 눌러 등록하세요")
        else:
            body = e.read().decode(errors="replace")[:200]
            shout(f"푸시 서비스가 거절했습니다 ({e.code}) {body}")
        return 1
    except Exception as e:
        shout(f"보내지 못했습니다: {e}")
        return 1


def cmd_status() -> int:
    key = load_key()
    print("열쇠      :", "있음" if key else "없음  ← keygen 필요")
    if key:
        print("공개키    :", public_key_b64(key))
    if os.path.exists(SUB_PATH):
        with open(SUB_PATH) as f:
            sub = json.load(f)
        print("폰 등록   : 있음", sub["endpoint"][:60] + "…")
    else:
        print("폰 등록   : 없음  ← 폰에서 '알림 켜기' 필요")
    print("보낼 시각 :", ", ".join(f"{h:02d}:{m:02d}" for h, m in SCHEDULE))
    # 인증서는 조용히 비어 있다가 보낼 때가 되어서야 터진다. 여기서 미리 만져 본다
    try:
        n = ssl_context().cert_store_stats().get("x509_ca", 0)
        print(f"인증서    : 있음 ({n}개)")
    except Exception as e:
        print("인증서    : 없음 ←", e)
    if os.path.exists(LOG_PATH):
        print("\n최근 기록:")
        with open(LOG_PATH) as f:
            for line in f.readlines()[-8:]:
                print("  " + line.rstrip())
    return 0


def main() -> int:
    args = sys.argv[1:]
    cmd = args[0] if args else "status"
    if cmd == "keygen":
        return cmd_keygen()
    if cmd == "pubkey":
        return cmd_pubkey()
    if cmd == "register":
        if len(args) < 2:
            print("사용법: push-send.py register '<폰에서 복사한 알림 주소>'")
            return 1
        return cmd_register(args[1])
    if cmd == "send":
        return cmd_send("--force" in args)
    if cmd == "status":
        return cmd_status()
    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main())
