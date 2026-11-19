import Foundation

// 할 일 파일(data.json)의 모양 — 맥 엔진(engine/store.go)과 칸 이름 · 뜻이 똑같아야 해요.
// 모르는 칸이 와도 읽을 수 있게, 없는 칸은 빈 값으로 채워요.

struct LogEntry: Codable, Hashable {
    var date: String
    var text: String
    var progress: Int

    init(date: String, text: String, progress: Int) {
        self.date = date; self.text = text; self.progress = progress
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        progress = try c.decodeIfPresent(Int.self, forKey: .progress) ?? 0
    }
}

struct DTask: Codable, Identifiable, Hashable {
    var id: String = ""
    var title: String = ""
    var note: String = ""
    var bucket: String = "day"     // day | week | someday
    var date: String = ""          // day: YYYY-MM-DD
    var weekOf: String = ""        // week: 그 주의 첫날
    var time: String = ""          // HH:MM
    var cat: String = ""
    var star = false
    var done = false
    var doneAt: String = ""
    var due: String = ""
    var alarm: String = ""
    var rep: String = ""           // "" | daily | weekdays | weekly | monthly  (파일에서는 "repeat")
    var progress: Int = 0
    var log: [LogEntry] = []
    var carriedFrom: String = ""
    var calendar = false
    var eventId: String = ""
    var reminderId: String = ""
    var nextId: String = ""
    var order: Double = 0
    var created: Int64 = 0
    var updated: Int64 = 0

    enum CodingKeys: String, CodingKey {
        case id, title, note, bucket, date, weekOf, time, cat, star, done, doneAt, due, alarm
        case rep = "repeat"
        case progress, log, carriedFrom, calendar, eventId, reminderId, nextId, order, created, updated
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func s(_ k: CodingKeys) -> String { (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil ?? "" }
        func b(_ k: CodingKeys) -> Bool { (try? c.decodeIfPresent(Bool.self, forKey: k)) ?? nil ?? false }
        func i64(_ k: CodingKeys) -> Int64 {
            if let v = try? c.decodeIfPresent(Int64.self, forKey: k) { return v }
            if let v = try? c.decodeIfPresent(Double.self, forKey: k) { return Int64(v) }
            return 0
        }
        id = s(.id); title = s(.title); note = s(.note); bucket = s(.bucket); date = s(.date); weekOf = s(.weekOf)
        time = s(.time); cat = s(.cat); star = b(.star); done = b(.done); doneAt = s(.doneAt); due = s(.due); alarm = s(.alarm)
        rep = s(.rep)
        progress = (try? c.decodeIfPresent(Int.self, forKey: .progress)) ?? nil ?? 0
        log = (try? c.decodeIfPresent([LogEntry].self, forKey: .log)) ?? nil ?? []
        carriedFrom = s(.carriedFrom); calendar = b(.calendar); eventId = s(.eventId); reminderId = s(.reminderId); nextId = s(.nextId)
        order = (try? c.decodeIfPresent(Double.self, forKey: .order)) ?? nil ?? 0
        created = i64(.created); updated = i64(.updated)
    }
}

struct DCategory: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var color: String
    var order: Int

    init(id: String, name: String, color: String, order: Int) {
        self.id = id; self.name = name; self.color = color; self.order = order
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? nil ?? "slate"
        order = (try? c.decodeIfPresent(Int.self, forKey: .order)) ?? nil ?? 0
    }
}

struct StoreData: Codable, Equatable {
    var v: Int = 1
    var tasks: [DTask] = []
    var cats: [DCategory] = []
    var lastDay: String = ""
    var deleted: [String: Int64] = [:]   // 지운 할 일 id → 지운 시각(ms)
    var catsUpdated: Int64 = 0           // 분류 목록을 마지막으로 바꾼 시각
    var weekStart: String = ""           // sun | mon (기기끼리 같게)
    var weekStartAt: Int64 = 0

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        v = (try? c.decodeIfPresent(Int.self, forKey: .v)) ?? nil ?? 1
        tasks = try c.decodeIfPresent([DTask].self, forKey: .tasks) ?? []
        cats = (try? c.decodeIfPresent([DCategory].self, forKey: .cats)) ?? nil ?? []
        lastDay = (try? c.decodeIfPresent(String.self, forKey: .lastDay)) ?? nil ?? ""
        deleted = (try? c.decodeIfPresent([String: Int64].self, forKey: .deleted)) ?? nil ?? [:]
        catsUpdated = (try? c.decodeIfPresent(Int64.self, forKey: .catsUpdated)) ?? nil ?? 0
        weekStart = (try? c.decodeIfPresent(String.self, forKey: .weekStart)) ?? nil ?? ""
        weekStartAt = (try? c.decodeIfPresent(Int64.self, forKey: .weekStartAt)) ?? nil ?? 0
    }

    var isEmpty: Bool { tasks.isEmpty && cats.isEmpty }
}

enum Coding {
    /// 비교용 (키 순서 고정)
    static func canon<T: Encodable>(_ v: T) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? e.encode(v)) ?? Data()
    }

    /// 파일에 쓸 때 (사람이 읽기 좋게)
    static func pretty<T: Encodable>(_ v: T) -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes, .prettyPrinted]
        return (try? e.encode(v)) ?? Data()
    }
}

/// 분류 색 — 맥 엔진 palette 와 같은 값 (라이트, 다크)
enum Palette {
    static let colors: [String: (String, String)] = [
        "blue": ("#3366B0", "#7EA6E6"),
        "orange": ("#C9502A", "#F2936B"),
        "purple": ("#6650B8", "#A796EA"),
        "green": ("#2F7D50", "#6FC08F"),
        "teal": ("#1F7A80", "#6CC3C8"),
        "gold": ("#9A6B0F", "#E0B25C"),
        "pink": ("#B23A5B", "#E58AA3"),
        "slate": ("#56606E", "#A9B2BE"),
    ]
    static let keys = ["blue", "orange", "purple", "green", "teal", "gold", "pink", "slate"]
    static let names = ["blue": "파랑", "orange": "주홍", "purple": "보라", "green": "초록", "teal": "청록", "gold": "황토", "pink": "분홍", "slate": "회색"]
}
