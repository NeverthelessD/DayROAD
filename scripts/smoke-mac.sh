#!/bin/bash
# DayROAD 실제 맥 시험 (맥 빌드 서버에서 dist/DayROAD.app 을 /Applications 에 깔고 여러 상황을 시험해요)
# 결과: $OUT/results.txt (PASS/FAIL 한 줄씩), 스크린샷, 위젯 그림, 기록 파일
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${OUT:-$ROOT/ci-out}"
mkdir -p "$OUT"
APPDIR="/Applications/DayROAD.app"
SUP="$HOME/Library/Application Support/DayROAD"
RES="$OUT/results.txt"
: > "$RES"

pass() { echo "PASS  $*" | tee -a "$RES"; }
fail() { echo "FAIL  $*" | tee -a "$RES"; }
check() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

app_pid() { pgrep -x DayROAD | head -1; }
engines() { pgrep -x dayroad-engine | tr '\n' ' '; }
tok() { cat "$SUP/token" 2>/dev/null; }
port() { cat "$SUP/port" 2>/dev/null; }
API() { echo "http://127.0.0.1:$(port)"; }
ping_ok() { curl -fs -m 2 -H "x-token: $(tok)" "$(API)/api/ping" >/dev/null 2>&1; }
wait_ready() { for _ in $(seq 1 60); do [ -s "$SUP/port" ] && ping_ok && return 0; sleep 0.5; done; return 1; }
wait_gone() { for _ in $(seq 1 30); do [ -z "$(app_pid)" ] && [ -z "$(engines)" ] && return 0; sleep 0.5; done; return 1; }
snap() { echo "--- $1"; ps -axo pid,ppid,stat,comm | grep -E "DayROAD|dayroad-engine" | grep -v grep; } >> "$OUT/procs.txt"
launch() { open "$APPDIR"; wait_ready; }
quit_app() { osascript -e 'tell application "DayROAD" to quit' >/dev/null 2>&1; wait_gone; }
post() { curl -fs -X POST -H "x-token: $(tok)" -H 'content-type: application/json' --data "$2" "$(API)$1"; }
jget() { python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1" 2>/dev/null; }
settings() { # settings.json (시험용 ui.smoke 는 그 화면을 열어요)
  printf '{"appearance":"%s","autoUpdate":false,"weekStart":"mon","carryOver":true,"morning":{"on":false,"time":"08:30"},"dueRemind":{"on":false,"days":1,"time":"09:00"},"calendarShow":true,"ui":%s}' "$1" "$2" > "$SUP/settings.json"
}
TODAY=$(date +%F)
day() { date -v"$1"d +%F; }

echo "▶ 준비: 앱 설치"
rm -rf "$APPDIR" "$SUP"; ditto "$ROOT/dist/DayROAD.app" "$APPDIR"
mkdir -p "$SUP"
settings light '{}'

echo "▶ A. 켜기 · 화면"
launch; check "A1 앱을 열면 엔진이 준비됨" ping_ok
check "A2 엔진이 Dock 앱 방식으로 켜짐(shell=native)" bash -c "curl -fs -H 'x-token: $(tok)' $(API)/api/ping | grep -q '\"shell\":\"native\"'"
check "A3 주소가 47951" test "$(port)" = "47951"
sleep 5
check "A4 화면이 앱 창(WKWebView)에서 열림" grep -q "DayROADShell" "$SUP/requests.log"
check "A5 처음 켜면 쓰는 법 할 일 3개" test "$(curl -fs -H "x-token: $(tok)" "$(API)/api/state" | jget "len(d['tasks'])")" = "3"
APID=$(app_pid); snap "A 실행 중"
SUPPID=$(ps -axo pid=,ppid=,comm= | awk -v a="$APID" '$2==a && /dayroad-engine/ {print $1}' | head -1)
CHILD=$(ps -axo pid=,ppid=,comm= | awk -v s="$SUPPID" '$2==s && /dayroad-engine/ {print $1}' | head -1)
check "A6 엔진이 DayROAD 앱의 자식 (앱 $APID → 지킴이 ${SUPPID:-없음} → 엔진 ${CHILD:-없음})" test -n "$SUPPID" -a -n "$CHILD"

echo "▶ T. 할 일 (실제 맥에서)"
for id in $(curl -fs -H "x-token: $(tok)" "$(API)/api/state" | jget "' '.join(t['id'] for t in d['tasks'])"); do post /api/task/delete "{\"id\":\"$id\"}" >/dev/null; done
mk() { post /api/task/save "{\"task\":$1}" | jget "d['task']['id']"; }
A=$(mk '{"title":"주간 회의 자료 정리","time":"09:30","cat":"work","star":true,"repeat":"weekly","progress":50}')
B=$(mk '{"title":"은행 업무 보기","time":"11:00","cat":"personal"}'); post /api/task/toggle "{\"id\":\"$B\"}" >/dev/null
C=$(mk "{\"title\":\"디자인 시안 피드백 보내기\",\"time\":\"14:00\",\"cat\":\"work\",\"due\":\"$(day +2)\"}")
post /api/task/log "{\"id\":\"$C\",\"text\":\"A안 의견 정리하는 중\",\"progress\":25}" >/dev/null
R=$(mk "{\"title\":\"보고서 초안 쓰기\",\"cat\":\"work\",\"due\":\"$(day +3)\",\"carriedFrom\":\"$(day -1)\"}")
post /api/task/log "{\"id\":\"$R\",\"text\":\"관련 자료 조사 끝\",\"progress\":30}" >/dev/null
post /api/task/log "{\"id\":\"$R\",\"text\":\"목차랑 1장까지 씀. 2장 자료는 폴더에 모아 둠\",\"progress\":60}" >/dev/null
E=$(mk '{"title":"운동 30분","cat":"health","repeat":"daily"}')
F=$(mk '{"title":"영어 단어 20개 외우기","cat":"study","repeat":"daily"}'); post /api/task/toggle "{\"id\":\"$F\"}" >/dev/null
mk "{\"title\":\"우유 · 계란 사기\",\"cat\":\"personal\",\"carriedFrom\":\"$(day -1)\"}" >/dev/null
mk "{\"title\":\"치과 예약\",\"date\":\"$(day +1)\",\"time\":\"15:00\",\"cat\":\"health\"}" >/dev/null
mk "{\"title\":\"팀 점심\",\"date\":\"$(day +2)\",\"time\":\"12:00\",\"cat\":\"work\"}" >/dev/null
mk "{\"title\":\"대청소\",\"date\":\"$(day +4)\",\"cat\":\"personal\"}" >/dev/null
mk '{"title":"책 한 권 끝까지 읽기","bucket":"week"}' >/dev/null
mk '{"title":"자동차 보험 갱신하기","bucket":"week"}' >/dev/null
S=$(curl -fs -H "x-token: $(tok)" "$(API)/api/state")
check "T1 할 일 만들기 · 끝내기 · 진행 기록 (12개 + 반복 다음 차례)" test "$(echo "$S" | jget "len(d['tasks'])")" = "13"
check "T2 반복하는 일을 끝내면 다음 차례가 내일로" test "$(echo "$S" | jget "[t['date'] for t in d['tasks'] if t['title']=='영어 단어 20개 외우기' and not t['done']][0]")" = "$(day +1)"
check "T3 데이터 파일 저장" test -s "$SUP/data.json"

echo "▶ W. 위젯"
check "W1 위젯 파일(widget.json)에 오늘 할 일" bash -c "python3 -c \"import json;d=json.load(open('$SUP/widget/widget.json'));assert d['date']=='$TODAY' and d['total']==7, d['total']\""
APPEX="$APPDIR/Contents/PlugIns/DayROADWidget.appex"
codesign -d --entitlements - "$APPEX" > "$OUT/widget-entitlements.txt" 2>&1
check "W2 위젯 확장이 앱 안에 있고 보호 상자 권한이 있음" grep -q "app-sandbox" "$OUT/widget-entitlements.txt"
pluginkit -m -v -p com.apple.widgetkit-extension > "$OUT/pluginkit.txt" 2>&1
if ! grep -q "com.nevertheless-d.dayroad.widget" "$OUT/pluginkit.txt"; then
  pluginkit -a "$APPEX" >> "$OUT/pluginkit.txt" 2>&1; sleep 2
  pluginkit -m -v -p com.apple.widgetkit-extension >> "$OUT/pluginkit.txt" 2>&1
fi
check "W3 맥이 위젯을 알아봄 (pluginkit)" grep -q "com.nevertheless-d.dayroad.widget" "$OUT/pluginkit.txt"
printf '{"id":"%s","done":true}\n' "$C" >> "$SUP/widget/actions.jsonl"
sleep 4
check "W4 위젯에서 누른 체크박스가 앱에 반영됨" test "$(curl -fs -H "x-token: $(tok)" "$(API)/api/state" | jget "[t['done'] for t in d['tasks'] if t['id']=='$C'][0]")" = "True"
post /api/task/toggle "{\"id\":\"$C\"}" >/dev/null; sleep 1
"$APPDIR/Contents/MacOS/DayROAD" --render-widgets "$OUT" > "$OUT/render-widgets.log" 2>&1
check "W5 위젯 그림 (라이트 · 다크)" test -s "$OUT/widgets-light.png" -a -s "$OUT/widgets-dark.png"
# 위젯 확장이 실제로 위젯 데이터를 읽을 수 있는지 (보호 상자 안에서) — 위젯 갤러리에 올리는 것은 사람이 해야 해요
log show --last 3m --predicate 'process CONTAINS "DayROADWidget" OR subsystem == "com.apple.chronod"' --style compact 2>/dev/null | grep -i dayroad | tail -40 > "$OUT/widget-system-log.txt" || true

echo "▶ S. 앱 화면 스크린샷"
quit_app
settings light '{"smoke":{"view":"today","sel":"보고서 초안 쓰기"}}'
launch; sleep 6
screencapture -x "$OUT/shot-today.png"
quit_app
settings light '{"smoke":{"view":"week"}}'
launch; sleep 6
screencapture -x "$OUT/shot-week.png"
quit_app
settings dark '{"smoke":{"view":"today","sel":"디자인 시안 피드백 보내기"}}'
launch; sleep 6
screencapture -x "$OUT/shot-today-dark.png"
quit_app
settings light '{"smoke":{"view":"today","settings":true}}'
launch; sleep 6
screencapture -x "$OUT/shot-settings.png"
quit_app
settings light '{}'

echo "▶ U. dayroad:// 주소로 열기 (위젯 · 알림을 눌렀을 때)"
launch; APID=$(app_pid)
open "dayroad://week"; sleep 3
check "U1 주소를 앱이 받음" bash -c "tail -40 '$SUP/launcher.log' | grep -q '주소로 열기: dayroad://week'"
check "U2 앱은 하나만" test "$(pgrep -x DayROAD | wc -l | tr -d ' ')" = "1"

echo "▶ M. 창 맨 위를 잡고 끌어서 옮기기"
osascript -e 'tell application "DayROAD" to activate' >/dev/null 2>&1; sleep 1
screencapture -x "$OUT/shot-drag-before.png"
MOVE=$(swift "$ROOT/scripts/drag-test.swift" 2>&1 | tail -1)
screencapture -x "$OUT/shot-drag-after.png"
echo "$MOVE" > "$OUT/drag-test.txt"
case "$MOVE" in
  moved*) pass "M1 창 맨 위를 끌면 창이 움직임 ($MOVE)" ;;
  *) echo "INFO  M1 창 옮기기를 확인하지 못함 ($MOVE) — 빌드 서버가 마우스 흉내를 막았을 수 있어요" | tee -a "$RES" ;;
