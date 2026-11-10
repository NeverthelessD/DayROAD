// DayROAD — 위젯이 읽는 파일 (앱 · 위젯이 함께 써요)
// made by. Nevertheless_D
//
// ~/Library/Application Support/DayROAD/widget/
//   widget.json   : 엔진이 씀 (오늘 할 일 · 이번 주 숫자 · 앞으로 8일)
//   actions.jsonl : 위젯이 씀 (체크박스를 누른 기록) → 앱(엔진)이 켜져 있으면 2초 안에, 꺼져 있으면 다음에 켤 때 반영
// 위젯은 맥의 보호 상자(샌드박스) 안에서 돌아서 이 폴더만 읽고 쓰도록 허락받았어요 (Widget.entitlements).

import Foundation

struct WItem: Codable, Hashable, Identifiable {
    var id: String
    var title: String
    var time: String
    var done: Bool?
    var color: String
    var colorDark: String
    var badge: String?

    var isDone: Bool { done ?? false }
}

struct WDay: Codable, Hashable {
    var dow: String
    var day: Int
    var total: Int
    var done: Int
    var today: Bool
}

struct WData: Codable {
    var v: Int
    var date: String
    var dow: String
    var day: Int
    var month: Int
    var total: Int
    var done: Int
    var items: [WItem]
    var next: WItem?
    var week: [WDay]
    var weekLabel: String
    var weekTotal: Int
    var weekDone: Int
    var updated: Int64
    var days: [String: [WItem]]?
    var carry: Bool?
}

enum WidgetFiles {
    /// 진짜 홈 폴더 (위젯 안에서 NSHomeDirectory() 는 보호 상자 폴더를 가리켜서, 사용자 정보로 찾아요)
    static var realHome: URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
    static var dir: URL { realHome.appendingPathComponent("Library/Application Support/DayROAD/widget", isDirectory: true) }
    static var data: URL { dir.appendingPathComponent("widget.json") }
    static var actions: URL { dir.appendingPathComponent("actions.jsonl") }

    static func load() -> WData? {
        guard let d = try? Data(contentsOf: data) else { return nil }
        return try? JSONDecoder().decode(WData.self, from: d)
    }

    static func todayString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 위젯에서 체크박스를 눌렀을 때: 기록을 남기고, 위젯이 바로 바뀐 모습을 보이도록 widget.json 도 고쳐 둬요
    static func toggle(id: String, done: Bool) {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let line = "{\"id\":\"\(id)\",\"done\":\(done ? "true" : "false")}\n"
        if let h = try? FileHandle(forWritingTo: actions) {
            h.seekToEndOfFile()
            h.write(line.data(using: .utf8)!)
            try? h.close()
        } else {
            try? line.data(using: .utf8)!.write(to: actions)
        }
        guard var w = load() else { return }
        for i in w.items.indices where w.items[i].id == id { w.items[i].done = done }
        if var days = w.days {
            for k in days.keys {
                if let j = days[k]?.firstIndex(where: { $0.id == id }) { days[k]?[j].done = done }
            }
            w.days = days
        }
        w.done = w.items.filter { $0.isDone }.count
        if let n = w.next, n.id == id, done {
            w.next = w.items.first { !$0.isDone }
        }
        if let wi = w.week.firstIndex(where: { $0.today }) { w.week[wi].done = w.done }
        if let d = try? JSONEncoder().encode(w) {
            let tmp = data.appendingPathExtension("tmp")
            if (try? d.write(to: tmp)) != nil {
                _ = try? fm.replaceItemAt(data, withItemAt: tmp)
            }
        }
    }
}

/// 위젯이 그릴 '오늘' 모습. 앱이 꺼진 채 날짜가 바뀌었으면, 저장해 둔 앞으로의 할 일과 못 끝낸 일로 오늘을 꾸며요.
struct WToday {
    var dow: String
    var day: Int
    var items: [WItem]
    var total: Int
    var done: Int
    var next: WItem?
    var week: [WDay]
    var weekLabel: String
    var weekTotal: Int
    var weekDone: Int
    var stale: Bool
    var empty: Bool

    static let dowNames = ["일", "월", "화", "수", "목", "금", "토"]

    static func make(_ w: WData?, now: Date = Date()) -> WToday {
        let cal = Calendar.current
        let today = WidgetFiles.todayString(now)
        let dow = dowNames[cal.component(.weekday, from: now) - 1] + "요일"
        let day = cal.component(.day, from: now)
        guard let w = w else {
            return WToday(dow: dow, day: day, items: [], total: 0, done: 0, next: nil, week: [], weekLabel: "", weekTotal: 0, weekDone: 0, stale: false, empty: true)
        }
        if w.date == today {
            return WToday(dow: dow, day: day, items: w.items, total: w.total, done: w.done, next: w.next, week: w.week, weekLabel: w.weekLabel,
                          weekTotal: w.weekTotal, weekDone: w.weekDone, stale: false, empty: false)
        }
        // 날짜가 바뀌었는데 앱이 아직 정리하지 않았어요
        var items: [WItem] = []
        if w.date < today {
            if w.carry ?? true {
                items += w.items.filter { !$0.isDone }
                for (d, l) in (w.days ?? [:]) where d < today { items += l.filter { !$0.isDone } }
            }
            items += (w.days?[today] ?? []).filter { !$0.isDone }
        }
        var seen = Set<String>()
        items = items.filter { seen.insert($0.id).inserted }
        items.sort { ($0.time.isEmpty ? "99" : $0.time) < ($1.time.isEmpty ? "99" : $1.time) }
        let week = w.week.map { d -> WDay in var x = d; x.today = (x.day == day); return x }
        return WToday(dow: dow, day: day, items: items, total: items.count, done: 0, next: items.first, week: week, weekLabel: w.weekLabel,
                      weekTotal: w.weekTotal, weekDone: w.weekDone, stale: true, empty: false)
    }
}
