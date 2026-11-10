// DayROAD — Dock 에 보이는 맥 앱 껍데기
// made by. Nevertheless_D
//
// 왜 이 껍데기가 있나요?
//   macOS 27 의 '백그라운드 앱 활동' 규칙: 앱을 종료한 뒤에도 창·메뉴 막대·Dock 없이 남아 도는 프로그램은
//   사용자에게 보여 주고, 허용되지 않으면 시스템이 끕니다. 예외는 '그 프로그램을 켠 앱이 Dock 에 있을 때'예요.
//   그래서 DayROAD 는 Dock 에 보이는 정식 앱이고, 엔진은 이 앱의 자식으로 '앱이 켜져 있는 동안만' 돌아요.
//   규칙을 피해 가는 장치(종료 신호 무시, 몰래 도는 도우미 앱)는 쓰지 않아요. (PaperROAD · MSROAD 와 같은 구조)
//   위젯은 맥이 따로 띄우는 정식 확장(PlugIns/DayROADWidget.appex)이에요 — 엔진을 켜지 않고 파일만 읽어요.
//
// 하는 일
//   1) 앱 안의 엔진을 ~/Library/Application Support/DayROAD/bin 으로 복사 (업데이트로 앱 묶음이 바뀌어도 안전하게)
//   2) 엔진(지킴이 모드)을 자식으로 켜고, 127.0.0.1:47951 + 토큰 주소를 앱 창(WKWebView)에 띄움
//   3) Dock 아이콘을 누르면 창을 다시 보여 주고, 앱을 종료하면 엔진도 깔끔하게 끔
//   4) 엔진이 끝나면 앱도 끝남 (화면의 '종료') · 업데이트 후에는 새 버전을 다시 엶
//   5) 모든 단계를 launcher.log 에 기록
//   6) 캘린더 · 미리 알림 · 알림 (Native.swift) · 위젯 새로 그리기 · dayroad:// 주소(위젯 · 알림을 눌렀을 때)

import AppKit
import Darwin
import SwiftUI
import WebKit
import WidgetKit

// MARK: - 경로 · 기록

enum Paths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("DayROAD", isDirectory: true)
    }()
    static let bin = support.appendingPathComponent("bin", isDirectory: true)
    static let engine = bin.appendingPathComponent("dayroad-engine")
    static func file(_ name: String) -> URL { support.appendingPathComponent(name) }
}

