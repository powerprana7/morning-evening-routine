#!/bin/bash
# 회귀 검사 — 핵심 로직을 건드렸으면 반드시 돌린다 (CLAUDE.md 6번)
#
#   tools/check.sh
#
# 무엇을 검사하나
#   1. JS 문법이 깨지지 않았는가          (파싱)
#   2. 시간 표기 fmt() 가 맞는가          (경계값 9건)
#   3. 텍스트 ↔ 목록 변환이 맞는가        (형식 12건 + 실제 루틴 왕복 전건)
#   4. 항목 이름에 중복이 없는가
#   5. 루틴 메타(label·short·tier·theme·view·items)가 갖춰져 있는가
#   6. 뷰 방식 전환의 뼈대가 남아 있는가
#   7. 목록 뷰의 줄 순서 — 끝낸 것이 아래로, 끝낸 순서대로 (D-025)
#   8. 어두운 톤의 색 두 벌이 같은가 (기기 설정용 / 루틴 지정용, D-027)
#   9. 배포 껍데기 — 아이콘 지문이 실제 파일과 맞는가 (자동 갱신 조건, D-029)
#  10. 폰에서 맥에 닿는 길로 보내는가 — 챗이 아니라 Code (D-031)
#  11. 버전이 `날짜.번호` 꼴인가 (D-032)
#
# 이 검사가 못 하는 것 — 전부 사람이 눌러야 판정된다
#   · 소리가 실제로 나는가            (기기 볼륨·무음·자동재생 정책)
#   · 레이아웃이 깨지지 않았는가      (완료 화면 스크롤 버그가 이 구멍에서 나왔다)
#   · 터치가 편한가, 화면이 안 꺼지는가
#
# 실행기는 node 가 아니라 macOS 내장 JavaScriptCore(osascript) 다. 의존성 0 (D-002).

set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
APP="$HERE/index.html"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

red()   { printf '\033[31m%s\033[0m\n' "$1"; }
green() { printf '\033[32m%s\033[0m\n' "$1"; }

[ -f "$APP" ] || { red "✗ 본체가 없습니다: $APP"; exit 1; }

# ── 본체에서 <script> 와 ROUTINES·변환 함수를 뽑아낸다 ────────────────
python3 - "$APP" "$TMP" <<'PY'
import json, re, sys
app, tmp = sys.argv[1], sys.argv[2]
src = open(app, encoding='utf-8').read()

m = re.search(r"<script>\n(.*?)\n</script>", src, re.S)
if not m:
    print("EXTRACT_FAIL: <script> 블록을 찾지 못했습니다"); sys.exit(1)
js = m.group(1)
open(tmp + '/all.js', 'w', encoding='utf-8').write(js)

r = re.search(r"(const ROUTINES = \{.*?\n\};\n)", js, re.S)
f = re.search(r"(function parseItems.*?\n\}\n\nfunction serializeItems.*?\n\}\n)", js, re.S)
t = re.search(r"(function fmt\(ms\) \{.*?\n\}\n)", js, re.S)
if not (r and f and t):
    print("EXTRACT_FAIL: ROUTINES / parseItems / fmt 를 찾지 못했습니다")
    sys.exit(1)
open(tmp + '/parts.js', 'w', encoding='utf-8').write(
    r.group(1).replace('const ', 'var ') + '\n' + f.group(1) + '\n' + t.group(1))

# ── 6. 뷰 방식 전환 (D-024) ──
# 뷰의 기본값은 루틴이 들고 있으므로(5번에서 함께 본다) 여기서는 딱지가
# 갖춰졌는지와 화면 쪽 뼈대가 남아 있는지를 본다.
v = re.search(r"(const VIEW_LABEL = \{.*?\n\};\n)", js, re.S)
o = re.search(r"(function listOrder\(count, doneIdx\) \{.*?\n\}\n)", js, re.S)
if not (v and o):
    print("EXTRACT_FAIL: 뷰 딱지(VIEW_LABEL) 또는 listOrder 를 찾지 못했습니다")
    sys.exit(1)
