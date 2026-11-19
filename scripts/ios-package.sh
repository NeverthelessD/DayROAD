#!/bin/bash
# 아이폰 설치용 zip: download/DayROAD-iPhone.zip  (빌드 서버가 만든 ios/DayROAD.xcodeproj 를 먼저 넣어 둘 것)
#   scripts/ios-package.sh ["바뀐 점" ...]  → 함께 releases/DayROAD-iPhone-<버전>.zip + releases/latest-ios.json (맥 DayROAD 가 보고 받아 감, engine/iphone.go)
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

# 맥 DayROAD 가 받아 갈 것 (버전마다 이름이 달라서 받는 중에 바뀌지 않아요)
rm -f releases/DayROAD-iPhone-*.zip
cp download/DayROAD-iPhone.zip "releases/DayROAD-iPhone-$V.zip"
python3 - "$V" "releases/DayROAD-iPhone-$V.zip" "$@" <<'PY'
import hashlib, json, os, sys, datetime
v, z, notes = sys.argv[1], sys.argv[2], sys.argv[3:]
json.dump({"version": v, "date": datetime.date.today().isoformat(), "zip": os.path.basename(z),
           "sha256": hashlib.sha256(open(z, "rb").read()).hexdigest(), "size": os.path.getsize(z), "notes": notes},
          open("releases/latest-ios.json", "w"), ensure_ascii=False, indent=2)
PY
cat releases/latest-ios.json

# 업데이트용 (이미 설치한 사람): DayROAD.xcodeproj 는 빼고 나머지 폴더만 → 받은 폴더에 덮어쓰고 ▶
TMP="$(mktemp -d)"; U="$TMP/DayROAD-iPhone-$V-업데이트"; mkdir -p "$U"
cp -R ios/DayROAD ios/Widget ios/Shared ios/Config "$U/"
echo "$V" > "$U/VERSION"
cat > "$U/바꿔 넣는 법.txt" <<TXT
DayROAD 아이폰 $V 업데이트

1. 문서 폴더의 DayROAD-iPhone 폴더를 열어요.
2. 이 폴더 안의 DayROAD · Widget · Shared · Config 폴더와 VERSION 파일을 DayROAD-iPhone 폴더로 끌어다 놓고 '대치'를 눌러요.
   (DayROAD.xcodeproj 는 그대로 둬요 — 고른 팀이 저장돼 있어요)
3. Xcode 에서 DayROAD.xcodeproj 를 열고 ▶ 를 눌러요. 할 일은 iCloud 에 있어서 그대로예요.

made by. Nevertheless_D
TXT
rm -f "download/DayROAD-iPhone-업데이트.zip"
(cd "$TMP" && zip -qr -X "$ROOT/download/DayROAD-iPhone-업데이트.zip" "DayROAD-iPhone-$V-업데이트")
rm -rf "$TMP"
ls -la "download/DayROAD-iPhone-업데이트.zip"
