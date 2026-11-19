import CryptoKit
import Foundation

// iCloud Drive › DayROAD › data.json 과 맞추기 (맥 engine/icloud.go 와 같은 규칙)
//
// 무료 애플 ID 로 설치한 앱은 iCloud(CloudKit) 기능을 못 써서, 사용자가 '파일' 창에서 DayROAD 폴더를 한 번 골라 주면
// 그 폴더를 기억해 두고(북마크) 계속 읽고 써요. 앱이 앞에 있는 동안 6초마다, 그리고 바꿀 때마다 맞춰요.
// - 처음 연결: iCloud 자료를 그대로 받아요 (아이폰에 있던 것은 버려요 — 처음엔 비어 있어요)
// - 그다음: 할 일마다 updated 가 큰 쪽, 지운 기록, 분류 목록, 한 주의 시작을 합쳐요 (Store.merge)
// - 받은 내용과 합친 결과가 같으면 다시 쓰지 않아요 (맥과 서로 계속 다시 쓰지 않게)
// - iCloud 가 만든 충돌 사본(data 2.json)은 합친 뒤 지워요
// - 읽을 수 없는(받는 중인) 파일은 덮어쓰지 않아요

@MainActor
final class Cloud: ObservableObject {
    static let shared = Cloud()

    enum State: String { case none, starting, ok, waiting, missing, error }

    @Published private(set) var state: State = .none
    @Published private(set) var msg = ""
    @Published private(set) var last: Date?
    @Published private(set) var connected = false

    private var bookmark: Data?
    private var subpath = ""          // 고른 폴더 안에서 DayROAD 폴더까지 (iCloud Drive 를 통째로 고른 경우 "DayROAD")
    private var synced = false        // 이번 실행에서 한 번이라도 맞췄는지 (그 전에는 쓰지 않아요)
    private var adoptNext = false     // 다음 맞추기에서 iCloud 자료를 그대로 받기
    private var lastHash = ""
    private var busy = false
    private var again = false
    private var timer: Timer?
    private var pushTask: Task<Void, Never>?

    /// 시험 모드: 보통 폴더를 iCloud 자리로 써요
    var demoFolder: URL?

    private let defaults = UserDefaults.standard

    init() {
        bookmark = defaults.data(forKey: "folderBookmark")
        subpath = defaults.string(forKey: "folderSubpath") ?? ""
        connected = bookmark != nil
        if connected { state = .starting }
    }

    func useDemo(_ dir: URL) {
        demoFolder = dir
        connected = true
        state = .starting
    }

    // MARK: 폴더 고르기

