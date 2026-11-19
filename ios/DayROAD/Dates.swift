import Foundation

// 날짜 계산 — 맥 엔진(store.go) · 화면(core.js)과 같은 규칙. 날짜는 "YYYY-MM-DD" 글자로 다뤄요.

enum Day {
    static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        c.locale = Locale(identifier: "ko_KR")
        return c
    }()

    private static let f: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dowNames = ["일", "월", "화", "수", "목", "금", "토"]

    /// 시험 모드에서는 날짜를 고정할 수 있어요 (-today 2026-11-19)
    static var fixedToday: String?

    static func today() -> String { fixedToday ?? fd(Date()) }

    static func fd(_ d: Date) -> String { f.string(from: d) }

    static func pd(_ s: String) -> Date {
        f.date(from: s).map { cal.startOfDay(for: $0) } ?? cal.startOfDay(for: Date())
    }

    static func valid(_ s: String) -> Bool { s.count == 10 && f.date(from: s) != nil }

    static func addDays(_ s: String, _ n: Int) -> String { fd(cal.date(byAdding: .day, value: n, to: pd(s))!) }

    static func between(_ a: String, _ b: String) -> Int {
        Int((pd(b).timeIntervalSince(pd(a)) / 86400).rounded())
    }

    /// 0 = 일요일
    static func weekday(_ s: String) -> Int { cal.component(.weekday, from: pd(s)) - 1 }

    static func weekStartOf(_ s: String, _ ws: String) -> String {
        let wd = weekday(s)
        let off = ws == "sun" ? wd : (wd + 6) % 7
        return addDays(s, -off)
    }

    static func nextOccurrence(_ s: String, _ rep: String) -> String {
        switch rep {
        case "daily": return addDays(s, 1)
        case "weekdays":
            var n = addDays(s, 1)
            while weekday(n) == 0 || weekday(n) == 6 { n = addDays(n, 1) }
            return n
        case "weekly": return addDays(s, 7)
        case "monthly":
            let d = pd(s)
            let y = cal.component(.year, from: d), m = cal.component(.month, from: d), day = cal.component(.day, from: d)
            let first = cal.date(from: DateComponents(year: y, month: m + 1, day: 1))!
            let last = cal.range(of: .day, in: .month, for: first)!.count
            return fd(cal.date(from: DateComponents(year: cal.component(.year, from: first), month: cal.component(.month, from: first), day: min(day, last)))!)
        default: return addDays(s, 1)
        }
    }

    static func parts(_ s: String) -> (y: Int, m: Int, d: Int) {
        let d = pd(s)
        return (cal.component(.year, from: d), cal.component(.month, from: d), cal.component(.day, from: d))
    }

    /// "11월 19일"
    static func md(_ s: String) -> String { let p = parts(s); return "\(p.m)월 \(p.d)일" }

    /// "11월 19일 (목)"
    static func mdw(_ s: String) -> String { "\(md(s)) (\(dowNames[weekday(s)]))" }

    /// 오늘 · 내일 · 모레 · 이번 주 요일 · 날짜
    static func rel(_ s: String, ws: String) -> String {
        let t = today()
        let n = between(t, s)
        if n == 0 { return "오늘" }
        if n == 1 { return "내일" }
        if n == 2 { return "모레" }
        if n == -1 { return "어제" }
        if n > 0 && s <= addDays(weekStartOf(t, ws), 6) { return dowNames[weekday(s)] + "요일" }
        return mdw(s)
    }

    /// "09:30" → "오전 9:30"
    static func time(_ hhmm: String) -> String {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return hhmm }
        let h = p[0], m = p[1]
        let ap = h < 12 ? "오전" : "오후"
        let h12 = h % 12 == 0 ? 12 : h % 12
        return "\(ap) \(h12):\(String(format: "%02d", m))"
    }

    static func hm(_ d: Date) -> String {
        String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d))
    }

    /// "2026-11-19" + "15:00" → Date
    static func at(_ s: String, _ hhmm: String) -> Date? {
        let p = hhmm.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return nil }
        return cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: pd(s))
    }

    /// 마감까지 남은 날 표시: D-day · D-3 · 마감 지남
    static func dueBadge(_ due: String, from: String = today()) -> String {
        guard !due.isEmpty else { return "" }
        let n = between(from, due)
        if n < 0 { return "마감 지남" }
        return n == 0 ? "D-day" : "D-\(n)"
    }
}
