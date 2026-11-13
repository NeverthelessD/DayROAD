> **이 파일을 읽은 Claude는 작업이 끝날 때마다 이 파일을 업데이트할 것.**
> (구조가 바뀌면 「구조」, 새로 정한 것은 「결정 사항」, 한 일·남은 일은 「진행 사항」에 적고 커밋·푸시까지 할 것)

# DayROAD — 프로젝트 노트

오늘 · 이번 주 할 일 관리 앱 + 바탕화면 위젯. macOS 14 이상 (Apple Silicon). made by. Nevertheless_D
사용자는 개발자가 아니에요. 한국어로 쉽게 설명하고, 터미널 사용을 요구하지 말 것. 결과물은 더블클릭으로 쓸 수 있게.

---

## 진행 사항

작업이 중간에 끊기면 아래 체크리스트에서 **처음으로 체크 안 된 항목부터** 이어서 하면 돼요. 각 단계가 끝날 때마다 커밋 · 푸시.

- [x] 0. 사용자와 기능 정하기 (오늘 · 이번 주 할 일, 위젯, 진행 기록 · 마감, 반복 · 알림 · 넘기기, 분류 추가, iCloud · Google 캘린더 · 아이폰)
- [x] 1. 디자인 시안 (Design 캔버스 'DayROAD 디자인 시안') → 수정 2번 → 2026-11-10 사용자 "확정"
- [x] 2. 저장소 뼈대 (이 파일, CLAUDE.md, VERSION, .gitignore, README)
- [x] 3. 엔진: 할 일 · 분류 저장(data.json + 하루 백업) · 넘기기 · 반복 · 진행 기록 · 위젯 파일 · 업데이트 · 지킴이 · 진단 (go test 통과)
- [x] 4. 화면: 오늘 · 이번 주(끌어 옮기기) · 마감 · 반복 · 언젠가 · 끝낸 일 · 분류 · 자세히 칸 · 설정 · 빠른 추가 글 읽기 (라이트/다크)
- [x] 5. 리눅스에서 Playwright 로 흐름 시험 (맥 연결은 가짜 bridge 로: 캘린더 일정 · 일정 넣기 · 알림 예약 · 미리 알림 보내기/가져오기)
- [x] 6. 맥 껍데기(Swift) + Native.swift(EventKit · 알림) + 위젯(WidgetKit, App Intents) + XcodeGen 프로젝트
- [x] 7. 사용 가이드 이미지 (docs/DayROAD_사용가이드.png)
- [x] 8. 맥 빌드 서버: build=ok · smoke=ok (26/26, macOS 15 · Apple Silicon), 스크린샷 · 위젯 그림이 시안과 같음 확인
- [x] 9. v1.0.0 release.sh → releases/ · download/ · 커밋 · 푸시, '앱 받기' 링크 확인

- [x] 10. v1.1.0 (맥 빌드 서버 26/26 통과 · 내보냄) (사용자 요청 4가지): 하루 · 한 주 · 한 달 단추 + 한 달 화면 · "분류는 ○○," 로 분류(없으면 새로 만듦) · "오후 5시까지" 시간
      · 이름 고치기(두 번 누르기 · ••• 메뉴 '이름 고치기') · 끝낸 일에서 반복하는 일은 한 번만(마지막으로 끝낸 날 · 몇 번 끝냈는지)

- [x] 11. v1.2.0 (맥 빌드 서버 27/27 통과 · M1 창 옮기기 실제 확인 · 내보냄) (사용자 요청 3가지): 자세히 칸 닫기(×는 모든 화면, Esc · 빈 곳 누르기, 고른 할 일이 없으면 칸이 사라짐)
      · 창 옮기기(맨 위 38px 제목 막대: 화면 .dragbar + main.swift DragStrip, 두 번 누르면 맥 설정대로 확대) · 시간 고르기 창(DR.pickTime:
      자주 쓰는 시간 · 오전/오후 · 시 · 분 · 직접 적기 · 시간 없애기) — 할 일 시간 · 알림 · 설정의 아침/마감 알림 시각 · 빠른 추가에서 알아들은 표시를 ×로 빼기