    /// '파일' 창에서 고른 폴더를 확인하고 기억해요. 문제가 있으면 안내 글을 돌려줘요.
    func connect(_ url: URL) async -> String? {
        let ok = url.startAccessingSecurityScopedResource()
        defer { if ok { url.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        func hasData(_ d: URL) -> Bool {
            fm.fileExists(atPath: d.appendingPathComponent("data.json").path)
                || fm.fileExists(atPath: d.appendingPathComponent(".data.json.icloud").path)
        }
        var sub = ""
        if !hasData(url) {
            let child = url.appendingPathComponent("DayROAD", isDirectory: true)
            if hasData(child) {
                sub = "DayROAD"
            } else {
                Log.write("폴더 고르기: 할 일 파일 없음 \(url.lastPathComponent)")
                return "이 폴더에는 DayROAD 할 일 파일이 없어요. iCloud Drive 안의 ‘DayROAD’ 폴더를 골라 주세요. (맥 DayROAD › 설정 › iCloud 저장이 켜져 있어야 해요)"
            }
        }
        guard let bm = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            return "폴더를 기억하지 못했어요. 다시 골라 주세요."
        }
        bookmark = bm
        subpath = sub
        defaults.set(bm, forKey: "folderBookmark")
        defaults.set(sub, forKey: "folderSubpath")
        connected = true
        synced = false
        adoptNext = true
        lastHash = ""
        state = .starting
        Log.write("폴더 연결: \(url.lastPathComponent)/\(sub)")
        await sync("연결")
        return state == .ok ? nil : (msg.isEmpty ? "할 일 파일을 읽지 못했어요. 잠시 뒤 다시 해 볼게요." : msg)
    }

    func disconnect() {
        bookmark = nil
        defaults.removeObject(forKey: "folderBookmark")
        connected = false
        synced = false
        state = .none
    }

    /// 기억해 둔 폴더 (시작 · 끝은 부르는 쪽에서)
    private func resolve() -> URL? {
        if let d = demoFolder { return d }
        guard let bm = bookmark else { return nil }
        var stale = false
        guard let u = try? URL(resolvingBookmarkData: bm, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale, let nb = try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            bookmark = nb
            defaults.set(nb, forKey: "folderBookmark")
        }
        return u
    }

    // MARK: 언제 맞추나

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 6, repeats: true) { _ in
            Task { @MainActor in await Cloud.shared.sync("6초") }
        }
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    /// 아이폰에서 바꾼 뒤: 잠깐 모았다가 맞춰요
    func pushSoon() {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await sync("바꿈")
        }
    }

    // MARK: 맞추기

    private enum Remote {
        case data(Data, conflicts: [(URL, Data)])
        case placeholder
        case missing
        case failed(String)
    }

    func sync(_ why: String) async {
        guard connected, let root = resolve() else { return }
        if busy { again = true; return }
        busy = true
        defer {
            busy = false
            if again { again = false; Task { @MainActor in await self.sync("다시") } }
        }
        Store.shared.applyWidgetActions()
        let scoped = demoFolder == nil
        let sub = subpath
        let dir = sub.isEmpty ? root : root.appendingPathComponent(sub, isDirectory: true)

        let remote: Remote = await Task.detached { Cloud.readRemote(root: root, dir: dir, scoped: scoped) }.value
        let store = Store.shared

        switch remote {
        case .failed(let e):
            set(.error, "iCloud Drive 의 할 일 파일을 읽지 못했어요: \(e)")
            return
        case .placeholder:
            set(.waiting, "iCloud 에서 할 일 파일을 받는 중이에요")
            return
        case .missing:
            if synced && !store.d.isEmpty {
                // 맞춘 적이 있는데 파일이 사라졌으면 아이폰 것으로 다시 만들어요
                await write(Coding.pretty(store.d), root: root, dir: dir, scoped: scoped, remove: [])
                return
            }
            set(.missing, "DayROAD 폴더에 할 일 파일이 없어요. 맥 DayROAD › 설정 › iCloud 저장을 켜 주세요")
            return
        case .data(let b, let conflicts):
            let h = Self.hash(b)
            if synced && h == lastHash && conflicts.isEmpty {
                set(.ok, "")
                last = Date()
                return
            }
            guard let r = try? JSONDecoder().decode(StoreData.self, from: b) else {
                set(.waiting, "iCloud 의 할 일 파일을 읽는 중이에요")
                return
            }
            var others = [r]
            var used: [URL] = []
            for (u, cb) in conflicts {
                if let o = try? JSONDecoder().decode(StoreData.self, from: cb) { others.append(o); used.append(u) }
            }
            if !synced && (adoptNext || store.d.isEmpty) {
                store.adopt(r)
                if others.count > 1 { _ = store.absorb(Array(others.dropFirst())) }
                adoptNext = false
                Log.write("iCloud 자료를 받았어요: 할 일 \(store.d.tasks.count)개 · 분류 \(store.d.cats.count)개")
                Notify.shared.scheduleSoon()
            } else if store.absorb(others) {
                Log.write("iCloud 에서 바뀐 것을 합쳤어요 (\(why))")
                Notify.shared.scheduleSoon()
            }
            synced = true
            if Coding.canon(store.d) != Coding.canon(r) || !used.isEmpty {
                await write(Coding.pretty(store.d), root: root, dir: dir, scoped: scoped, remove: used)
            } else {
                lastHash = h
                set(.ok, "")
                last = Date()
            }
        }
    }

    private func write(_ b: Data, root: URL, dir: URL, scoped: Bool, remove: [URL]) async {
        let err: String? = await Task.detached { Cloud.writeRemote(b, root: root, dir: dir, scoped: scoped, remove: remove) }.value
        if let e = err {
            set(.error, "iCloud Drive 에 저장하지 못했어요: \(e)")
            Log.write("⚠️ iCloud 쓰기 실패: \(e)")
            return
        }
        lastHash = Self.hash(b)
        synced = true
        set(.ok, "")
        last = Date()
    }

    private func set(_ s: State, _ m: String) {
        if s != state || m != msg, s != .ok { Log.write("iCloud 상태: \(s.rawValue) \(m)") }
        state = s
        msg = m
    }

    nonisolated static func hash(_ b: Data) -> String {
        SHA256.hash(data: b).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: 파일 읽기 · 쓰기 (뒤에서)

    nonisolated private static func readRemote(root: URL, dir: URL, scoped: Bool) -> Remote {
        let ok = scoped ? root.startAccessingSecurityScopedResource() : false
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        let file = dir.appendingPathComponent("data.json")
        try? fm.startDownloadingUbiquitousItem(at: file)
        if !fm.fileExists(atPath: file.path) {
            if fm.fileExists(atPath: dir.appendingPathComponent(".data.json.icloud").path) { return .placeholder }
            return .missing
        }
        var cerr: NSError?
        var out: Data?
        var inner: Error?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &cerr) { u in
            do { out = try Data(contentsOf: u) } catch { inner = error }
        }
        if let e = cerr ?? (inner as NSError?) { return .failed(e.localizedDescription) }
        guard let data = out else { return .failed("빈 파일") }
        var conflicts: [(URL, Data)] = []
        if let names = try? fm.contentsOfDirectory(atPath: dir.path) {
            for n in names where n.hasPrefix("data ") && n.hasSuffix(".json") {
                let u = dir.appendingPathComponent(n)
                if let cb = try? Data(contentsOf: u) { conflicts.append((u, cb)) }
            }
        }
        return .data(data, conflicts: conflicts)
    }

    nonisolated private static func writeRemote(_ b: Data, root: URL, dir: URL, scoped: Bool, remove: [URL]) -> String? {
        let ok = scoped ? root.startAccessingSecurityScopedResource() : false
        defer { if ok { root.stopAccessingSecurityScopedResource() } }
        let file = dir.appendingPathComponent("data.json")
        var cerr: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: file, options: .forReplacing, error: &cerr) { u in
            do { try b.write(to: u, options: .atomic) } catch { inner = error }
        }
        if let e = cerr ?? (inner as NSError?) { return e.localizedDescription }
        for u in remove {
            NSFileCoordinator().coordinate(writingItemAt: u, options: .forDeleting, error: nil) { x in
                try? FileManager.default.removeItem(at: x)
            }
        }
        return nil
    }
}