enum Log {
    static func write(_ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        let url = Paths.file("launcher.log")
        if let attrs = try? fm.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber, size.intValue > 262_144 {
            let prev = Paths.file("launcher.prev.log")
            try? fm.removeItem(at: prev)
            try? fm.moveItem(at: url, to: prev)
        }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "MM-dd HH:mm:ss"
        let line = "\(df.string(from: Date())) [앱 \(getpid())] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - 엔진

final class Engine {
    var process: Process?
    var port: Int = 0
    var token: String = ""
    let build: String
    var onExit: ((Int32, Bool) -> Void)?

    init() {
        let v = Bundle.main.url(forResource: "version", withExtension: "txt")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "0.0.0"
        build = v.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func readText(_ name: String) -> String? {
        guard let s = try? String(contentsOf: Paths.file(name), encoding: .utf8) else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// 앱 안의 엔진을 앱 전용 폴더로 복사해요 (버전이 바뀌었을 때만)
    func prepare() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: Paths.bin, withIntermediateDirectories: true)
        let buildFile = Paths.bin.appendingPathComponent("build")
        let installed = (try? String(contentsOf: buildFile, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let want = build + "-native"
        if installed != want || !fm.isExecutableFile(atPath: Paths.engine.path) {
            guard let src = Bundle.main.url(forResource: "dayroad-engine", withExtension: nil) else {
                throw NSError(domain: "DayROAD", code: 1, userInfo: [NSLocalizedDescriptionKey: "앱 안에서 엔진을 찾지 못했어요"])
            }
            let tmp = Paths.bin.appendingPathComponent("dayroad-engine.new")
            try? fm.removeItem(at: tmp)
            try fm.copyItem(at: src, to: tmp)
            chmod(tmp.path, 0o755)
            removexattr(tmp.path, "com.apple.quarantine", 0)
            if rename(tmp.path, Paths.engine.path) != 0 {
                throw NSError(domain: "DayROAD", code: 2, userInfo: [NSLocalizedDescriptionKey: "엔진을 준비하지 못했어요"])
            }
            try want.write(to: buildFile, atomically: true, encoding: .utf8)
            Log.write("엔진 준비 (v\(build))")
        }
        removexattr(Paths.engine.path, "com.apple.quarantine", 0)
    }

    /// 127.0.0.1 엔진에 짧게 요청해요 (응답이 200 이면 내용을 돌려줘요)
    func request(_ method: String, port: Int, path: String, token: String, timeout: TimeInterval) -> Data? {
        guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "x-token")
        if method == "POST" {
            req.httpBody = "{}".data(using: .utf8)
            req.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        let task = URLSession.shared.dataTask(with: req) { data, resp, _ in
            if let h = resp as? HTTPURLResponse, h.statusCode == 200 { out = data ?? Data() }
            sem.signal()
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 0.5) == .timedOut { task.cancel() }
        return out
    }

    /// 이미 켜져 있는 엔진(예전 버전 포함)이 있으면 끄고 새로 켜요
    func stopExisting() {
        guard let p = readText("port").flatMap({ Int($0) }), let t = readText("token") else { return }
        guard request("GET", port: p, path: "/api/ping", token: t, timeout: 1) != nil else { return }
        Log.write("이미 켜져 있던 엔진(포트 \(p))을 끄고 새로 켜요")
        _ = request("POST", port: p, path: "/api/quit", token: t, timeout: 2)
        for _ in 0..<40 {
            if request("GET", port: p, path: "/api/ping", token: t, timeout: 0.5) == nil { break }
            usleep(150_000)
        }
    }

    func start() throws {
        let fm = FileManager.default
        token = readText("token") ?? Engine.randomToken()
        try? fm.removeItem(at: Paths.file("port"))
        try? fm.removeItem(at: Paths.file("restart-requested"))

        let p = Process()
        p.executableURL = Paths.engine
        var env = ProcessInfo.processInfo.environment
        for k in ["DAYROAD_RESTART", "DAYROAD_PORT", "DAYROAD_CHILD"] { env.removeValue(forKey: k) }
        env["DAYROAD_SUPERVISOR"] = "1"
        env["DAYROAD_SHELL"] = "native"
        env["DAYROAD_VIA"] = "native"
        env["DAYROAD_TOKEN"] = token
        env["DAYROAD_SUPPORT"] = Paths.support.path
        env["DAYROAD_APP"] = Bundle.main.bundlePath
        env["DAYROAD_PARENT_PID"] = String(getpid())
        env["DAYROAD_PORT_WAIT"] = "1"
        p.environment = env
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { self?.exited(code) }
        }
        try p.run()
        process = p
        Log.write("엔진 켬 (지킴이 pid \(p.processIdentifier))")
    }

    func waitForPort() -> Int? {
        for _ in 0..<100 {
            if let v = readText("port").flatMap({ Int($0) }) {
                port = v
                return v
            }
            usleep(150_000)
        }
        return nil
    }

    private func exited(_ code: Int32) {
        let restart = FileManager.default.fileExists(atPath: Paths.file("restart-requested").path)
        process = nil
        onExit?(code, restart)
    }

    /// 앱을 종료할 때: 엔진에게 정중히 끄라고 하고, 안 꺼지면 종료 신호를 보내요
    func stop(completion: @escaping () -> Void) {
        guard let p = process, p.isRunning else { completion(); return }
        let port = self.port, token = self.token
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.request("POST", port: port, path: "/api/quit", token: token, timeout: 2)
            for _ in 0..<30 where p.isRunning { usleep(100_000) }
            if p.isRunning {
                p.terminate()
                for _ in 0..<20 where p.isRunning { usleep(100_000) }
            }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
            DispatchQueue.main.async { completion() }
        }
    }

    static func randomToken() -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<32).map { _ in chars[Int(arc4random_uniform(UInt32(chars.count)))] })
    }
}

