#!/bin/bash
# DayROAD 맥 빌드 (맥에서만 돌아요 — 맥 빌드 서버 scripts/ci-mac.sh 가 불러요)
#   Go 엔진(darwin/arm64) + Swift 앱 껍데기 + 위젯 확장(WidgetKit) → dist/DayROAD.app
#   앱과 위젯은 Xcode 로 만들어요 (위젯의 'App Intents' 정보는 Xcode 만 만들 수 있어서). 서명은 임시 서명(ad-hoc, "-").
#   → dist/DayROAD-<버전>.zip (업데이트용) · dist/DayROAD.zip (처음 설치용, 사용 가이드 포함)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="$(tr -d ' \n' < VERSION)"
DIST="$ROOT/dist"
GEN="$ROOT/build/gen"
rm -rf "$DIST" "$ROOT/build" "$ROOT/DayROAD.xcodeproj"
mkdir -p "$DIST" "$GEN/res"

echo "▶ 엔진 테스트 · 빌드 (darwin/arm64, v$VERSION)"
( cd engine && go test ./... )
( cd engine && CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 \
    go build -trimpath -ldflags "-s -w -X main.build=$VERSION" -o "$GEN/res/dayroad-engine" . )
chmod 755 "$GEN/res/dayroad-engine"

echo "▶ 아이콘 (AppIcon.png → AppIcon.icns)"
ICONSET="$ROOT/build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" app/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" app/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$GEN/res/AppIcon.icns"

printf '%s' "$VERSION" > "$GEN/res/version.txt"
sed "s/__VERSION__/$VERSION/g" app/Info.plist > "$GEN/Info.plist"
sed "s/__VERSION__/$VERSION/g" app/Widget-Info.plist > "$GEN/Widget-Info.plist"
plutil -lint "$GEN/Info.plist" "$GEN/Widget-Info.plist"

echo "▶ Xcode 프로젝트 만들기 (XcodeGen)"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate --spec project.yml --project "$ROOT"
xcodebuild -version

echo "▶ 앱 + 위젯 빌드 (xcodebuild)"
set +e
xcodebuild -project DayROAD.xcodeproj -target DayROAD -configuration Release \
  SYMROOT="$ROOT/build/sym" OBJROOT="$ROOT/build/obj" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
  build > "$ROOT/build/xcodebuild.log" 2>&1
XC=$?
set -e
grep -E "error:|warning: .*(DayROAD|Widget)|BUILD (SUCCEEDED|FAILED)" "$ROOT/build/xcodebuild.log" | tail -60 || true
[ $XC -eq 0 ] || { echo "✖ xcodebuild 실패 (build/xcodebuild.log)"; tail -80 "$ROOT/build/xcodebuild.log"; exit 1; }

APP="$DIST/DayROAD.app"
ditto "$ROOT/build/sym/Release/DayROAD.app" "$APP"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▶ 내용 확인"
APPEX="$APP/Contents/PlugIns/DayROADWidget.appex"
test -x "$APP/Contents/MacOS/DayROAD"
test -x "$APP/Contents/Resources/dayroad-engine"
test -f "$APP/Contents/Resources/AppIcon.icns"
test -d "$APPEX" || { echo "✖ 위젯 확장이 앱 안에 없어요"; exit 1; }
[ "$(cat "$APP/Contents/Resources/version.txt")" = "$VERSION" ]
ls -la "$APP/Contents" "$APP/Contents/PlugIns" "$APPEX/Contents/Resources" | sed 's/^/  /'
find "$APPEX" -name "*.appintents*" -o -name "extract.actionsdata" | sed 's/^/  App Intents: /' || true

echo "▶ 다시 서명: 버전이 바뀌어도 맥이 '같은 앱'으로 알아보게 (임시 서명 + 앱 이름 기준 정체성)"
# 임시 서명(ad-hoc)의 기본 정체성은 코드 지문(cdhash)이라, 업데이트할 때마다 맥이 다른 앱으로 봐요
# (캘린더 허락을 다시 묻거나, 위젯 보호 상자 · 바탕화면 위젯이 이어지지 않을 수 있어요). 그래서 정체성을 앱 이름으로 정해요.
codesign --force --sign - --preserve-metadata=entitlements,flags \
  --requirements '=designated => identifier "com.nevertheless-d.dayroad.widget"' "$APPEX"
codesign --force --sign - --preserve-metadata=entitlements,flags \
  --requirements '=designated => identifier "com.nevertheless-d.dayroad"' "$APP"
codesign -d -r- "$APPEX" 2>&1 | sed 's/^/  위젯 /'
codesign -d -r- "$APP" 2>&1 | sed 's/^/  앱 /'
codesign -d -r- "$APP" 2>&1 | grep -q 'designated => identifier "com.nevertheless-d.dayroad"' || { echo "✖ 앱 정체성이 바뀌지 않았어요"; exit 1; }
codesign -d -r- "$APPEX" 2>&1 | grep -q 'designated => identifier "com.nevertheless-d.dayroad.widget"' || { echo "✖ 위젯 정체성이 바뀌지 않았어요"; exit 1; }

echo "▶ 서명 확인 (임시 서명) · 위젯의 보호 상자 권한"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv "$APP" 2>&1 | sed 's/^/  /'
codesign -d --entitlements - "$APPEX" 2>&1 | sed 's/^/  /'
codesign -d --entitlements - "$APPEX" 2>&1 | grep -q "app-sandbox" || { echo "✖ 위젯에 보호 상자 권한이 없어요"; exit 1; }

echo "▶ 압축"
ditto -c -k --norsrc --keepParent "$APP" "$DIST/DayROAD-$VERSION.zip"
mkdir -p "$DIST/first/DayROAD"
ditto "$APP" "$DIST/first/DayROAD/DayROAD.app"
[ -f "docs/DayROAD_사용가이드.png" ] && cp "docs/DayROAD_사용가이드.png" "$DIST/first/DayROAD/"
ditto -c -k --norsrc --keepParent "$DIST/first/DayROAD" "$DIST/DayROAD.zip"

echo "▶ 업데이트 파일을 풀어도 서명이 그대로인지 확인 (앱의 업데이트 기능처럼 unzip)"
CHECK="$DIST/check"; rm -rf "$CHECK"; mkdir -p "$CHECK"
( cd "$CHECK" && unzip -q "$DIST/DayROAD-$VERSION.zip" )
codesign --verify --deep --strict "$CHECK/DayROAD.app"
[ "$(cat "$CHECK/DayROAD.app/Contents/Resources/version.txt")" = "$VERSION" ]
rm -rf "$CHECK"
echo "✔ dist/DayROAD-$VERSION.zip · dist/DayROAD.zip"