# ── 8. 어두운 톤 두 벌 (D-027) ──
# CSS 가 선택자와 미디어 질의를 한 규칙으로 못 묶어서 같은 색을 두 번 적어야 한다.
# 어긋나면 기기 설정을 따를 때와 루틴이 지정할 때 색이 달라진다 — 조용히 어긋나는
# 종류라 글자 그대로 비교해 둔다.
def _vars(block):
    return sorted(x.strip() for x in re.split(r'[;\n]', block) if x.strip())

d1 = re.search(r'body\[data-theme="dark"\] \{\n(.*?)\n\}', src, re.S)
d2 = re.search(r'@media \(prefers-color-scheme: dark\) \{\n'
               r'  body\[data-theme="auto"\] \{\n(.*?)\n  \}\n\}', src, re.S)

has = {
    'darkOnce':  bool(d1),
    'darkAuto':  bool(d2),
    'darkSame':  bool(d1 and d2) and _vars(d1.group(1)) == _vars(d2.group(1)),
    'colorMeta': 'name="color-scheme"' in src and 'light dark' in src,
    'themeMeta': 'name="theme-color"' in src and 'paintThemeColor' in js,
    # CSS 와 JS 가 **같은 질의**를 봐야 한다. 한쪽만 바꾸면 화면은 밝은데
    # 홈 화면 앱의 위쪽 띠만 어두운 식으로 어긋난다 (뒤집어 보다 실제로 나왔다)
    'sameQuery': "matchMedia('(prefers-color-scheme: dark)')" in js,
    'btnView':  'id="btnView"' in src,
    'runList':  'id="runList"' in src,
    'cssOne':   '#screen-run[data-view="one"]' in src,
    'cssList':  '#screen-run[data-view="list"]' in src,
    'wired':    "$('btnView').addEventListener" in src,
    'applied':  'applyView()' in js,
    'noGlobal': 'routine.view' not in src,   # 전역 저장으로 되돌아가지 않았는가
    'rowBtn':   'class="row-btn"' in src or "'row-btn'" in src,  # 줄마다 붙는 완료 단추
    'rowWired': "$('runList').addEventListener" in src,
    'uncheck':  'function uncheckItem' in js,   # 잘못 누른 것을 되살릴 수 있는가
}

# ── 10. 폰이 맥에 닿는 길로 가는가 (D-031) ──
# 전부 "조용히 사라지는" 종류다. 폰 경로가 어긋나도 맥에서는 아무 증상이 없다.
# 특히 공유 시트로 되돌아가는 것을 막는다 — 그것은 새 챗으로 떨어져서, 맥을 건드리지
# 못한 채 "완료했다"고 답한다. 실패보다 나쁘다.
_phone_i = js.find('if (onPhone) {')
_open_i  = js.find('window.open(CODE_URL', _phone_i) if _phone_i >= 0 else -1
_clip_i  = js.find('toClipboard(', _phone_i) if _phone_i >= 0 else -1
has.update({
    # 진입 버튼을 어떤 기기에서도 감추지 않는가 (옛 pointer:fine 게이트가 되살아났나)
    'editShown':  "$('btnEdit').style.display" not in js,
    # 공유 시트로 되돌아가지 않았는가
    'noShare':    'navigator.share' not in js,
    # 여는 곳이 챗이 아니라 Code 인가
    'codeUrl':    "const CODE_URL = 'https://claude.ai/code'" in js,
    'opensCode':  _open_i >= 0,
    # 폰에서만 연다 — 데스크톱에서 창이 뜨면 방해만 된다
    'phoneGate':  'const onPhone' in js and "matchMedia('(pointer: coarse)')" in js,
    # 클립보드가 창 열기보다 **먼저** 와야 한다. 초점을 잃으면 그 뒤로는 쓰기가 막히고,
    # 앱이 링크를 안 가져갈 때 붙여넣을 것이 아무것도 남지 않는다
    'clipFirst':  0 <= _clip_i < _open_i,
    # 이 창을 떠나면 방금 고친 텍스트가 날아간다 — 반드시 새 창으로
    'newTab':     "'_blank'" in js,
    # 맥앱 직통 경로(D-020)를 갈아치우지 않았는가
    'macDirect':  'messageHandlers.claudeCode.postMessage' in js,
    # 버튼 딱지가 두 경로 다 따라오는가
    'sendLabel':  "if (inMacApp || onPhone) $('btnEditCopy').textContent" in js,
    # 지시문이 "샌드박스에 복제해 고치고 완료라고 하기"를 못박는가
    'promptWarn': 'push 까지 끝나야 반영이다' in js and '완료' in js,
})

