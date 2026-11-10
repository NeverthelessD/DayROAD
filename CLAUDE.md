# DayROAD — notes for Claude

**Read `PROJECT_NOTES.md` first** (structure, decisions, progress checklist) and update it at the end of every task.
DayROAD is a personal macOS (Apple Silicon, macOS 14+) to-do app (today / this week) with a WidgetKit widget, for **Nevertheless_D**, who is not a programmer.
Talk to them in Korean, in plain words. Never ask them to use Terminal. Never mention GitHub (or the repo name) in anything the user sees.
Same structure as PaperROAD / MSROAD: a real, visible Dock app (Swift shell `app/shell/main.swift`, WKWebView window) with a Go engine (`engine/`)
that runs as the app's child only while the app is open (app → supervisor → engine). Follows macOS 27's "Background App Activity" rule —
never add hidden helpers, nohup engines or SIGTERM-ignoring. The widget is a normal WidgetKit app extension (`app/widget`), sandboxed,
allowed to read/write only `~/Library/Application Support/DayROAD/widget/` (temporary-exception entitlement).

Unlike PaperROAD, the app is built with **Xcode via XcodeGen** (`project.yml`), because the widget's App Intents metadata needs Xcode.
The app can only be built on a Mac: pushing changes under app/, engine/, project.yml or VERSION triggers `.github/workflows/build-mac.yml`,
which builds, ad-hoc signs, runs real-Mac smoke tests and force-pushes results to the `ci-results` branch (read results via git:
`git fetch origin +refs/heads/ci-results:refs/remotes/origin/ci-results`). Release with `scripts/release.sh`.
In tests use `pkill -x`, never `pkill -f dayroad-engine`.

Design was confirmed by the user on 2026-11-10 (Design canvas "DayROAD 디자인 시안", direction A "종이 플래너", icon #2 "할 일 메모지").
Text must wrap only between words (`word-break: keep-all`).