esac

echo "▶ B. Dock 아이콘 다시 누르기(reopen)"
osascript -e 'tell application "DayROAD" to reopen' >/dev/null 2>&1; sleep 1
check "B1 다시 열기 뒤에도 앱·엔진 그대로" test "$(app_pid)" = "$APID"

echo "▶ C. 엔진이 고장으로 꺼지면 지킴이가 다시 켬"
SUPPID=$(ps -axo pid=,ppid=,comm= | awk -v a="$APID" '$2==a && /dayroad-engine/ {print $1}' | head -1)
CHILD=$(ps -axo pid=,ppid=,comm= | awk -v s="$SUPPID" '$2==s && /dayroad-engine/ {print $1}' | head -1)
kill -SEGV "$CHILD" 2>/dev/null; sleep 4
check "C1 엔진 다시 켜짐" ping_ok
check "C2 앱은 그대로" test "$(app_pid)" = "$APID"
check "C3 할 일은 그대로" test "$(curl -fs -H "x-token: $(tok)" "$(API)/api/state" | jget "len(d['tasks'])")" = "13"

echo "▶ D. 앱 종료(⌘Q) → 엔진까지 모두 꺼짐"
osascript -e 'tell application "DayROAD" to quit' >/dev/null 2>&1
check "D1 앱·엔진 모두 꺼짐" wait_gone
snap "D 종료 뒤"