# ── 11. 버전 꼴 (D-032) ──
# 하루에 여러 번 바꾸면서 번호를 안 올리면, 기기에 새 파일이 갔는지를 화면의 버전으로
# 판단할 수 없다. 2026-08-28 과 09-04 에 실제로 걸렸다. 맨 날짜로 되돌아가는 것을 막는다.
_v = re.search(r"const VERSION = '([^']*)'", js)
has.update({
    'verFound':  bool(_v),
    'verShape':  bool(_v) and bool(re.fullmatch(r'\d{4}-\d{2}-\d{2}\.[1-9]\d*', _v.group(1))),
    'verShown':  "$('ver').textContent = VERSION" in js,
})
open(tmp + '/view.js', 'w', encoding='utf-8').write(
    v.group(1).replace('const ', 'var ') + '\n' + o.group(1)
    + '\nvar SRC_HAS = ' + json.dumps(has) + ';\n')
PY
[ $? -eq 0 ] || { red "✗ 본체에서 코드를 뽑아내지 못했습니다 (구조가 바뀌었나요?)"; exit 1; }

# ── 검사 본문 ────────────────────────────────────────────────────────
cat > "$TMP/test.js" <<'JS'
var out = [], fail = 0, pass = 0;
function eq(label, got, want) {
  var g = JSON.stringify(got), w = JSON.stringify(want);
  if (g === w) { pass++; return; }
  fail++; out.push("  ✗ " + label + "\n      기대 " + w + "\n      실제 " + g);
}
function one(t) { var r = parseItems(t); return r.length === 1 ? r[0] : r; }

/* ── 2. 시간 표기 ── */
eq("fmt 0",       fmt(0),       "0:00");
eq("fmt 999ms",   fmt(999),     "0:01");
eq("fmt 59.4초",  fmt(59400),   "0:59");
eq("fmt 1분",     fmt(60000),   "1:00");
eq("fmt 9:59",    fmt(599000),  "9:59");
eq("fmt 1시간",   fmt(3600000), "1:00:00");
eq("fmt 1:01:01", fmt(3661000), "1:01:01");
eq("fmt 음수",    fmt(-5),      "0:00");

/* ── 3. 텍스트 ↔ 목록 ── */
eq("이름만",         one("Make bed"),                  {name:"Make bed", note:"", minutes:null});
eq("앞뒤 공백",      one("   기지개를 켠다   "),        {name:"기지개를 켠다", note:"", minutes:null});
eq("설명",           one("제자리뛰기 100회 | 가자미근"), {name:"제자리뛰기 100회", note:"가자미근", minutes:null});
eq("분",             one("오일풀링 @10"),               {name:"오일풀링", note:"", minutes:10});
eq("설명+분",        one("명상 | 조용히 @15"),          {name:"명상", note:"조용히", minutes:15});
eq("설명 속 슬래시", one("Brush | 치실 / 워터픽스"),    {name:"Brush", note:"치실 / 워터픽스", minutes:null});
eq("빈줄·주석 무시", parseItems("A\n\n# 메모\n  \nB").length, 2);
eq("@ 가 이름 일부", one("이메일 @회사 확인"),          {name:"이메일 @회사 확인", note:"", minutes:null});
eq("@ 가 설명 일부", one("약 | 식후 @에 먹기"),         {name:"약", note:"식후 @에 먹기", minutes:null});
eq("@0 은 무효",     one("X @0"),                      {name:"X", note:"", minutes:null});
eq("이름 없는 줄",   parseItems("| 설명만").length,     0);
eq("전부 빈 입력",   parseItems("\n\n   \n").length,    0);

