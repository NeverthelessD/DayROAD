#!/bin/bash
# 맥 빌드 서버에서 돌아요: 빌드 → 실제 맥 시험 → 결과를 ci-results 브랜치에 올림 (실패해도 기록은 올려요)
# Claude 는 빌드 서버 화면을 볼 수 없어서, 결과(빌드 기록 · 시험 결과 · 스크린샷 · 앱 zip)를 저장소로 받아 봐요.
set -uo pipefail
ROOT="$(pwd)"
OUT="$ROOT/ci-out"; rm -rf "$OUT"; mkdir -p "$OUT"
VERSION="$(tr -d ' \n' < VERSION)"
export OUT

{
  echo "commit: ${GITHUB_SHA:-local}  version: $VERSION  started: $(date -u +%FT%TZ)"
  sw_vers; uname -m
} > "$OUT/info.txt"

# Go 가 준비되지 않았으면(설치 단계 실패) Homebrew 로 깔아요
if ! command -v go >/dev/null 2>&1; then
  echo "Go 가 없어서 Homebrew 로 깔아요" >> "$OUT/info.txt"
  brew install go >> "$OUT/info.txt" 2>&1 || true
fi
go version >> "$OUT/info.txt" 2>&1 || echo "Go 없음" >> "$OUT/info.txt"

BUILD=fail; SMOKE=skip
if bash scripts/build-mac.sh > "$OUT/build.log" 2>&1; then
  BUILD=ok
  cp "dist/DayROAD-$VERSION.zip" "$OUT/"
  cp dist/DayROAD.zip "$OUT/DayROAD-first-install.zip"
  shasum -a 256 "$OUT/DayROAD-$VERSION.zip" "$OUT/DayROAD-first-install.zip" > "$OUT/sha256.txt"
  if bash scripts/smoke-mac.sh > "$OUT/smoke.log" 2>&1; then SMOKE=ok; else SMOKE=fail; fi
fi
cp build/xcodebuild.log "$OUT/" 2>/dev/null || true
printf '{"version":"%s","commit":"%s","build":"%s","smoke":"%s"}\n' "$VERSION" "${GITHUB_SHA:-local}" "$BUILD" "$SMOKE" > "$OUT/status.json"
cat "$OUT/status.json"; tail -40 "$OUT/build.log"; [ -f "$OUT/smoke.log" ] && tail -40 "$OUT/smoke.log"

# 올리기 전에 큰 것(시험용으로 푼 앱 · 업데이트 파일 · 엔진 실행 파일)은 빼요
rm -rf "$OUT/feed" "$OUT/sup-before-x/bin" "$OUT/sup-before-x/backup.noindex" "$OUT/sup-before-x/update" 2>/dev/null
find "$OUT" -type f -size +40M -print -delete > "$OUT/removed-big-files.txt" 2>/dev/null
du -sh "$OUT" > "$OUT/size.txt" 2>/dev/null
# 서버 접근 열쇠가 섞인 줄은 통째로 빼요 (올리기가 막히지 않게). 시스템 기록은 원본을 올리지 않아요.
LC_ALL=C grep -rlIiE --exclude='*.zip' --exclude='*.png' --exclude='*.json' 'gh[pousr]_[A-Za-z0-9]|github_pat_|x-access-token|eC1hY2Nlc3MtdG9rZW4|authorization: (basic|bearer)' "$OUT" 2>/dev/null | while read -r f; do
  LC_ALL=C grep -aviE 'gh[pousr]_[A-Za-z0-9]|github_pat_|x-access-token|eC1hY2Nlc3MtdG9rZW4|authorization: (basic|bearer)' "$f" > "$f.clean" || true
  mv "$f.clean" "$f"; echo "열쇠가 섞인 줄을 뺌: ${f#$OUT/}" >> "$OUT/removed-big-files.txt"
done

push_results() {
  git -c user.name="DayROAD build" -c user.email="NeverthelessD@users.noreply.github.com" commit -qm "$1"
  git push -f "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" ci-results > "$ROOT/push.log" 2>&1
}
if [ -n "${GITHUB_TOKEN:-}" ]; then
  cd "$OUT"
  git init -q && git checkout -q -b ci-results
  git add -A
  if ! push_results "v$VERSION build=$BUILD smoke=$SMOKE (${GITHUB_SHA:-local})"; then
    echo "결과 올리기 실패:"; cat "$ROOT/push.log"
    # 작은 것만 다시 올려서, 무엇이 문제였는지라도 볼 수 있게
    SMALL="$ROOT/ci-small"; rm -rf "$SMALL"; mkdir -p "$SMALL"
    for f in status.json info.txt results.txt size.txt removed-big-files.txt; do [ -f "$OUT/$f" ] && cp "$OUT/$f" "$SMALL/"; done
    [ -f "$OUT/smoke.log" ] && tail -200 "$OUT/smoke.log" > "$SMALL/smoke-tail.log"
    [ -f "$OUT/build.log" ] && tail -200 "$OUT/build.log" > "$SMALL/build-tail.log"
    sed 's/x-access-token:[^@]*@/x-access-token:***@/g' "$ROOT/push.log" > "$SMALL/push-error.txt"
    (cd "$OUT" && find . -type f -not -path './.git/*' -exec ls -la {} + | sort -k5 -n -r | head -40) > "$SMALL/biggest-files.txt"
    cd "$SMALL" && git init -q && git checkout -q -b ci-results && git add -A && \
      push_results "v$VERSION build=$BUILD smoke=$SMOKE push=small (${GITHUB_SHA:-local})" || cat "$ROOT/push.log"
  fi
fi
[ "$BUILD" = ok ] && [ "$SMOKE" = ok ]