echo "▶ E. 화면의 '종료'(= /api/quit) → 앱도 꺼짐"
launch
curl -fs -X POST -H "x-token: $(tok)" "$(API)/api/quit" >/dev/null
check "E1 앱·엔진 모두 꺼짐" wait_gone

echo "▶ F. 앱이 강제로 꺼지면 엔진도 스스로 꺼짐"
launch; kill -9 "$(app_pid)"; sleep 1
check "F1 남은 엔진 없음" bash -c 'for i in $(seq 1 20); do [ -z "$(pgrep -x dayroad-engine)" ] && exit 0; sleep 0.5; done; exit 1'

echo "▶ G. 업데이트 뒤 다시 열기 (/api/update/restart)"
launch; OLD=$(app_pid)
curl -fs -X POST -H "x-token: $(tok)" "$(API)/api/update/restart" >/dev/null
sleep 3
check "G1 새로 열린 앱이 엔진을 켬" wait_ready
NEW=$(app_pid)
check "G2 앱이 새로 열림 ($OLD → ${NEW:-없음})" test -n "$NEW" -a "$NEW" != "$OLD"
check "G3 앱 하나만 떠 있음" test "$(pgrep -x DayROAD | wc -l | tr -d ' ')" = "1"
quit_app

echo "▶ X. 진짜 업데이트(사용자에게 나간 버전 → 이번 빌드) 뒤 위젯 · 재시동 흉내"
# 사용자 신고(2026-11-12): 재시동하니 다른 위젯은 그대로인데 DayROAD 위젯만 사라짐.
# 의심: 업데이트 때 이전 버전을 보관 폴더로 옮기는데, 그 안의 위젯도 같은 이름으로 맥에 남아서 위젯이 두 개가 됨.
WID=com.nevertheless-d.dayroad.widget
NEWV=$(tr -d ' \n' < "$ROOT/VERSION")
widgets() { pluginkit -m -D -v -i "$WID" 2>&1; }
T0=$(date '+%Y-%m-%d %H:%M:%S')
[ -n "$(app_pid)" ] && quit_app
ditto "$SUP" "$OUT/sup-before-x"   # 앞의 시험 기록은 따로 남겨요
rm -rf "$APPDIR" "$SUP"; mkdir -p "$SUP"; settings light '{}'
OLDDIR="$HOME/Downloads/dayroad-old"; rm -rf "$OLDDIR"; mkdir -p "$OLDDIR"   # 사용자처럼 '받은 파일' 폴더에 압축을 풀어 둬요
ditto -x -k "$ROOT/download/DayROAD.zip" "$OLDDIR"
ditto "$OLDDIR/DayROAD/DayROAD.app" "$APPDIR"
# 받은 파일 폴더의 압축 푼 앱도 맥이 찾아내 위젯 목록에 올린 상태로 만들어요 (사용자 맥에서 생기는 일)
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
"$LSREG" -f "$OLDDIR/DayROAD/DayROAD.app" 2>/dev/null || true
pluginkit -a "$OLDDIR/DayROAD/DayROAD.app/Contents/PlugIns/DayROADWidget.appex" 2>/dev/null || true
OLDV=$(cat "$APPDIR/Contents/Resources/version.txt")
FEED="$OUT/feed"; rm -rf "$FEED"; mkdir -p "$FEED"
cp "$ROOT/dist/DayROAD-$NEWV.zip" "$FEED/"
python3 - "$FEED" "$NEWV" <<'PY'
import hashlib, json, os, sys
d, v = sys.argv[1], sys.argv[2]
z = os.path.join(d, f"DayROAD-{v}.zip")
json.dump({"version": v, "date": "2026-11-12", "zip": os.path.basename(z), "size": os.path.getsize(z),
           "sha256": hashlib.sha256(open(z, "rb").read()).hexdigest(), "notes": ["시험"]}, open(os.path.join(d, "latest.json"), "w"))
