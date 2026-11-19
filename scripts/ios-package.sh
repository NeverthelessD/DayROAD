#!/bin/bash
# 아이폰 설치용 zip: download/DayROAD-iPhone.zip  (빌드 서버가 만든 ios/DayROAD.xcodeproj 를 먼저 넣어 둘 것)
#   DayROAD-iPhone/ DayROAD.xcodeproj · DayROAD/ · Widget/ · Shared/ · Config/ · DayROAD_아이폰_설치.png
# 업데이트를 줄 때는 DayROAD.xcodeproj(사용자가 고른 팀이 저장된 파일)는 빼고 나머지만 바꿔 넣게 안내해요 (ValoROAD 와 같음).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
V="$(tr -d ' \n' < ios/VERSION)"
TMP="$(mktemp -d)"; D="$TMP/DayROAD-iPhone"; mkdir -p "$D"
cp -R ios/DayROAD.xcodeproj ios/DayROAD ios/Widget ios/Shared ios/Config "$D/"
rm -rf "$D/DayROAD.xcodeproj/xcuserdata" "$D/DayROAD.xcodeproj/project.xcworkspace/xcuserdata"
cp docs/DayROAD_아이폰_설치.png "$D/"
echo "$V" > "$D/VERSION"
mkdir -p download
rm -f download/DayROAD-iPhone.zip
(cd "$TMP" && zip -qr -X "$ROOT/download/DayROAD-iPhone.zip" DayROAD-iPhone)
rm -rf "$TMP"
ls -la download/DayROAD-iPhone.zip