/* 실제 루틴 왕복 — 직렬화했다 되읽으면 원본과 같아야 한다.
   여기가 깨지면 편집 화면에서 저장하는 순간 루틴이 망가진다. */
Object.keys(ROUTINES).forEach(function (k) {
  var orig = ROUTINES[k].items;
  var back = parseItems(serializeItems(orig));
  eq("왕복 " + k + " 개수", back.length, orig.length);
  for (var i = 0; i < orig.length; i++) eq("왕복 " + k + " #" + (i + 1), back[i], orig[i]);
});

/* ── 4. 이름 중복 ── */
Object.keys(ROUTINES).forEach(function (k) {
  var names = ROUTINES[k].items.map(function (i) { return i.name; });
  var dup = names.filter(function (n, i) { return names.indexOf(n) !== i; });
  eq("중복 없음 " + k, dup, []);
});

/* ── 5. 루틴 메타 (D-023) ──
   루틴을 늘릴 때 메타를 빠뜨리면 시작 화면에 안 뜨거나 톤이 어긋난다.
   화면을 안 띄우고 잡을 수 있는 것은 여기까지다. */
Object.keys(ROUTINES).forEach(function (k) {
  var r = ROUTINES[k];
  eq("메타 label " + k,  typeof r.label === "string" && r.label.length > 0, true);
  eq("메타 short " + k,  typeof r.short === "string" && r.short.length > 0, true);
  eq("메타 tier " + k,   r.tier === "main" || r.tier === "more", true);
  eq("메타 theme " + k,  r.theme === "auto" || r.theme === "light" || r.theme === "dark", true);
  eq("메타 view " + k,   r.view === "one" || r.view === "list", true);
  eq("메타 items " + k,  Array.isArray(r.items) && r.items.length > 0, true);
});
/* 시작 화면이 비면 앱을 시작할 방법이 없다 */
eq("main 루틴이 하나 이상",
   Object.keys(ROUTINES).filter(function (k) { return ROUTINES[k].tier === "main"; }).length > 0,
   true);
/* 시간대 제안(정오 경계)이 가리키는 두 키는 반드시 있어야 한다 */
eq("제안 대상 morning 존재", !!ROUTINES.morning, true);
eq("제안 대상 evening 존재", !!ROUTINES.evening, true);

/* ── 6. 뷰 방식 전환 (D-024) ──
   "한 화면에 한 항목"은 실행 순서가 중요한 루틴에 걸리는 원칙이다. 순서와
   무관하게 훑는 체크리스트에는 그 근거가 없어 목록으로 연다.
   위험한 것은 목록이 순서가 중요한 루틴까지 번지는 것이므로 두 가지를 못박는다 —
   순서가 중요한 셋은 'one' 이어야 하고, 실행 중 전환은 저장되지 않아야 한다. */