- [x] 12. v1.2.1 위젯이 재시동 뒤 사라지는 문제: ① 업데이트로 보관한 이전 버전 안의 위젯을 끔(PlugIns → PlugIns.off, pluginkit -r,
      되돌리기 때만 다시 켬, 예전 버전이 남긴 보관 앱도 켤 때 정리) ② 임시 서명 + 앱 이름 기준 정체성(--requirements identifier) — 업데이트해도 같은 앱
      ③ 켤 때마다 LSRegisterURL + pluginkit -a/-e use 로 위젯 다시 등록, 맥이 아는 위젯 위치를 launcher.log 에 기록
      ④ smoke X: 사용자에게 나간 버전(download zip)을 깔고, 로컬 업데이트 서버로 진짜 업데이트 → 재시동 흉내(pkd · chronod 다시 시작)
      ⑤ 켤 때 같은 위젯 ID 가 다른 곳(받은 파일 폴더의 압축 푼 앱 등)에도 등록돼 있으면 pluginkit -r + lsregister -u 로 맥에서 지움(파일은 그대로)
      ⑥ 응용 프로그램 폴더 밖(AppTranslocation 포함)에서 열면 옮기기 제안(ditto → xattr -dr quarantine → 다시 열기). 시험은 DAYROAD_NO_MOVE=1 로 끌 수 있음
      ⑦ 빌드 서버: log show 가 서버 접근 열쇠(ghs_)를 담아 결과 올리기가 막혔음 → 프로세스를 좁히고 열쇠 모양은 [가림], ci-mac.sh 도 올리기 전에 가림

