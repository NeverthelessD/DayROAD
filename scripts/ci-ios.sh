#!/bin/bash
# 맥 빌드 서버에서 돌아요 (.github/workflows/build-ios.yml):
#  1) ios/project.yml → DayROAD.xcodeproj (XcodeGen)  2) 시뮬레이터용 · 실제 아이폰용(서명 없이) 빌드 + 위젯 없는 판
#  3) 시뮬레이터에서 시험 모드로 화면 찍기 · 규칙 시험 · iCloud 맞추기 시험(가짜 iCloud 폴더) · 위젯 그림
#  4) 결과(+ 만들어진 DayROAD.xcodeproj)를 ci-results-ios 브랜치에 올림 (실패해도 기록은 올려요)
set -uo pipefail
ROOT="$(pwd)"
OUT="$ROOT/ci-out-ios"; rm -rf "$OUT"; mkdir -p "$OUT/shots"
VERSION="$(tr -d ' \n' < ios/VERSION)"
BUNDLE="com.neverthelessd.dayroad.iphone"
GROUP="group.com.neverthelessd.dayroad.iphone"
DD="$ROOT/build/dd"
: > "$OUT/results.txt"
pass() { echo "PASS  $*" | tee -a "$OUT/results.txt"; }
fail() { echo "FAIL  $*" | tee -a "$OUT/results.txt"; }
info() { echo "INFO  $*" | tee -a "$OUT/results.txt"; }

{
  echo "commit: ${GITHUB_SHA:-local}  ios version: $VERSION  started: $(date -u +%FT%TZ)"
  sw_vers; uname -m; xcodebuild -version
} > "$OUT/info.txt" 2>&1

# 맥 위젯 화면 파일과 아이폰 복사본이 같은지 (2번째 줄 설명만 달라요)
if diff <(sed '2d' ios/Shared/WidgetViews.swift) app/shared/WidgetViews.swift > /dev/null; then pass "위젯 화면 파일이 맥과 같음"; else fail "위젯 화면 파일이 맥과 다름 (ios/Shared/WidgetViews.swift 를 다시 복사)"; fi
grep -q "MARKETING_VERSION: \"$VERSION\"" ios/project.yml && [ "$(grep -c "<string>$VERSION</string>" ios/Config/App-Info.plist ios/Config/Widget-Info.plist | grep -c ':1')" = 2 ] && pass "버전 $VERSION" || fail "버전이 ios/VERSION · project.yml · Config/*-Info.plist 에서 달라요"

command -v xcodegen >/dev/null || brew install xcodegen > "$OUT/brew.log" 2>&1
(cd ios && xcodegen generate --spec project.yml) > "$OUT/xcodegen.log" 2>&1 && pass "XcodeGen 프로젝트" || fail "XcodeGen 프로젝트"
PROJ="ios/DayROAD.xcodeproj"

SIM=fail; DEVICE=fail; LITE=fail; SHOTS=skip
if xcodebuild -project "$PROJ" -scheme DayROAD -configuration Debug -sdk iphonesimulator \
     -destination "generic/platform=iOS Simulator" -derivedDataPath "$DD" CODE_SIGNING_ALLOWED=NO build \
     > "$OUT/build-sim.log" 2>&1; then SIM=ok; fi
grep -E "error:|warning: " "$OUT/build-sim.log" | grep -v "appintentsmetadataprocessor" | sort -u | head -120 > "$OUT/build-sim-errors.txt"

if xcodebuild -project "$PROJ" -scheme DayROAD -configuration Release -sdk iphoneos \
     -destination "generic/platform=iOS" -derivedDataPath "$DD-dev" CODE_SIGNING_ALLOWED=NO build \
     > "$OUT/build-device.log" 2>&1; then DEVICE=ok; fi
grep -E "error:" "$OUT/build-device.log" | sort -u | head -60 > "$OUT/build-device-errors.txt"

if xcodebuild -project "$PROJ" -scheme DayROAD-NoWidget -configuration Release -sdk iphoneos \
     -destination "generic/platform=iOS" -derivedDataPath "$DD-lite" CODE_SIGNING_ALLOWED=NO build \
     > "$OUT/build-lite.log" 2>&1; then LITE=ok; fi
grep -E "error:" "$OUT/build-lite.log" | sort -u | head -40 > "$OUT/build-lite-errors.txt"
[ "$SIM" = ok ] && pass "시뮬레이터용 빌드" || fail "시뮬레이터용 빌드"
[ "$DEVICE" = ok ] && pass "실제 아이폰용 빌드 (앱 + 위젯)" || fail "실제 아이폰용 빌드 (앱 + 위젯)"
[ "$LITE" = ok ] && pass "실제 아이폰용 빌드 (위젯 없는 판)" || fail "실제 아이폰용 빌드 (위젯 없는 판)"