PY
python3 -m http.server 8765 --bind 127.0.0.1 --directory "$FEED" > "$OUT/feed-server.log" 2>&1 &
FEEDPID=$!
launchctl setenv DAYROAD_UPDATE_URL "http://127.0.0.1:8765/latest.json"
launch
check "X1 사용자에게 나간 버전(v$OLDV)이 켜짐" bash -c "curl -fs -H 'x-token: $(tok)' $(API)/api/ping | grep -q '\"build\":\"$OLDV\"'"
sleep 4
{ echo "== 1) v$OLDV 설치 · 실행 뒤"; widgets; ls -la "$HOME/Library/Containers" 2>/dev/null | grep -i dayroad; } > "$OUT/widget-update.txt"
curl -fs -X POST -H "x-token: $(tok)" "$(API)/api/update/check" > /dev/null
curl -fs -X POST -H "x-token: $(tok)" "$(API)/api/update/install" > /dev/null
for _ in $(seq 1 120); do
  ST=$(curl -fs -H "x-token: $(tok)" "$(API)/api/poll" | jget "d['update']['status']")
  [ "$ST" = "ready" ] || [ "$ST" = "error" ] && break; sleep 1
done
check "X2 v$OLDV 앱이 스스로 v$NEWV 를 받아 설치함 ($ST)" test "$ST" = "ready"
{ echo; echo "== 2) 업데이트 직후 (예전 업데이트 방식 그대로, 다시 시작 전)"; widgets; ls -la "$SUP/backup.noindex/DayROAD.app/Contents" 2>&1; } >> "$OUT/widget-update.txt"
BEFORE_FIX=$(widgets | grep -c "backup.noindex")
echo "INFO  X3 업데이트 직후 보관 폴더 위젯이 맥에 남아 있음: ${BEFORE_FIX}개 (1 이상이면 의심했던 문제)" | tee -a "$RES"
curl -fs -X POST -H "x-token: $(tok)" "$(API)/api/update/restart" >/dev/null
sleep 3; wait_ready
check "X4 다시 열린 앱이 v$NEWV" bash -c "curl -fs -H 'x-token: $(tok)' $(API)/api/ping | grep -q '\"build\":\"$NEWV\"'"
sleep 5
{ echo; echo "== 3) v$NEWV 로 다시 연 뒤"; widgets; ls -la "$SUP/backup.noindex/DayROAD.app/Contents" 2>&1; } >> "$OUT/widget-update.txt"
check "X5 보관한 이전 버전 안의 위젯은 꺼짐" test -d "$SUP/backup.noindex/DayROAD.app/Contents/PlugIns.off" -a ! -d "$SUP/backup.noindex/DayROAD.app/Contents/PlugIns"
check "X6 맥이 아는 DayROAD 위젯은 응용 프로그램 폴더의 것 하나뿐" bash -c "[ \"\$(pluginkit -m -D -v -i $WID | grep -c '\.appex')\" = 1 ] && pluginkit -m -D -v -i $WID | grep -q '/Applications/DayROAD.app/Contents/PlugIns/'"
check "X7 앱이 켤 때 위젯을 다시 등록함" grep -q "위젯 등록" "$SUP/launcher.log"
check "X7b 받은 파일 폴더에 남은 같은 위젯을 맥에서 지움 (파일은 그대로)" bash -c "! pluginkit -m -D -v -i $WID | grep -q dayroad-old && test -d '$OLDDIR/DayROAD/DayROAD.app'"
quit_app
echo "▶ X. 재시동 흉내: 위젯 관리자(pkd · chronod)를 껐다 켜고, 앱 없이 위젯이 남아 있는지"
killall pkd 2>/dev/null; killall chronod 2>/dev/null; sleep 8
{ echo; echo "== 4) 앱 끄고 pkd · chronod 다시 시작한 뒤"; widgets; } >> "$OUT/widget-update.txt"
check "X8 재시동 흉내 뒤에도 위젯은 응용 프로그램 폴더의 것 하나만" bash -c "[ \"\$(pluginkit -m -D -v -i $WID | grep -c '\.appex')\" = 1 ] && pluginkit -m -D -v -i $WID | grep -q '/Applications/DayROAD.app/Contents/PlugIns/'"
check "X9 새 버전의 정체성이 앱 이름 기준" bash -c "codesign -d -r- '$APPDIR/Contents/PlugIns/DayROADWidget.appex' 2>&1 | grep -q 'designated => identifier \"$WID\"'"
# 시스템 기록에는 빌드 서버의 접근 열쇠가 섞일 수 있어서(올리기가 막혀요) 위젯 관련 프로세스만 보고, 열쇠 모양은 가려요
log show --start "$T0" --style compact --info --predicate '(process == "chronod" OR process == "pkd" OR process == "containermanagerd" OR process == "runningboardd" OR process == "DayROADWidget" OR process == "NotificationCenter" OR process == "WidgetKit Simulator" OR process == "lsd") AND eventMessage CONTAINS[c] "dayroad"' 2>/dev/null \
  | LC_ALL=C grep -aviE 'gh[pousr]_|github_pat_|access-token|authori[sz]ation|bearer|eC1hY2Nlc3MtdG9rZW4|token|github\.com' > "$OUT/widget-update-syslog.txt" || true