eq("모닝은 한 항목",        ROUTINES.morning.view,   "one");
eq("이브닝은 한 항목",      ROUTINES.evening.view,   "one");
eq("수련·운동은 한 항목",   ROUTINES.practice.view,  "one");
eq("출국 전은 목록",        ROUTINES.departure.view, "list");
eq("뷰를 저장하지 않는다",  SRC_HAS.noGlobal, true);
eq("뷰는 두 가지뿐",        Object.keys(VIEW_LABEL).sort(), ["list", "one"]);
["one", "list"].forEach(function (v) {
  var t = VIEW_LABEL[v];
  eq("뷰 딱지 글자 " + v, typeof t.text  === "string" && t.text.length  > 0, true);
  eq("뷰 딱지 그림 " + v, typeof t.glyph === "string" && t.glyph.length > 0, true);
  eq("뷰 딱지 읽기 " + v, typeof t.aria  === "string" && t.aria.length  > 0, true);
});
eq("전환 버튼이 있다",       SRC_HAS.btnView, true);
eq("목록 담을 자리가 있다",  SRC_HAS.runList, true);
eq("한 항목 뷰 CSS 규칙",    SRC_HAS.cssOne,  true);
eq("목록 뷰 CSS 규칙",       SRC_HAS.cssList, true);
eq("전환 버튼이 연결됐다",   SRC_HAS.wired,   true);
eq("시작할 때 뷰를 건다",    SRC_HAS.applied, true);
eq("줄마다 완료 단추가 있다", SRC_HAS.rowBtn,   true);
eq("줄 단추가 연결됐다",     SRC_HAS.rowWired, true);
eq("완료를 되돌릴 수 있다",  SRC_HAS.uncheck,  true);

/* ── 7. 목록 뷰의 줄 순서 (D-025) ──
   목록 뷰는 순서와 무관하게 아무 줄이나 완료할 수 있고, 끝낸 것은 아래로
   내려가 흐리게 뜬다. 그 순서를 정하는 것이 listOrder 다 — 상태를 안 쓰는
   순수 함수라 화면 없이 돌려볼 수 있는 몇 안 되는 부분이다.
   여기가 틀리면 훑는 도중 줄이 엉뚱한 데로 튀어 어디까지 했는지를 잃는다. */
eq("아무것도 안 했을 때",   listOrder(5, []),           [0, 1, 2, 3, 4]);
eq("가운데 하나를 끝내면",  listOrder(5, [2]),          [0, 1, 3, 4, 2]);
eq("끝낸 순서대로 쌓인다",  listOrder(5, [3, 0]),       [1, 2, 4, 3, 0]);
eq("거꾸로 다 끝내면",      listOrder(5, [4, 3, 2, 1, 0]), [4, 3, 2, 1, 0]);
eq("차례대로 다 끝내면",    listOrder(3, [0, 1, 2]),    [0, 1, 2]);
eq("빈 루틴",               listOrder(0, []),           []);
eq("범위 밖 번호는 버린다", listOrder(3, [7]),          [0, 1, 2]);
eq("줄 수는 늘 그대로",     listOrder(9, [5, 1]).length, 9);

/* ── 8. 화면 톤 (D-027) ──
   기기의 밝게/어둡게 설정을 따르려면 어두운 톤의 색을 두 벌 적어야 한다
   (선택자용 · 미디어 질의용). 두 벌이 어긋나면 기기 설정을 따를 때와 루틴이
   못박을 때 색이 달라지는데, 둘을 나란히 볼 일이 없어 조용히 어긋난다. */
eq("어두운 톤 (루틴 지정용)", SRC_HAS.darkOnce, true);
eq("어두운 톤 (기기 설정용)", SRC_HAS.darkAuto, true);
eq("두 벌의 색이 같다",       SRC_HAS.darkSame, true);
eq("color-scheme 메타",       SRC_HAS.colorMeta, true);
eq("위쪽 띠 색을 맞춘다",     SRC_HAS.themeMeta, true);
eq("CSS 와 JS 가 같은 질의",  SRC_HAS.sameQuery, true);
/* 넷 다 기기 설정을 따르는 것이 지금의 결정이다 (D-027). 하나라도 못박혀 있으면
   그 루틴만 기기 설정을 무시하게 되므로 눈에 띄게 실패시킨다 */
Object.keys(ROUTINES).forEach(function (k) {
  eq("기기 설정을 따른다 " + k, ROUTINES[k].theme, "auto");
});

