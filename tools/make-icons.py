#!/usr/bin/env python3
"""아이콘 생성 — 의존성 0 (파이썬 표준 라이브러리만, D-002)

    tools/make-icons.py

만드는 것
    icon-192.png, icon-512.png              캔버스를 꽉 채운다. 파비콘·iOS 홈 화면·
                                            안드로이드 홈 화면(maskable). OS 가 마스크로
                                            잘라내는 자리들이다
    icon-inset-192.png, icon-inset-512.png  824/1024 둥근 사각형 + 투명 여백.
                                            매니페스트의 `any` — 안드로이드 시작 화면
                                            (스플래시)이 이것을 자른 데 없이 그대로 그린다
    mac/icon-mac-1024.png                   맥용. 같은 여백 도형

왜 셋인가 (D-019, D-028)
    잘라내는 자리는 꽉 채워야 하고(여백을 주면 두 번 줄어든다), **그대로 그리는 자리는
    여백을 직접 넣어야 한다.** 맥 독이 그랬고(D-019), 안드로이드 시작 화면도 같았다
    (D-028). 애플 표준 비율은 1024 안의 824(=80.5%), 모서리 반경은 그 크기의 약 22.4% 다.
"""

import math
import os
import struct
import zlib

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BG = (0xC2, 0x70, 0x3A)   # accent
FG = (0xFF, 0xFA, 0xF2)

# 체크 표시 — 몸통 사각형 기준 정규 좌표
SEGS = [((0.32, 0.52), (0.44, 0.65)), ((0.44, 0.65), (0.70, 0.36))]
STROKE = 0.055    # 선 두께 반경
AA = 1.2          # 가장자리 부드럽게 (픽셀)


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L = dx * dx + dy * dy
    t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def write_png(path, size, rows_fn, rgba):
    raw = bytearray()
    for y in range(size):
        raw.append(0)
        raw += rows_fn(y, size)
    def chunk(tag, data):
        return (struct.pack('>I', len(data)) + tag + data
                + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF))
    ihdr = struct.pack('>IIBBBBB', size, size, 8, 6 if rgba else 2, 0, 0, 0)
    out = (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr)
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(out)
    return len(out)


def blend(t):
    """t: 0=배경색 1=전경색"""
    return tuple(round(BG[i] + (FG[i] - BG[i]) * t) for i in range(3))


def check_alpha(nx, ny):
    """몸통 기준 정규 좌표에서 체크 표시의 진하기"""
    d = min(seg_dist(nx, ny, a[0], a[1], b[0], b[1]) for a, b in SEGS)
    return max(0.0, min(1.0, (STROKE - d) / 0.008 + 0.5))


# ── 웹·안드로이드용: 꽉 채운 정사각형 ────────────────────────────────
def full_bleed(size):
    def rows(y, n):
        out = bytearray()
        for x in range(n):
            r, g, b = blend(check_alpha((x + 0.5) / n, (y + 0.5) / n))
            out += bytes((r, g, b))
        return out
    return rows


# ── 여백 + 둥근 사각형 + 투명 배경 — 맥 독과 안드로이드 시작 화면이 함께 쓴다 ──
def inset_icon(size):
    body = size * 824 / 1024.0          # 애플 표준 비율
    margin = (size - body) / 2.0
    radius = body * 0.2237              # 애플 표준 모서리 반경
    cx = cy = size / 2.0
    half = body / 2.0

    def rows(y, n):
        out = bytearray()
        py = y + 0.5
        for x in range(n):
            px = x + 0.5
            # 둥근 사각형까지의 거리 (음수면 안쪽)
            dx = max(abs(px - cx) - (half - radius), 0.0)
            dy = max(abs(py - cy) - (half - radius), 0.0)
            dist = math.hypot(dx, dy) - radius
            alpha = max(0.0, min(1.0, 0.5 - dist / AA))
            if alpha <= 0.0:
                out += b'\x00\x00\x00\x00'
                continue
            nx = (px - margin) / body
            ny = (py - margin) / body
            r, g, b = blend(check_alpha(nx, ny))
            out += bytes((r, g, b, round(alpha * 255)))
        return out
    return rows


def main():
    for s in (192, 512):
        p = os.path.join(HERE, f'icon-{s}.png')
        n = write_png(p, s, full_bleed(s), rgba=False)
        print(f'  icon-{s}.png             {n:>9,} 바이트   (파비콘·maskable, 꽉 채움)')

    for s in (192, 512):
        p = os.path.join(HERE, f'icon-inset-{s}.png')
        n = write_png(p, s, inset_icon(s), rgba=True)
        print(f'  icon-inset-{s}.png       {n:>9,} 바이트   (시작 화면, 824/1024 여백)')

    os.makedirs(os.path.join(HERE, 'mac'), exist_ok=True)
    p = os.path.join(HERE, 'mac', 'icon-mac-1024.png')
    n = write_png(p, 1024, inset_icon(1024), rgba=True)
    print(f'  mac/icon-mac-1024.png  {n:>9,} 바이트   (맥, 824/1024 여백 + 둥근 모서리)')


if __name__ == '__main__':
    main()