if [ "$DEVICE" = ok ]; then
  DAPP="$(find "$DD-dev/Build/Products" -maxdepth 2 -name 'DayROAD.app' | head -1)"
  [ -d "$DAPP/PlugIns/DayROADWidget.appex" ] && pass "위젯이 앱 안에 들어 있음" || fail "위젯이 앱 안에 없음"
  du -sh "$DAPP" > "$OUT/app-size.txt" 2>&1
fi

if [ "$SIM" = ok ]; then
  SHOTS=fail
  APP="$(find "$DD/Build/Products" -maxdepth 2 -name 'DayROAD.app' -path '*iphonesimulator*' | head -1)"
  echo "app: $APP" >> "$OUT/info.txt"
  UDID="$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
best=None
for rt,devs in d.items():
    if "iOS" not in rt: continue
    for x in devs:
        n=x["name"]
        if not n.startswith("iPhone"): continue
        score=(rt, ("Pro" in n and "Max" not in n), n)
        if best is None or score>best[0]: best=(score,x["udid"],n,rt)
print(best[1] if best else "")
print(best[2]+" / "+best[3] if best else "", file=sys.stderr)
' 2>>"$OUT/info.txt")"
  if [ -n "$UDID" ]; then
    xcrun simctl boot "$UDID" 2>/dev/null
    xcrun simctl bootstatus "$UDID" -b > /dev/null 2>&1
    xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 2>/dev/null
    xcrun simctl install "$UDID" "$APP" >> "$OUT/info.txt" 2>&1
    xcrun simctl privacy "$UDID" grant notifications "$BUNDLE" > /dev/null 2>&1
    xcrun simctl privacy "$UDID" grant calendar "$BUNDLE" > /dev/null 2>&1
    shot() { # 이름 · 기다릴 초 · 화면 모드 · 실행 인자…
      local name="$1" wait="$2" mode="$3"; shift 3
      xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1
      xcrun simctl ui "$UDID" appearance "$mode" > /dev/null 2>&1
      xcrun simctl launch "$UDID" "$BUNDLE" -demo "$@" >> "$OUT/launch.txt" 2>&1
      sleep "$wait"
      xcrun simctl io "$UDID" screenshot "$OUT/shots/$name.png" > /dev/null 2>&1 && pass "화면 $name" || fail "화면 $name"
    }
    shot 01-today-light 25 light -fresh -selftest -renderWidgets -tab today
    DATA="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data 2>/dev/null)"
    DOCS="$DATA/Documents"
    cp "$DOCS/selftest.txt" "$OUT/selftest.txt" 2>/dev/null
    if [ -s "$OUT/selftest.txt" ]; then
      cat "$OUT/selftest.txt" | sed 's/^/  규칙 /' >> "$OUT/results.txt"
      grep -q '^FAIL' "$OUT/selftest.txt" && fail "규칙 시험 (selftest.txt)" || pass "규칙 시험 $(grep -c '^PASS' "$OUT/selftest.txt")개"
    else
      fail "규칙 시험 결과가 없어요"
    fi
    cp "$DOCS"/widgets-*.png "$OUT/shots/" 2>/dev/null && pass "위젯 그림" || fail "위젯 그림"
    shot 02-today-dark 10 dark -tab today
    shot 03-detail 12 light -tab today -detail
    shot 04-week 10 light -tab week
    shot 05-month 10 light -tab month
    shot 06-lists 10 light -tab lists
    shot 07-settings 10 light -tab settings
    shot 08-settings-dark 10 dark -tab settings

    # 맞추기 1: 맥이 iCloud 파일에 할 일을 더한 것처럼 → 앱에 들어오는지
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1
    xcrun simctl ui "$UDID" appearance light > /dev/null 2>&1
    xcrun simctl launch "$UDID" "$BUNDLE" -demo -tab today >> "$OUT/launch.txt" 2>&1
    sleep 12
    CF="$DOCS/DemoCloud/DayROAD/data.json"
    cp "$CF" "$OUT/cloud-before.json" 2>/dev/null
    python3 - "$CF" <<'PY'
import json, sys, time, os
p = sys.argv[1]; d = json.load(open(p)); now = int(time.time() * 1000) + 50
d['tasks'].append({"id": "mac1", "title": "맥에서 적은 할 일", "note": "", "bucket": "day", "date": time.strftime('%Y-%m-%d'), "weekOf": "", "time": "08:00",
  "cat": "work", "star": False, "done": False, "doneAt": "", "due": "", "alarm": "", "repeat": "", "progress": 0, "log": [], "carriedFrom": "",
  "calendar": False, "eventId": "", "reminderId": "", "nextId": "", "order": now, "created": now, "updated": now})