/* ── 10. 폰이 맥에 닿는 길로 가는가 (D-031) ──
   길은 셋이다 — 맥앱은 터미널 직통(D-020), 폰은 복사 + `Code` 화면, 데스크톱
   브라우저는 복사. 폰만 새로 생겼고, 폰만 틀린 곳으로 갈 수 있다.
   첫 판의 공유 시트는 새 챗으로 떨어졌다. 챗 클로드는 자기 샌드박스에 저장소를
   새로 받아 고치고 "완료"라고 답한다 — 맥에는 아무 일도 일어나지 않는데 화면에는
   성공이라고 적힌다. 되돌아가지 않게 못박는다. */
eq("편집 진입을 감추지 않는다",     SRC_HAS.editShown, true);
eq("공유 시트로 되돌아가지 않았다", SRC_HAS.noShare,   true);
eq("여는 곳이 Code 다",             SRC_HAS.codeUrl,   true);
eq("실제로 연다",                   SRC_HAS.opensCode, true);
eq("여는 것은 폰에서만",            SRC_HAS.phoneGate, true);
eq("복사가 창 열기보다 먼저",       SRC_HAS.clipFirst, true);
eq("새 창으로 연다",                SRC_HAS.newTab,    true);
eq("맥앱 직통 경로가 남아 있다",    SRC_HAS.macDirect, true);
eq("버튼 딱지가 두 경로를 따른다",  SRC_HAS.sendLabel, true);
eq("지시문이 샌드박스 작업을 막는다", SRC_HAS.promptWarn, true);

/* ── 11. 버전 꼴 (D-032) ──
   `YYYY-MM-DD.N`. 번호가 빠지면 하루에 여러 판이 같은 이름이 되어, 폰에 새 파일이
   갔는지를 화면만 보고 못 가린다 — 두 번 걸렸던 구멍이다. */
eq("버전이 있다",         SRC_HAS.verFound, true);
eq("버전이 날짜.번호 꼴", SRC_HAS.verShape, true);
eq("버전을 화면에 띄운다", SRC_HAS.verShown, true);

out.unshift(fail ? "실패 " + fail + "건 / 통과 " + pass + "건"
                 : "통과 " + pass + "건 / 실패 0건");
out.push(fail ? "RESULT_FAIL" : "RESULT_OK");
out.join("\n");
JS

RESULT="$(osascript -l JavaScript -e "
ObjC.import('Foundation');
function read(p){ return \$.NSString.stringWithContentsOfFileEncodingError(p, \$.NSUTF8StringEncoding, null).js; }
var all = read('$TMP/all.js');
try { new Function(all); } catch(e) { '문법 오류: ' + e.message + '\nRESULT_FAIL'; }
" 2>&1)"

case "$RESULT" in
  *RESULT_FAIL*) red "✗ 1. JS 문법"; echo "$RESULT"; exit 1 ;;
esac
green "✓ 1. JS 문법"

RESULT="$(osascript -l JavaScript -e "
ObjC.import('Foundation');
function read(p){ return \$.NSString.stringWithContentsOfFileEncodingError(p, \$.NSUTF8StringEncoding, null).js; }
eval(read('$TMP/parts.js'));
eval(read('$TMP/view.js'));
eval(read('$TMP/test.js'));
" 2>&1)"

echo "$RESULT" | grep -v RESULT_

case "$RESULT" in
  *RESULT_OK*)
    green "✓ 2~8·10·11. 시간 표기 · 텍스트 변환 · 중복 · 루틴 메타 · 뷰 전환 · 줄 순서 · 화면 톤 · 전달 경로 · 버전 꼴" ;;
  *)
    red "✗ 2~8·10·11 실패"
    echo
    red "회귀 검사 실패 — 로직을 되돌리거나, 의도한 변경이면 DECISIONS 에 근거를 남기고 검사를 고치세요."
    exit 1 ;;
esac

# ── 9. 배포 껍데기 — 아이콘이 저절로 갈아끼워지는 조건 (D-029) ─────────
#
# 자동 갱신은 "아이콘 주소가 바뀌었나"로 판정된다. 지문(`?v=`)이 빠지거나
# 실제 파일과 어긋나면, 기기에서는 옛 아이콘이 계속 뜨는데 여기서는 아무 일도
# 없어 보인다. 그 침묵이 이 검사가 막으려는 것이다.
if ! python3 - "$HERE" <<'PY'
import hashlib, json, os, re, sys