// MARK: - 화면(app.js)에서 오는 부탁: window.webkit.messageHandlers.dayroad.postMessage({type, …})

final class Bridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var app: AppDelegate?
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.securityOrigin.host == "127.0.0.1",
              let body = message.body as? [String: Any], let type = body["type"] as? String, let app = app else {
            replyHandler(nil, "허용되지 않은 요청이에요")
            return
        }
        switch type {
        case "appearance":
            app.setAppearance(body["value"] as? String ?? "system")
            replyHandler(["ok": true], nil)
        case "openDiag":
            app.openDiag()
            replyHandler(["ok": true], nil)
        default:
            app.native.handle(type, body, reply: replyHandler)
        }
    }
}

// MARK: - 앱

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    let engine = Engine()
    let native = Native()
    var quitting = false
    var pageURL: URL?
    var pageReady = false
    var pendingURL: URL?
    var widgetStamp: Date?
    var focusWork: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("시작 v\(engine.build) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(Bundle.main.bundlePath)")
        buildMenu()
        makeWindow()
        showLoading()
        native.onOpenURL = { [weak self] u in self?.openURL(u) }
        native.onStoreChanged = { [weak self] in self?.notifyFocus(delay: 1.0) }
        engine.onExit = { [weak self] code, restart in self?.engineExited(code: code, restart: restart) }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.notifyFocus(delay: 0.3)
        }
        // 엔진이 위젯 파일을 새로 쓰면 위젯을 바로 다시 그려요
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in self?.checkWidgetFile() }
        boot()
    }

    func boot() {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.engine.prepare()
                self.engine.stopExisting()
                try self.engine.start()
                guard let port = self.engine.waitForPort() else {
                    throw NSError(domain: "DayROAD", code: 3, userInfo: [NSLocalizedDescriptionKey: "엔진이 준비되지 않았어요"])
                }
                Log.write("엔진 준비됨 (포트 \(port))")
                DispatchQueue.main.async { self.loadApp(port: port) }
            } catch {
                Log.write("⚠️ 시작 실패: \(error.localizedDescription)")
                DispatchQueue.main.async { self.startFailed(error) }
            }
        }
    }

    func loadApp(port: Int) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/?t=\(engine.token)") else { return }
        pageURL = url
        pageReady = false
        web.load(URLRequest(url: url))
    }

    func startFailed(_ error: Error) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = "DayROAD를 시작하지 못했어요"
        a.informativeText = "\(error.localizedDescription)\n앱을 다시 실행해 보세요. 계속 안 되면 맥을 재시동한 뒤 시도해 주세요."
        a.addButton(withTitle: "다시 시도")
        a.addButton(withTitle: "종료")
        if a.runModal() == .alertFirstButtonReturn {
            boot()
        } else {
            quitting = true
            NSApp.terminate(nil)
        }
    }

    func engineExited(code: Int32, restart: Bool) {
        if quitting { return }
        if restart {
            relaunch()
            return
        }
        Log.write("엔진이 끝나서 앱도 닫아요 (코드 \(code))")
        quitting = true
        NSApp.terminate(nil)
    }

    /// 업데이트된 새 버전을 macOS 정식 방법(LaunchServices)으로 다시 열고, 지금 앱은 끝내요
    func relaunch() {
        Log.write("새 버전으로 다시 열어요")
        quitting = true
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = true
        var env = ProcessInfo.processInfo.environment
        env.removeValue(forKey: "DAYROAD_RESTART")
        env["DAYROAD_RELAUNCHED"] = "1"
        cfg.environment = env
        NSWorkspace.shared.openApplication(at: appURL, configuration: cfg) { _, error in
            if let error = error { Log.write("⚠️ 다시 열지 못했어요: \(error.localizedDescription)") }
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // 위젯 · 알림을 누르면 dayroad://today · dayroad://week · dayroad://task/<id> 로 열려요
    func application(_ application: NSApplication, open urls: [URL]) {
        for u in urls where u.scheme == "dayroad" { openURL(u) }
    }

    func openURL(_ u: URL) {
        Log.write("주소로 열기: \(u.absoluteString)")
        showMain()
        if pageReady {
            callJS("url", ["url": u.absoluteString])
        } else {
            pendingURL = u
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMain() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard engine.process != nil else { return .terminateNow }
        quitting = true
        Log.write("종료: 엔진을 끄는 중")
        engine.stop {
            Log.write("종료 완료")
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: 화면에 알리기

    /// window.DR.onNative(name, data) 를 불러요 (화면이 아직 준비 안 됐으면 조용히 넘어가요)
    func callJS(_ name: String, _ data: [String: Any]) {
        guard pageReady,
              let json = try? JSONSerialization.data(withJSONObject: data),
              let s = String(data: json, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.DR && window.DR.onNative && window.DR.onNative(\"\(name)\", \(s))", completionHandler: nil)
    }

    func notifyFocus(delay: TimeInterval) {
        focusWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.callJS("focus", [:]) }
        focusWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    func checkWidgetFile() {
        let attrs = try? FileManager.default.attributesOfItem(atPath: WidgetFiles.data.path)
        guard let m = attrs?[.modificationDate] as? Date else { return }
        if widgetStamp != m {
            if widgetStamp != nil { WidgetCenter.shared.reloadAllTimelines() }
            widgetStamp = m
        }
    }

    // MARK: 창

    static let sideColor = NSColor(name: nil) { ap in
        ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x20 / 255, green: 0x25 / 255, blue: 0x2C / 255, alpha: 1)
            : NSColor(srgbRed: 0xF6 / 255, green: 0xF2 / 255, blue: 0xEA / 255, alpha: 1)
    }

    func makeWindow() {
        let cfg = WKWebViewConfiguration()
        cfg.applicationNameForUserAgent = "DayROADShell/\(engine.build)"
        let bridge = Bridge()
        bridge.app = self
        cfg.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "dayroad")
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 820), configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsMagnification = false
        if #available(macOS 13.3, *) { web.isInspectable = true }

        // 제목 막대를 투명하게 해서 화면과 하나로 보이게 해요. 신호등 단추는 왼쪽 메뉴 위에 떠 있어요.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "DayROAD"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = AppDelegate.sideColor
        window.minSize = NSSize(width: 900, height: 600)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        window.contentView = web
        if !window.setFrameUsingName("DayROADMain") { window.center() }
        window.setFrameAutosaveName("DayROADMain")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func setAppearance(_ v: String) {
        switch v {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func showLoading() {
        let html = """
        <!doctype html><meta charset="utf-8"><style>
        :root{color-scheme:light dark}
        body{margin:0;height:100vh;display:grid;place-items:center;font:600 14px -apple-system,"Apple SD Gothic Neo",sans-serif;
             background:#FFFDF8;color:#5E6673}
        @media (prefers-color-scheme: dark){body{background:#1B1F25;color:#A2A8B2}}
        .w{display:flex;flex-direction:column;align-items:center;gap:14px}
        .s{width:22px;height:22px;border-radius:50%;border:2.5px solid rgba(140,133,120,.3);border-top-color:#C9502A;animation:r .9s linear infinite}
        @keyframes r{to{transform:rotate(360deg)}}
        </style><div class="w"><div class="s"></div>DayROAD 준비 중…</div>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    @objc func showMain() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openDiag() {
        if engine.port > 0, let u = URL(string: "http://127.0.0.1:\(engine.port)/diag") { NSWorkspace.shared.open(u) }
    }

    @objc func reloadPage() {
        if let u = pageURL { web.load(URLRequest(url: u)) }
    }

    @objc func menuAction(_ sender: NSMenuItem) {
        showMain()
        if let a = sender.representedObject as? String { callJS("menu", ["action": a]) }
    }

    // MARK: WKWebView

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let cur = webView.url, cur.host == "127.0.0.1" else { return }
        pageReady = true
        if let u = pendingURL {
            pendingURL = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.callJS("url", ["url": u.absoluteString]) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let u = action.request.url else { decisionHandler(.allow); return }
        let scheme = u.scheme ?? ""
        if scheme == "about" || scheme == "data" || scheme == "blob" || u.host == "127.0.0.1" || u.host == "localhost" {
            decisionHandler(.allow)
            return
        }
        if scheme == "file" {
            decisionHandler(.cancel)
            return
        }
        NSWorkspace.shared.open(u)
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = action.request.url, u.scheme == "http" || u.scheme == "https" { NSWorkspace.shared.open(u) }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard pageURL != nil, !quitting else { return }
        Log.write("⚠️ 화면을 불러오지 못함: \(error.localizedDescription) → 다시 시도")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.reloadPage() }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Log.write("⚠️ 화면 프로세스가 멈춤 → 다시 불러와요")
        reloadPage()
    }

    func webViewDidClose(_ webView: WKWebView) {
        window.orderOut(nil)
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "확인")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert()
        a.messageText = message
        a.addButton(withTitle: "확인")
        a.addButton(withTitle: "취소")
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    // MARK: 메뉴

    func item(_ menu: NSMenu, _ title: String, _ action: String, _ key: String, _ mods: NSEvent.ModifierFlags = [.command]) {
        let it = menu.addItem(withTitle: title, action: #selector(menuAction(_:)), keyEquivalent: key)
        it.keyEquivalentModifierMask = mods
        it.representedObject = action
        it.target = self
    }

    func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "DayROAD에 관하여", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        item(appMenu, "설정…", "settings", ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "DayROAD 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "기타 가리기", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "모두 보기", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "DayROAD 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        main.addItem(fileItem)
        let file = NSMenu(title: "파일")
        item(file, "새 할 일", "new", "n")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileItem.submenu = file

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: "보기")
        item(view, "오늘", "today", "1")
        item(view, "이번 주", "week", "2")
        item(view, "이번 달", "month", "3")
        item(view, "마감 다가옴", "due", "4")
        item(view, "반복하는 일", "repeat", "5")
        item(view, "언젠가", "someday", "6")
        item(view, "끝낸 일", "done", "7")
        view.addItem(NSMenuItem.separator())
        let fs = view.addItem(withTitle: "전체 화면", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        view.addItem(NSMenuItem.separator())
        let diag = view.addItem(withTitle: "진단 정보 보기", action: #selector(openDiag), keyEquivalent: "")
        diag.target = self
        viewItem.submenu = view

        let winItem = NSMenuItem()
        main.addItem(winItem)
        let win = NSMenu(title: "윈도우")
        win.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "확대/축소", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        win.addItem(NSMenuItem.separator())
        let show = win.addItem(withTitle: "DayROAD 창 보기", action: #selector(showMain), keyEquivalent: "")
        show.target = self
        winItem.submenu = win

        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }
}

// MARK: - 위젯 모습을 그림 파일로 (맥 빌드 서버의 시험용: DayROAD --render-widgets <폴더>)

@MainActor
func renderWidgetSnapshots(to dir: String) {
    let data = WidgetFiles.load()
    let t = data == nil ? WToday.sample : WToday.make(data)
    let sizes: [(WFamily, CGFloat, CGFloat, String)] = [(.small, 170, 170, "small"), (.medium, 364, 170, "medium"), (.large, 364, 382, "large")]
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for scheme in [ColorScheme.light, .dark] {
        let p = WPalette.of(scheme)
        let row = HStack(alignment: .top, spacing: 24) {
            ForEach(Array(sizes.enumerated()), id: \.offset) { _, s in
                DayROADWidgetView(t: t, family: s.0, toggle: { AnyView(WCheck(done: $0.isDone, p: p)) }, p: p)
                    .frame(width: s.1, height: s.2)
                    .background(p.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
            }
        }
        .padding(32)
        .background(Color(hex: scheme == .dark ? "#3A4048" : "#BCC7BF"))
        .environment(\.colorScheme, scheme)
        let r = ImageRenderer(content: row)
        r.scale = 2
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("widgets-\(scheme == .dark ? "dark" : "light").png"))
        }
    }
}

// MARK: - 시작

if let i = CommandLine.arguments.firstIndex(of: "--render-widgets"), i + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated { renderWidgetSnapshots(to: CommandLine.arguments[i + 1]) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