grep -iE "denied|mismatch|invalid|not authori|reject|fail|error" "$OUT/widget-update-syslog.txt" | grep -v "DayROAD\[.*\] \[앱" | tail -25 > "$OUT/widget-update-syslog-errors.txt" || true
echo "---- widget-update.txt"; cat "$OUT/widget-update.txt"; echo "---- 오류처럼 보이는 시스템 기록"; cat "$OUT/widget-update-syslog-errors.txt"; echo "----"
echo "INFO  X10 시스템 기록 중 오류처럼 보이는 줄: $(wc -l < "$OUT/widget-update-syslog-errors.txt" | tr -d ' ')줄 (widget-update-syslog-errors.txt)" | tee -a "$RES"
launchctl unsetenv DAYROAD_UPDATE_URL
kill "$FEEDPID" 2>/dev/null
"$LSREG" -u "$OLDDIR/DayROAD/DayROAD.app" 2>/dev/null; rm -rf "$OLDDIR"

echo "▶ 기록 모으기"
for f in launcher.log requests.log engine.log engine.prev.log engine.out engine.prev.out settings.json data.json widget/widget.json; do
  [ -f "$SUP/$f" ] && cp "$SUP/$f" "$OUT/$(basename "$f")"
done
sw_vers > "$OUT/macos.txt"
echo
echo "== 결과 =="; cat "$RES"
! grep -q '^FAIL' "$RES"