d['deleted'] = d.get('deleted') or {}
d['deleted']['demo10'] = now   # 맥에서 '대청소'를 지운 것처럼
open(p + '.w', 'w').write(json.dumps(d, ensure_ascii=False)); os.replace(p + '.w', p)
PY
    LOCAL="$DATA/Library/Application Support/DayROAD/data.json"
    GOT=no; for _ in $(seq 1 40); do
      python3 -c "import json,sys;d=json.load(open(sys.argv[1]));ids=[t['id'] for t in d['tasks']];assert 'mac1' in ids and 'demo10' not in ids" "$LOCAL" 2>/dev/null && { GOT=yes; break; }; sleep 0.5; done
    [ "$GOT" = yes ] && pass "맥이 iCloud 에 적은 할 일 · 지운 할 일이 20초 안에 아이폰에 반영" || fail "맥이 바꾼 것이 아이폰에 반영되지 않음"
    sleep 2; xcrun simctl io "$UDID" screenshot "$OUT/shots/09-sync-from-mac.png" > /dev/null 2>&1

    # 맞추기 2: 아이폰에서 끝내면(-toggleFirst: '디자인 시안 피드백 보내기') iCloud 파일에도
    xcrun simctl terminate "$UDID" "$BUNDLE" > /dev/null 2>&1
    xcrun simctl launch "$UDID" "$BUNDLE" -demo -tab today -toggleFirst >> "$OUT/launch.txt" 2>&1
    OK2=no; for _ in $(seq 1 40); do
      python3 -c "import json,sys;d=json.load(open(sys.argv[1]));t=[x for x in d['tasks'] if x['id']=='demo3'][0];assert t['done'] and t['updated']>0;assert any(x['id']=='mac1' for x in d['tasks'])" "$CF" 2>/dev/null && { OK2=yes; break; }; sleep 0.5; done
    [ "$OK2" = yes ] && pass "아이폰에서 끝낸 것이 iCloud 파일에 들어감 (맥 것도 그대로)" || fail "아이폰에서 바꾼 것이 iCloud 파일에 안 들어감"
    cp "$CF" "$OUT/cloud-after.json" 2>/dev/null
    # 같은 내용이면 다시 쓰지 않아요 (맥과 서로 계속 다시 쓰지 않게)
    sleep 3; M1=$(stat -f %m "$CF"); sleep 14; M2=$(stat -f %m "$CF")
    [ "$M1" = "$M2" ] && pass "바뀐 게 없으면 iCloud 파일을 다시 쓰지 않음" || fail "바뀐 게 없는데 iCloud 파일을 계속 다시 씀"
    python3 -c "import json,sys;json.load(open(sys.argv[1]))['tasks'][0]['repeat']" "$CF" 2>/dev/null && pass "iCloud 파일이 맥이 읽는 모양(repeat 칸 등)" || fail "iCloud 파일 모양이 맥과 다름"

    GC="$(xcrun simctl get_app_container "$UDID" "$BUNDLE" "$GROUP" 2>/dev/null)"
    if [ -n "$GC" ] && [ -s "$GC/widget/widget.json" ]; then pass "위젯 자료(widget.json)를 앱 그룹 폴더에 씀"; cp "$GC/widget/widget.json" "$OUT/widget.json"; else info "시뮬레이터(서명 없음)에서는 앱 그룹 폴더가 없어 위젯 자료 확인을 건너뜀"; fi

    cp "$DATA/Library/Application Support/DayROAD/log.txt" "$OUT/app-log.txt" 2>/dev/null
    # 처음 켤 때 화면 (폴더 연결 전)
    xcrun simctl uninstall "$UDID" "$BUNDLE" > /dev/null 2>&1
    xcrun simctl install "$UDID" "$APP" >> "$OUT/info.txt" 2>&1
    shot 10-connect 10 light -connect

    xcrun simctl spawn "$UDID" log show --last 8m --style compact --predicate 'process == "DayROAD" AND messageType >= 16' 2>/dev/null | tail -200 > "$OUT/sim-errors.txt"
    N=$(ls "$OUT/shots" | wc -l | tr -d ' ')
    [ "$N" -ge 11 ] && SHOTS=ok
  else
    fail "아이폰 시뮬레이터를 찾지 못했어요"
  fi
fi

# 사용자에게 줄 프로젝트 파일
if [ -d "$PROJ" ]; then (cd ios && zip -qr "$OUT/DayROAD.xcodeproj.zip" DayROAD.xcodeproj); fi
grep -q '^FAIL' "$OUT/results.txt" && TESTS=fail || TESTS=ok
printf '{"version":"%s","commit":"%s","sim":"%s","device":"%s","lite":"%s","shots":"%s","tests":"%s"}\n' "$VERSION" "${GITHUB_SHA:-local}" "$SIM" "$DEVICE" "$LITE" "$SHOTS" "$TESTS" > "$OUT/status.json"
cat "$OUT/status.json"; cat "$OUT/results.txt"; head -60 "$OUT/build-sim-errors.txt"

if [ -n "${GITHUB_TOKEN:-}" ]; then
  cd "$OUT"
  git init -q && git checkout -q -b ci-results-ios
  git add -A
  git -c user.name="DayROAD build" -c user.email="NeverthelessD@users.noreply.github.com" commit -qm "ios v$VERSION sim=$SIM device=$DEVICE tests=$TESTS (${GITHUB_SHA:-local})"
  git push -qf "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" ci-results-ios
fi
[ "$SIM" = ok ] && [ "$DEVICE" = ok ]
