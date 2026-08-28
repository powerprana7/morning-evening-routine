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
has = {
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
  eq("메타 theme " + k,  r.theme === "light" || r.theme === "dark", true);
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
    green "✓ 2~7. 시간 표기 · 텍스트 변환 · 중복 · 루틴 메타 · 뷰 전환 · 줄 순서"
    echo
    green "회귀 검사 통과"
    printf '\033[33m%s\033[0m\n' "다만 소리·레이아웃·터치는 이 검사가 판정하지 못합니다 — 손으로 확인하세요."
    exit 0 ;;
  *)
    red "✗ 2~7 실패"
    echo
    red "회귀 검사 실패 — 로직을 되돌리거나, 의도한 변경이면 DECISIONS 에 근거를 남기고 검사를 고치세요."
    exit 1 ;;
esac
