import Foundation
import WidgetKit

// 할 일 저장소 — 맥 엔진(engine/store.go · icloud.go · widget.go)을 그대로 옮겼어요.
// 규칙이 달라지면 두 기기가 서로 다른 답을 내니까, 한쪽을 고치면 다른 쪽도 같이 고칠 것.
//
// - 할 일은 day(정한 날) · week(이번 주 안에) · someday(언젠가) 중 하나
// - 날짜가 바뀌면 못 끝낸 일을 오늘로(설정), 반복하는 일은 다음 차례로 (updated 는 바꾸지 않아요)
// - 반복하는 일을 끝내면 다음 차례가 새로 생기고, 되돌리면 손대지 않은 다음 차례는 지워요
// - 지우면 deleted[id] 에 지운 시각을 남겨요 (다른 기기가 되살리지 않게)

@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published private(set) var d = StoreData()
    @Published private(set) var rev = 0

    /// 바뀐 뒤 할 일 (iCloud 에 쓰기 · 알림 다시 예약)
    var afterCommit: (() -> Void)?
    var carryOver: () -> Bool = { true }

    private var path: URL { Paths.file("data.json") }

    init() { load() }

    // MARK: 읽기 · 쓰기

    func load() {
        if let b = try? Data(contentsOf: path), let x = try? JSONDecoder().decode(StoreData.self, from: b) {
            d = x
        }
        for i in d.tasks.indices { normalize(&d.tasks[i]) }
    }

    func saveLocal() {
        do {
            try Coding.pretty(d).write(to: path, options: .atomic)
        } catch {
            Log.write("⚠️ 저장 실패: \(error.localizedDescription)")
        }
    }

    /// iCloud 에서 받은 자료를 그대로 쓰기 (처음 연결할 때)
    func adopt(_ x: StoreData) {
        d = x
        for i in d.tasks.indices { normalize(&d.tasks[i]) }
        _ = rollover(Day.today())
        rev += 1
        saveLocal()
        exportWidget()
    }

    /// 다른 기기 자료 합치기 → 바뀌었으면 true (iCloud 에 다시 쓸지는 Cloud 가 정해요)
    func absorb(_ others: [StoreData]) -> Bool {
        let before = Coding.canon(d)
        for o in others { merge(o) }
        pruneTombstones()
        for i in d.tasks.indices { normalize(&d.tasks[i]) }
        _ = rollover(Day.today())
        let changed = before != Coding.canon(d)
        if changed {
            rev += 1
            saveLocal()
            exportWidget()
        }
        return changed
    }

    private func commit() {
        d.v = 1
        rev += 1
        saveLocal()
        exportWidget()
        afterCommit?()
    }

    // MARK: 찾기

    var weekStart: String { d.weekStart == "mon" ? "mon" : "sun" }

    func task(_ id: String) -> DTask? { d.tasks.first { $0.id == id } }
    private func index(_ id: String) -> Int? { d.tasks.firstIndex { $0.id == id } }

    func cat(_ id: String) -> DCategory? { d.cats.first { $0.id == id } }
    var cats: [DCategory] { d.cats.sorted { $0.order < $1.order } }

    // MARK: 다듬기 (store.go normalize)

    func normalize(_ t: inout DTask) {
        t.title = t.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.title.count > 300 { t.title = String(t.title.prefix(300)) }
        if !["day", "week", "someday"].contains(t.bucket) { t.bucket = "day" }
        if t.bucket == "day" && !Day.valid(t.date) { t.date = Day.today() }
        if t.bucket != "day" { t.date = ""; t.alarm = ""; t.time = "" }
        if t.bucket == "week" && !Day.valid(t.weekOf) { t.weekOf = Day.weekStartOf(Day.today(), weekStart) }
        if t.bucket != "week" { t.weekOf = "" }
        if !Self.isHM(t.time) { t.time = "" }
        if !Self.isHM(t.alarm) { t.alarm = "" }
        if !Day.valid(t.due) { t.due = "" }
        if !["", "daily", "weekdays", "weekly", "monthly"].contains(t.rep) { t.rep = "" }
        if t.bucket == "someday" { t.rep = "" }
        if t.bucket == "week" && !t.rep.isEmpty { t.rep = "weekly" }
        t.progress = max(0, min(100, t.progress))
        if !t.cat.isEmpty && cat(t.cat) == nil { t.cat = "" }
        if !t.done { t.doneAt = "" }
    }

    static func isHM(_ s: String) -> Bool {
        let p = s.split(separator: ":")
        guard s.count == 5, p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    // MARK: 넘기기 · 반복

    @discardableResult
    func rollover(_ today: String) -> Bool {
        var changed = false
        let ws = weekStart
        let thisWeek = Day.weekStartOf(today, ws)
        for i in d.tasks.indices {
            var t = d.tasks[i]
            if t.done { continue }
            switch t.bucket {
            case "day":
                if t.date >= today { continue }
                if !t.rep.isEmpty {
                    let old = t.date
                    var x = t.date
                    var n = 0
                    while x < today && n < 4000 { x = Day.nextOccurrence(x, t.rep); n += 1 }
                    if !t.due.isEmpty { t.due = Day.addDays(t.due, Day.between(old, x)) }
                    t.date = x; t.progress = 0; t.carriedFrom = ""
                    changed = true
                } else if carryOver() {
                    if t.carriedFrom.isEmpty { t.carriedFrom = t.date }
                    t.date = today
                    changed = true
                }
            case "week":
                let a = Day.weekStartOf(t.weekOf, ws)
                if a != t.weekOf { t.weekOf = a; changed = true }
                if Day.addDays(t.weekOf, 6) >= today { break }
                if !t.rep.isEmpty {
                    t.weekOf = thisWeek; t.progress = 0
                    changed = true
                } else if carryOver() {
                    if t.carriedFrom.isEmpty { t.carriedFrom = t.weekOf }
                    t.weekOf = thisWeek
                    changed = true
                }
            default: break
            }
            d.tasks[i] = t
        }
        return changed
    }

    func tick() {
        let today = Day.today()
        var changed = rollover(today)
        if d.lastDay != today { d.lastDay = today; changed = true }
        if changed { commit() }
    }

    private func setDone(_ i: Int, _ done: Bool) {
        guard d.tasks[i].done != done else { return }
        let now = Fmt.nowMs()
        d.tasks[i].done = done
        d.tasks[i].updated = now
        if done {
            d.tasks[i].doneAt = Day.today()
            d.tasks[i].progress = 100
            let t = d.tasks[i]
            if !t.rep.isEmpty && (t.nextId.isEmpty || task(t.nextId) == nil) {
                var n = t
                n.id = Fmt.randomID()
                n.done = false; n.doneAt = ""; n.progress = 0; n.log = []
                n.carriedFrom = ""; n.eventId = ""; n.reminderId = ""; n.nextId = ""
                n.created = now; n.updated = now; n.order = Double(now)
                switch t.bucket {
                case "day":
                    n.date = Day.nextOccurrence(t.date, t.rep)
                    var k = 0
                    while n.date < Day.today() && k < 4000 { n.date = Day.nextOccurrence(n.date, t.rep); k += 1 }
                    if !t.due.isEmpty { n.due = Day.addDays(t.due, Day.between(t.date, n.date)) }
                case "week":
                    n.weekOf = Day.addDays(t.weekOf, 7)
                default: break
                }
                d.tasks.append(n)
                d.tasks[i].nextId = n.id
            }
        } else {
            d.tasks[i].doneAt = ""
            d.tasks[i].progress = d.tasks[i].log.first?.progress ?? 0
            let nid = d.tasks[i].nextId
            if !nid.isEmpty {
                if let n = task(nid), !n.done, n.updated == n.created, n.log.isEmpty { remove(nid) }
                if let j = index(d.tasks[i].id) { d.tasks[j].nextId = "" }
            }
        }
    }

    @discardableResult
    private func remove(_ id: String) -> DTask? {
        guard let i = index(id) else { return nil }
        let t = d.tasks.remove(at: i)
        d.deleted[id] = max(Fmt.nowMs(), t.updated)
        return t
    }

    // MARK: 바꾸기 (화면에서)

    @discardableResult
    func add(_ q: Quick, defaults: DTask? = nil) -> DTask? {
        var t = defaults ?? DTask()
        let now = Fmt.nowMs()
        t.id = Fmt.randomID()
        t.title = q.title
        if let b = q.bucket { t.bucket = b }
        if let x = q.date { t.date = x; t.bucket = "day" }
        if let x = q.weekOf { t.weekOf = x }
        if let x = q.time { t.time = x }
        if let x = q.due { t.due = x }
        if let x = q.rep { t.rep = x }
        if q.star { t.star = true }
        if let name = q.newCat, let c = saveCat(id: nil, name: name, color: nextColor(), silent: true) { t.cat = c.id }
        if let x = q.cat { t.cat = x }
        if t.bucket == "day" && t.date.isEmpty { t.date = Day.today() }
        t.created = now; t.updated = now; t.order = Double(now)
        normalize(&t)
        guard !t.title.isEmpty else { return nil }
        d.tasks.append(t)
        commit()
        return t
    }

    /// 자세히 칸에서 고친 것 저장 (끝냄 · 기록은 따로)
    func update(_ x: DTask) {
        guard let i = index(x.id) else { return }
        let cur = d.tasks[i]
        var t = x
        t.done = cur.done; t.doneAt = cur.doneAt; t.nextId = cur.nextId; t.log = cur.log
        t.created = cur.created; t.eventId = cur.eventId; t.reminderId = cur.reminderId
        normalize(&t)
        if t.title.isEmpty { t.title = cur.title }
        if t.bucket != cur.bucket || t.date != cur.date || t.weekOf != cur.weekOf { t.carriedFrom = "" }
        guard t != cur else { return }
        t.updated = Fmt.nowMs()
        d.tasks[i] = t
        commit()
    }

    func toggle(_ id: String, to done: Bool? = nil) {
        guard let i = index(id) else { return }
        setDone(i, done ?? !d.tasks[i].done)
        commit()
    }

    func delete(_ id: String) {
        guard remove(id) != nil else { return }
        for i in d.tasks.indices where d.tasks[i].nextId == id { d.tasks[i].nextId = "" }
        commit()
    }

    /// 다시 넣기 (지우기 되돌리기)
    func restore(_ t: DTask) {
        var x = t
        x.updated = max(Fmt.nowMs(), (d.deleted[t.id] ?? 0) + 1)
        d.deleted.removeValue(forKey: t.id)
        d.tasks.append(x)
        commit()
    }

    func addLog(_ id: String, text: String, progress: Int?) {
        guard let i = index(id) else { return }
        if let p = progress { d.tasks[i].progress = max(0, min(100, p)) }
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !s.isEmpty {
            d.tasks[i].log.insert(LogEntry(date: Day.today(), text: String(s.prefix(2000)), progress: d.tasks[i].progress), at: 0)
        }
        d.tasks[i].updated = Fmt.nowMs()
        commit()
    }

    func editLog(_ id: String, _ k: Int, text: String) {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let i = index(id), !s.isEmpty, d.tasks[i].log.indices.contains(k) else { return }
        d.tasks[i].log[k].text = String(s.prefix(2000))
        d.tasks[i].updated = Fmt.nowMs()
        commit()
    }

    func delLog(_ id: String, _ k: Int) {
        guard let i = index(id), d.tasks[i].log.indices.contains(k) else { return }
        d.tasks[i].log.remove(at: k)
        d.tasks[i].updated = Fmt.nowMs()
        commit()
    }

    func toTomorrow(_ id: String) {
        guard var t = task(id) else { return }
        t.bucket = "day"
        t.date = Day.addDays(max(t.date, Day.today()), 1)
        update(t)
    }

    // 분류

    func nextColor() -> String {
        let used = Set(d.cats.map { $0.color })
        return Palette.keys.first { !used.contains($0) } ?? "teal"
    }

    @discardableResult
    func saveCat(id: String?, name: String, color: String, silent: Bool = false) -> DCategory? {
        let n = String(name.trimmingCharacters(in: .whitespaces).prefix(20))
        guard !n.isEmpty else { return nil }
        if d.cats.contains(where: { $0.id != id && $0.name == n }) { return nil }
        let col = Palette.colors[color] == nil ? "slate" : color
        if let id = id, let i = d.cats.firstIndex(where: { $0.id == id }) {
            d.cats[i].name = n; d.cats[i].color = col
            d.catsUpdated = Fmt.nowMs()
            if !silent { commit() }
            return d.cats[i]
        }
        let c = DCategory(id: Fmt.randomID(5), name: n, color: col, order: (d.cats.map { $0.order }.max() ?? -1) + 1)
        d.cats.append(c)
        d.catsUpdated = Fmt.nowMs()
        if !silent { commit() }
        return c
    }

    func deleteCat(_ id: String) {
        guard let i = d.cats.firstIndex(where: { $0.id == id }) else { return }
        d.cats.remove(at: i)
        d.catsUpdated = Fmt.nowMs()
        for k in d.tasks.indices where d.tasks[k].cat == id { d.tasks[k].cat = "" }
        commit()
    }

    func setWeekStart(_ ws: String) {
        guard ws == "sun" || ws == "mon", ws != d.weekStart else { return }
        d.weekStart = ws
        d.weekStartAt = Fmt.nowMs()
        rollover(Day.today())
        commit()
    }

    // MARK: 합치기 (icloud.go merge 와 같은 규칙)

    func merge(_ o: StoreData) {
        for (id, at) in o.deleted where at > (d.deleted[id] ?? 0) { d.deleted[id] = at }
        if o.catsUpdated > d.catsUpdated || (o.catsUpdated == d.catsUpdated && Self.greater(Self.catsTieKey(o.cats), Self.catsTieKey(d.cats))) {
            if !o.cats.isEmpty || o.catsUpdated > d.catsUpdated {
                d.cats = o.cats; d.catsUpdated = o.catsUpdated
            }
        }
        for rt in o.tasks where !rt.id.isEmpty {
            if let i = index(rt.id) {
                let lt = d.tasks[i]
                if rt.updated > lt.updated || (rt.updated == lt.updated && Self.greater(Self.tieKey(rt), Self.tieKey(lt))) {
                    d.tasks[i] = rt
                }
            } else if (d.deleted[rt.id] ?? -1) < rt.updated {
                d.tasks.append(rt)
            }
        }
        d.tasks.removeAll { t in
            if let at = d.deleted[t.id], at >= t.updated { return true }
            return false
        }
        if (o.weekStart == "sun" || o.weekStart == "mon") && (o.weekStartAt > d.weekStartAt || (o.weekStartAt == d.weekStartAt && o.weekStart > d.weekStart)) {
            d.weekStart = o.weekStart; d.weekStartAt = o.weekStartAt
        }
        if o.lastDay > d.lastDay { d.lastDay = o.lastDay }
    }

    /// updated 가 같을 때 고르는 기준 — 맥 icloud.go taskTieKey · catsTieKey 와 똑같이 (UTF-8 바이트 순서로 비교)
    static func tieKey(_ t: DTask) -> String {
        [t.eventId, t.reminderId, t.cat, t.carriedFrom, t.date, t.weekOf, String(t.progress), t.done ? "1" : "0", t.doneAt, t.due, t.nextId, t.title]
            .joined(separator: "\u{01}")
    }

    static func catsTieKey(_ cs: [DCategory]) -> String {
        cs.map { "\($0.id)\u{02}\($0.name)\u{02}\($0.color)\u{02}\($0.order)" }
            .sorted { lessBytes($0, $1) }
            .joined(separator: "\u{01}")
    }

    static func lessBytes(_ a: String, _ b: String) -> Bool { Array(a.utf8).lexicographicallyPrecedes(Array(b.utf8)) }
    static func greater(_ a: String, _ b: String) -> Bool { lessBytes(b, a) }

    private func pruneTombstones() {
        let limit = Fmt.nowMs() - 60 * 86_400_000
        d.deleted = d.deleted.filter { $0.value >= limit }
    }

    // MARK: 위젯 (widget.go 와 같은 모양)

    static func sortDay(_ ts: [DTask]) -> [DTask] {
        ts.sorted { a, b in
            if a.done != b.done { return !a.done }
            let ta = a.time.isEmpty ? "99" : a.time, tb = b.time.isEmpty ? "99" : b.time
            if ta != tb { return ta < tb }
            if a.star != b.star { return a.star }
            return a.order < b.order
        }
    }

    func colors(_ catID: String) -> (String, String) {
        if let c = cat(catID), let p = Palette.colors[c.color] { return p }
        return ("", "")
    }

    func exportWidget() {
        guard let dir = Paths.widgetDir else { return }
        let today = Day.today()
        let p = Day.parts(today)
        var w = WData(v: 1, date: today, dow: Day.dowNames[Day.weekday(today)] + "요일", day: p.d, month: p.m, total: 0, done: 0,
                      items: [], next: nil, week: [], weekLabel: "", weekTotal: 0, weekDone: 0, updated: Fmt.nowMs(), days: [:], carry: carryOver())
        let item = { (t: DTask, on: String) -> WItem in
            let c = self.colors(t.cat)
            return WItem(id: t.id, title: t.title, time: t.time, done: t.done, color: c.0, colorDark: c.1, badge: Day.dueBadge(t.due, from: on))
        }
        let day = Self.sortDay(d.tasks.filter { $0.bucket == "day" && $0.date == today })
        let now = Day.hm(Date())
        for t in day {
            w.total += 1
            if t.done { w.done += 1 }
            if w.items.count < 12 { w.items.append(item(t, today)) }
            if !t.done && w.next == nil && (t.time.isEmpty || t.time >= now) { w.next = item(t, today) }
        }
        if w.next == nil, let t = day.first(where: { !$0.done }) { w.next = item(t, today) }
        let ws = Day.weekStartOf(today, weekStart)
        let end = Day.addDays(ws, 6)
        for k in 0..<7 {
            let x = Day.addDays(ws, k)
            let l = d.tasks.filter { $0.bucket == "day" && $0.date == x }
            let wd = WDay(dow: Day.dowNames[Day.weekday(x)], day: Day.parts(x).d, total: l.count, done: l.filter { $0.done }.count, today: x == today)
            w.weekTotal += wd.total; w.weekDone += wd.done
            w.week.append(wd)
        }
        for t in d.tasks where t.bucket == "week" && t.weekOf >= ws && t.weekOf <= end {
            w.weekTotal += 1
            if t.done { w.weekDone += 1 }
        }
        let a = Day.parts(ws), b = Day.parts(end)
        w.weekLabel = a.m == b.m ? "\(a.m)월 \(a.d)일 – \(b.d)일" : "\(a.m)월 \(a.d)일 – \(b.m)월 \(b.d)일"
        var days: [String: [WItem]] = [:]
        for k in 1...8 {
            let x = Day.addDays(today, k)
            days[x] = Array(Self.sortDay(d.tasks.filter { $0.bucket == "day" && $0.date == x && !$0.done }).prefix(12)).map { item($0, x) }
        }
        w.days = days
        if let b = try? JSONEncoder().encode(w) {
            let u = dir.appendingPathComponent("widget.json")
            if (try? b.write(to: u, options: .atomic)) != nil {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// 위젯에서 누른 체크박스 반영
    func applyWidgetActions() {
        guard let dir = Paths.widgetDir else { return }
        let p = dir.appendingPathComponent("actions.jsonl")
        let work = dir.appendingPathComponent("actions.work")
        guard FileManager.default.fileExists(atPath: p.path) else { return }
        try? FileManager.default.removeItem(at: work)
        guard (try? FileManager.default.moveItem(at: p, to: work)) != nil, let s = try? String(contentsOf: work, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: work)
        struct Act: Decodable { var id: String; var done: Bool }
        var n = 0
        for line in s.split(separator: "\n") {
            guard let a = try? JSONDecoder().decode(Act.self, from: Data(line.utf8)), let i = index(a.id) else { continue }
            if d.tasks[i].done != a.done { setDone(i, a.done); n += 1 }
        }
        if n > 0 {
            Log.write("위젯에서 누른 것 \(n)개 반영")
            commit()
        } else {
            exportWidget()
        }
    }
}