- [ ] 13. v1.3.0 (사용자 요청): 남긴 '진행 기록' 고치기 — 기록에 마우스를 올리면 연필(고치기) · ×(지우기), 글을 두 번 눌러도 고치기.
      ↩ 저장 · ⇧↩ 줄바꿈 · esc 취소 · 다른 곳을 누르면 저장, 날짜 · 진행 % 는 그대로 (엔진 /api/task/logedit · Store.EditLog · go test)
      · ⌫ 뒤로 가기(ROAD 앱 공통): 지나온 화면 기록(최대 50), 할 일을 골라 둔 때는 ⌫ = 지우기가 먼저, ⌘[ 도 뒤로 → 맥 빌드 서버 통과 뒤 release.sh

### 다음에 할 수 있는 일
- [ ] 사용자 맥에서 실제로 써 보기: 위젯 갤러리에 보이는지, 캘린더 · 미리 알림 허락, 알림

### 작업 기록
- 2026-11-13 v1.3.0 — 사용자 요청: 기록 남기기로 남긴 글에 오타가 있어도 지우기만 됐음 → 고치기 추가. 같은 날 road-app-skill 에
  '⌫ 뒤로 가기' 공통 규칙이 생겨서 함께 넣음(빠른 추가 · 이름 고치기 등 글 칸에서는 ⌫ 가 원래대로 글자 지우기).
- 2026-11-12 v1.2.1 — 사용자: 재시동하니 DayROAD 위젯만 사라짐. 원인 후보: 업데이트할 때 이전 앱을 backup.noindex 로 옮기는데
  lsregister -u 만 하고 그 안의 위젯 확장(같은 번들 ID)은 pkd 에 남음 → 위젯 둘. 또 임시 서명이라 버전마다 정체성(cdhash)이 달라짐.
  주의: 정체성을 '앱 이름'으로만 정하면, 같은 번들 ID 를 쓰는 다른 임시 서명 앱도 같은 앱으로 보일 수 있어요(개인 앱이라 받아들임).
  진짜 해결은 Apple 개발자 인증서(Developer ID)로 서명하는 것.
  첫 시험(2f59bd2)에서 X6/X8 실패 = 맥이 아는 DayROAD 위젯이 하나가 아님. 사용자도 받은 파일 폴더에 압축 푼 앱이 남아 있을 가능성이 커서
  ⑤ ⑥ 을 더하고, smoke X 는 받은 파일 폴더에 예전 버전을 풀어 등록해 둔 상태에서 시험(X7b).
  확인(405b228): v1.2.0 은 업데이트 직후 맥이 아는 위젯이 '받은 파일 폴더의 것' 하나뿐이고 응용 프로그램 폴더 것이 빠짐 = 사용자 증상.
  v1.2.1 은 켤 때 그것을 지우고 응용 프로그램 폴더 것 하나만 남음, pkd · chronod 다시 시작 뒤에도 그대로. 전부 통과 → 릴리스.
- 2026-11-11 v1.2.0 — 사용자 요청: 오늘 화면에 × 없음 · 창 옮길 곳이 안 보임 · 시간 바꾸기/없애기 표시 없음.
  WKWebView 의 type=time 칸은 맥에서 고르기 창이 없고 지우기 단추도 없어서 직접 만든 시간 고르기 창으로 바꿈.
  WKWebView 는 -webkit-app-region 을 몰라서, 창 옮기기는 Swift 쪽 투명 DragStrip(performDrag)이 맡고 화면은 같은 자리에 제목 막대를 그림.
  smoke M1: CGEvent 로 제목 막대를 끌어 창이 움직이는지 (빌드 서버가 마우스 흉내를 막으면 INFO).
- 2026-11-10 v1.1.0 — 사용자가 실제로 써 보고 요청: ① 보는 범위 넓히기 → 머리에 '하루 · 한 주 · 한 달' 단추(왼쪽 메뉴에도 '이번 달', ⌘3)
  ② 빠른 추가 "분류는 사역," · "분류: 사역" (그냥 '분류'라는 낱말은 건드리지 않게 '는 · 은 · :' 또는 쉼표가 있을 때만) ③ 이름 고치기:
  누를 때 화면을 다시 그려서 브라우저 더블클릭이 안 와요 → 같은 할 일을 450ms 안에 두 번 누르면 직접 고치기 칸으로 ④ 끝낸 일: 반복은 제목+반복+분류로 묶음.
- 2026-11-10 v1.0.0 — 첫 버전. 시안 확정(방향 A 종이 플래너, 아이콘 2번 메모지, 분류 추가 기능 포함) 뒤 제작.
  맥 빌드 서버 첫 실행에서 Xcode(XcodeGen) 빌드 · 26/26 통과. pluginkit 이 위젯을 알아봄, 위젯 체크박스 → 앱 반영 확인,
  `--render-widgets` 로 그린 위젯 그림(라이트 · 다크)이 시안과 같음. 실제 맥 스크린샷에서 분류 단추가 두 줄로 나뉘어 nowrap 으로 고침.
  참고: 빌드 서버 화면이 1024×768 이라 자세히 칸이 서랍으로 보여요(정상). 캘린더 · 미리 알림 · 알림 허락은 빌드 서버에서 시험할 수 없어서
  화면 쪽 동기화 규칙은 리눅스에서 가짜 bridge 로 시험했어요. 임시 서명이라 업데이트 뒤 캘린더 허락을 다시 물을 수 있어요.

## 결정 사항 (확정 디자인)

- 색 (라이트/다크): 종이 #FFFDF8/#1B1F25 · 옆 칸 #F6F2EA/#20252C · 선 #E6DFD2/#2E343D · 글 #1F2A37/#ECE6DA · 흐린 글 #5E6673/#A2A8B2
  · 주홍(강조) #C9502A/#E8703F (글자용 #B4461C/#F2936B, 옅은 바탕 #FBE9E0/#3A2A22) · 끝냄 초록 #3F7D57/#5FA77A · 넘어옴 파랑 #EAF0FA/#2F4F86
- 분류 색 8가지 (palette: blue · orange · purple · green · teal · gold · pink · slate) — engine/store.go 와 css 가 같은 값
- 폰트: 제목 · 날짜 숫자 = 고운바탕 Bold (OFL, 한글 11172자 + 라틴 woff2 432KB) · 본문 = IBM Plex Sans KR (OFL). 위젯은 고운바탕 숫자용 작은 ttf + 맥 기본 글꼴
- 아이콘: 주홍 둥근 네모 + 기울어진 메모지(체크 1개 + 빈 칸 2개) — app/AppIcon.svg → AppIcon.png
- 화면: 왼쪽 메뉴(오늘 · 이번 주 · 마감 다가옴 · 반복하는 일 · 언젠가 · 끝낸 일 · 분류 + 분류 추가 · 캘린더 상태 · 설정 · made by)
  · 가운데(머리 · 7일 띠 · 캘린더 일정 · 빠른 추가 · 넘어옴 알림 · 남은 일 · 끝낸 일) · 오른쪽 자세히 칸(이번 주 화면 · 좁은 창에서는 밀려 나오는 서랍)
- 창: 제목 막대 투명 + 내용이 꽉 차게(fullSizeContentView), 신호등 단추는 왼쪽 메뉴 위에 떠 있음
- 글은 낱말 단위로만 줄바꿈 (`word-break: keep-all`)

## 구조

```
app/shell/main.swift     DayROAD.app 본체(Swift/AppKit): Dock · 메뉴(새 할 일 ⌘N · 설정 ⌘, · 보기 ⌘1~6 · 진단) · WKWebView 창 ·
                         엔진 실행/종료 · Dock 다시 열기 · 업데이트 후 다시 열기(restart-requested → NSWorkspace) · launcher.log
                         Bridge('dayroad') → Native.handle · dayroad:// 주소(위젯 · 알림 누름) → DR.onNative('url') · 창이 앞에 오면 'focus'
                         widget.json 이 바뀌면 WidgetCenter.reloadAllTimelines() · `DayROAD --render-widgets <폴더>` 위젯 그림(시험용)
app/shell/Native.swift   EventKit: 상태 · 허락 · 캘린더 목록 · 일정(여러 날은 날마다) · 일정 넣기/지우기 · 미리 알림 DayROAD 목록 · 보내기/지우기/가져오기
                         알림 센터: 화면이 정한 목록으로 예약 통째로 바꾸기(dr- 접두사, 60개) · 알림을 누르면 dayroad://task/<id>
app/shared/WidgetData.swift   widget.json 모델 · 진짜 홈 경로(getpwuid) · 위젯 체크박스 기록(actions.jsonl) · 앱이 꺼진 채 날짜가 바뀌었을 때의 '오늘'(WToday.make)
app/shared/WidgetViews.swift  위젯 화면(작게 · 중간 · 크게) — 위젯과 앱(그림 만들기)이 같이 씀
app/widget/DayROADWidget.swift WidgetBundle · TimelineProvider(자정 · 15분) · ToggleTaskIntent(App Intent, 위젯 체크박스)
app/Info.plist · Widget-Info.plist · Widget.entitlements(샌드박스 + Support/DayROAD/widget/ 읽기쓰기) · AppIcon.svg/png · fonts/
project.yml              XcodeGen: DayROAD(앱) + DayROADWidget(app-extension, 앱 안 PlugIns 에 들어감). 서명 "-"(ad-hoc)
engine/main.go           설정(settings.json) · 라우트 · 127.0.0.1:47951 + 토큰
engine/store.go          할 일 · 분류 · 넘기기(rollover) · 반복(nextOccurrence, 끝내면 다음 차례 생성/되돌리면 지움) · 진행 기록 · 가져오기 · /api/*
engine/widget.go         Support/widget/widget.json 쓰기 (오늘 · 이번 주 · 앞으로 8일 · 넘기기 설정) · actions.jsonl 2초마다 반영
engine/supervise.go · update.go · diag.go   PaperROAD 와 같음 (이름만 DayROAD)
engine/web/              index.html · css/app.css · js/core.js(요청 · 상태 · 날짜 · 떠 있는 창) · parse.js(빠른 추가 글 읽기)
                         · views.js(화면들: 하루 · 한 주 · 한 달 · 목록) · detail.js(자세히 칸) · settings.js(설정 · 업데이트 · 분류 관리) · sync.js(캘린더 · 미리 알림 · 알림) · main.js
scripts/build-mac.sh     (맥 전용) Go 엔진 → 아이콘 → XcodeGen → xcodebuild → 확인(위젯 · 샌드박스) → zip 2개
scripts/smoke-mac.sh     (맥 전용) 켜기 · 자식 관계 · 할 일 API · 위젯(파일 · pluginkit · 체크박스 반영 · 그림) · 스크린샷 4장 · dayroad:// · 다시 열기 · 고장 복구 · ⌘Q · 종료 · 강제 종료 · 업데이트 재실행
scripts/ci-mac.sh · release.sh · publish-download.sh · feed.py · guide.py   PaperROAD 와 같음
```
엔진 실행 사슬: DayROAD.app(Swift, Dock) → dayroad-engine(지킴이) → dayroad-engine(엔진). 위젯은 맥이 따로 띄워요(엔진 없이 파일만).
기록: ~/Library/Application Support/DayROAD/{launcher.log, requests.log, engine.log, data.json, settings.json, backups/, widget/}

### 동기화 규칙 (sync.js)
- 엔진에서 새 상태를 받을 때마다 바뀐 할 일만: 캘린더(calendar=true 인 날짜 할 일 → 일정, 끄면 지움) · 미리 알림(남은 일은 보내고, 끝냄도 맞춤)
- 미리 알림 가져오기: 켤 때 · 창이 앞에 올 때 · 2분마다. 아이폰에서 끝낸 것 → /api/sync/done, 새로 적은 것 → /api/import
- 알림: 앞으로 8일의 할 일 알림 · 아침 알림 · 마감 미리 알림을 계산해서 통째로 다시 예약

### 리눅스에서 시험하는 법
```
cd engine && go test ./... && go build -o /tmp/dr-engine .
DAYROAD_SUPPORT=/tmp/drsup DAYROAD_TOKEN=tok DAYROAD_PORT=47951 DAYROAD_UPDATE_URL=http://127.0.0.1:1/x /tmp/dr-engine
```
→ Playwright 로 `http://127.0.0.1:47951/?t=tok`. 맥 연결은 `window.webkit.messageHandlers.dayroad.postMessage` 를 가짜로 만들어 시험해요.
날짜를 바꿔 보려면 `DAYROAD_TODAY=2026-11-11`.