HERE = sys.argv[1]
fail = []

mpath = os.path.join(HERE, 'manifest.webmanifest')
try:
    m = json.load(open(mpath, encoding='utf-8'))
except Exception as e:
    print(f'  매니페스트가 올바른 JSON 이 아니다: {e}')
    sys.exit(1)

icons = m.get('icons', [])
if not icons:
    fail.append('매니페스트에 아이콘이 하나도 없다')

purposes = {i.get('purpose') for i in icons}
for need, why in (('any', '시작 화면(스플래시)이 쓴다'), ('maskable', '홈 화면 아이콘이 쓴다')):
    if need not in purposes:
        fail.append(f'purpose "{need}" 아이콘이 없다 — {why}')

for i in icons:
    src = i.get('src', '')
    m2 = re.fullmatch(r'([A-Za-z0-9._-]+\.png)\?v=([0-9a-f]{8})', src)
    if not m2:
        fail.append(f'{src!r} 에 지문이 없다 — tools/make-icons.py 를 돌려라')
        continue
    name, stamp = m2.group(1), m2.group(2)
    fpath = os.path.join(HERE, name)
    if not os.path.exists(fpath):
        fail.append(f'{name} 파일이 없다')
        continue
    real = hashlib.sha256(open(fpath, 'rb').read()).hexdigest()[:8]
    if real != stamp:
        fail.append(f'{name} 지문이 어긋난다 (매니페스트 {stamp} / 실제 {real}) '
                    '— tools/make-icons.py 를 돌려라')

# 서비스워커가 아이콘 이름을 또 적어 두면 두 곳이 어긋난다 (D-029)
sw = open(os.path.join(HERE, 'sw.js'), encoding='utf-8').read()
body = re.sub(r'/\*.*?\*/', '', sw, flags=re.S)
body = re.sub(r'//[^\n]*', '', body)
if re.search(r'icon-[A-Za-z0-9-]*\.png', body):
    fail.append('sw.js 가 아이콘 이름을 직접 적고 있다 — 매니페스트에서 읽어야 한다')

for f in fail:
    print('  ' + f)
sys.exit(1 if fail else 0)
PY
then
  red "✗ 9. 배포 껍데기 — 아이콘 자동 갱신 조건이 깨졌습니다"
  echo
  red "회귀 검사 실패 — 이대로 올리면 기기에서 아이콘이 저절로 안 바뀝니다."
  exit 1
fi
green "✓ 9. 배포 껍데기 — 아이콘 지문·purpose·서비스워커"

# ── 12. 정해진 시각 알림 (D-033) ──────────────────────────────────────
# 여기서 어긋나는 것은 **전부 조용히 실패한다.** 알림이 안 오는 것은 아무 소리도
# 안 나는 고장이라 몇 주씩 모르고 지나간다. 특히 시각이 두 파일에 적혀 있는 것
# (`push-send.py` 의 SCHEDULE · `push-setup.sh` 의 StartCalendarInterval)이
# 위험하다 — 한쪽만 고치면 launchd 는 깨우는데 스크립트가 안 보낸다.
if ! python3 - "$HERE" <<'PY'
import base64, os, re, sys
HERE = sys.argv[1]
fail, warn = [], []

app  = open(os.path.join(HERE, 'index.html'), encoding='utf-8').read()
sw   = open(os.path.join(HERE, 'sw.js'), encoding='utf-8').read()
send = open(os.path.join(HERE, 'tools/push-send.py'), encoding='utf-8').read()
setup= open(os.path.join(HERE, 'tools/push-setup.sh'), encoding='utf-8').read()

# 앱이 든 공개키가 규격에 맞는가 — 65바이트 비압축 P-256 점, 0x04 로 시작
m = re.search(r"const VAPID_PUBLIC =\s*\n?\s*'([A-Za-z0-9_-]+)'", app)
if not m:
    fail.append('index.html 에 VAPID_PUBLIC 이 없다 — 알림을 켤 수 없다')
else:
    raw = base64.urlsafe_b64decode(m.group(1) + '=' * (-len(m.group(1)) % 4))
    if len(raw) != 65 or raw[0] != 4:
        fail.append(f'VAPID_PUBLIC 이 공개키 꼴이 아니다 ({len(raw)}바이트)')

# 비밀키는 절대 저장소에 들어오면 안 된다 (이 저장소만 Public — CLAUDE.md 7번)
for name in ('index.html', 'sw.js', 'tools/push-send.py', 'tools/push-setup.sh'):
    if 'BEGIN PRIVATE KEY' in open(os.path.join(HERE, name), encoding='utf-8').read():
        fail.append(f'{name} 에 비밀키가 들어 있다 — 절대 커밋하면 안 된다')

# 받는 쪽이 갖춰져 있는가
if "addEventListener('push'" not in sw:
    fail.append('sw.js 에 push 처리가 없다 — 알림이 와도 아무 일도 안 일어난다')
if "addEventListener('notificationclick'" not in sw:
    fail.append('sw.js 에 notificationclick 이 없다 — 눌러도 루틴이 안 열린다')
for key in ('morning', 'evening'):
    if f"{key}:" not in sw.split('const NOTICE')[-1][:400]:
        fail.append(f'sw.js 의 NOTICE 에 {key} 문구가 없다')
if 'userVisibleOnly: true' not in app:
    fail.append('userVisibleOnly 가 없다 — 안드로이드에서 구독이 거절된다')
if "get('routine')" not in app:
    fail.append('앱이 ?routine= 을 읽지 않는다 — 알림을 눌러도 그 루틴이 안 열린다')
if 'history.replaceState' not in app:
    fail.append('?routine= 을 주소에서 지우지 않는다 — 갱신 때 루틴이 처음부터 다시 돈다')

# ⚠ 시각이 두 곳에 적혀 있다. 어긋나면 조용히 안 온다
py_times = set(re.findall(r'\((\d+),\s*(\d+)\)', send.split('SCHEDULE = [')[-1].split(']')[0]))
sh_times = set(zip(re.findall(r'<key>Hour</key><integer>(\d+)</integer>', setup),
                   re.findall(r'<key>Minute</key><integer>(\d+)</integer>', setup)))
if not py_times:
    fail.append('push-send.py 의 SCHEDULE 을 읽지 못했다')
elif py_times != sh_times:
    fail.append(f'보낼 시각이 두 파일에서 어긋난다 — '
                f'push-send.py {sorted(py_times)} / push-setup.sh {sorted(sh_times)}')

# 이 맥에 깔린 사본이 낡았는가. 다른 기기에는 없는 것이 정상이라 경고만 한다
dest = os.path.expanduser('~/.routine-push/push-send.py')
if os.path.exists(dest) and open(dest, encoding='utf-8').read() != send:
    warn.append('~/.routine-push/push-send.py 가 저장소본과 다르다 '
                '— tools/push-setup.sh 를 다시 돌려라')

for w in warn: print('  ⚠ ' + w)
for f in fail: print('  ' + f)
sys.exit(1 if fail else 0)
PY
then
  red "✗ 12. 정해진 시각 알림 — 조용히 실패할 자리가 생겼습니다"
  echo
  red "회귀 검사 실패 — 이대로 올리면 알림이 아무 소리 없이 안 옵니다."
  exit 1
fi
green "✓ 12. 정해진 시각 알림 — 공개키·수신·시각 일치"

echo
green "회귀 검사 통과"
printf '\033[33m%s\033[0m\n' "다만 소리·레이아웃·터치는 이 검사가 판정하지 못합니다 — 손으로 확인하세요."
exit 0
