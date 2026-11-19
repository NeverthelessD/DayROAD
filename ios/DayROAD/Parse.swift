import Foundation

// 빠른 추가 글 읽기 — 맥 화면(engine/web/js/parse.js)과 같은 규칙
// "금요일까지 보고서" · "내일 오후 3시 치과" · "매주 월 9시 회의" · "#공부 영어 단어 !" · "분류는 사역, 회의 준비"

struct Quick {
    struct Chip: Hashable, Identifiable {
        var k: String
        var label: String
        var id: String { k + label }
    }
    var title = ""
    var chips: [Chip] = []
    var bucket: String?
    var date: String?
    var weekOf: String?
    var time: String?
    var due: String?
    var rep: String?
    var star = false
    var cat: String?
    var newCat: String?
}

enum QuickParse {
    static let WD: [String: Int] = ["일": 0, "월": 1, "화": 2, "수": 3, "목": 4, "금": 5, "토": 6]
    static let sp = "(?:^|\\s)"
    static let end = "(?=\\s|$|[,.])"
    static let dateWord = "(오늘|내일|모레|글피|언젠가|(?:이번\\s?주|다음\\s?주|담주)\\s?[월화수목금토일]요일|[월화수목금토일]요일|\\d{1,2}월\\s?\\d{1,2}일|\\d{1,2}\\/\\d{1,2}|이번\\s?주|다음\\s?주|담주)"

    static func nextWd(_ base: String, _ wd: Int) -> String {
        Day.addDays(base, (wd - Day.weekday(base) + 7) % 7)
    }

    static func inWeek(_ first: String, _ wd: Int, _ ws: String) -> String {
        let w0 = ws == "sun" ? 0 : 1
        return Day.addDays(first, (wd - w0 + 7) % 7)
    }

    static func hourOf(_ ap: String?, _ hs: String, _ ms: String?) -> String? {
        guard var h = Int(hs) else { return nil }
        let m = Int(ms ?? "0") ?? 0
        if h > 24 || m > 59 { return nil }
        switch ap {
        case "오후", "저녁", "밤", "낮":
            if h < 12 { h += 12 }
            if ap == "낮" && h > 17 { h -= 12 }
        case "오전", "아침", "새벽":
            if h == 12 { h = 0 }
        default:
            if h >= 1 && h <= 6 { h += 12 }   // "3시" 는 보통 오후 3시
        }
        if h == 24 { h = 0 }
        return String(format: "%02d:%02d", h, m)
    }

    enum DateHit { case date(String), week(String), someday }

    static func dateOf(_ word: String, ws: String) -> DateHit? {
        let today = Day.today()
        let w = word.replacingOccurrences(of: " ", with: "")
        switch w {
        case "오늘": return .date(today)
        case "내일": return .date(Day.addDays(today, 1))
        case "모레": return .date(Day.addDays(today, 2))
        case "글피": return .date(Day.addDays(today, 3))
        case "언젠가": return .someday
        case "이번주": return .week(Day.weekStartOf(today, ws))
        case "다음주", "담주": return .week(Day.addDays(Day.weekStartOf(today, ws), 7))
        default: break
        }
        if let m = match("^(이번주|다음주|담주)?([월화수목금토일])요일$", w), let wd = WD[m[2] ?? ""] {
            if m[1] == "이번주" { return .date(inWeek(Day.weekStartOf(today, ws), wd, ws)) }
            if m[1] != nil { return .date(inWeek(Day.addDays(Day.weekStartOf(today, ws), 7), wd, ws)) }
            return .date(nextWd(today, wd))
        }
        if let m = match("^(\\d{1,2})월(\\d{1,2})일$", w) ?? match("^(\\d{1,2})\\/(\\d{1,2})$", w),
           let mo = Int(m[1] ?? ""), let dd = Int(m[2] ?? "") {
            let y = Day.parts(today).y
            for yy in [y, y + 1] {
                guard let d = Day.cal.date(from: DateComponents(year: yy, month: mo, day: dd)),
                      Day.cal.component(.month, from: d) == mo else { return nil }
                let s = Day.fd(d)
                if s >= today { return .date(s) }
            }
        }
        return nil
    }

    static func match(_ pattern: String, _ s: String) -> [String?]? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : (s as NSString).substring(with: r)
        }
    }

    /// cats: 지금 분류 목록 · skip: 표시에서 × 로 뺀 종류 · base: 기본 날짜(그 날 화면에서 적으면 그 날)
    static func parse(_ text: String, cats: [DCategory], ws: String, base: String? = nil, skip: Set<String> = []) -> Quick {
        let today = Day.today()
        let base = base ?? today
        var out = Quick()
        var s = " " + text.trimmingCharacters(in: .whitespacesAndNewlines) + " "
        func chip(_ k: String, _ l: String) { out.chips.append(.init(k: k, label: l)) }

        /// 맞는 글을 찾아 fn 이 true 를 돌려주면 그 글을 빈칸으로 바꿔요 (global: 전부, 아니면 처음 하나)
        func take(_ pattern: String, global: Bool = false, kind: String? = nil, _ fn: ([String?]) -> Bool) {
            if let k = kind, skip.contains(k) { return }
            guard let re = try? NSRegularExpression(pattern: pattern) else { return }
            let ns = s as NSString
            var ms = re.matches(in: s, range: NSRange(location: 0, length: ns.length))
            if !global { ms = Array(ms.prefix(1)) }
            var cut: [NSRange] = []
            for m in ms {
                let g: [String?] = (0..<m.numberOfRanges).map { i in
                    let r = m.range(at: i)
                    return r.location == NSNotFound ? nil : ns.substring(with: r)
                }
                if fn(g) { cut.append(m.range) }
            }
            var t = s as NSString
            for r in cut.reversed() { t = t.replacingCharacters(in: r, with: " ") as NSString }
            s = t as String
        }

        func findCat(_ name: String) -> DCategory? {
            cats.first { $0.name == name } ?? cats.first { $0.name.lowercased() == name.lowercased() } ?? cats.first { $0.name.hasPrefix(name) }
        }

        // 분류: "분류는 사역," · "분류: 사역" · "분류 사역,"
        take("(?:^|\\s)분류\\s*(?:(?:는|은|:|：|=)\\s*([^\\s,，.。#]+)\\s*[,，]?|\\s+([^\\s,，.。#]+)\\s*[,，])(?=\\s|$)") { g in
            if skip.contains("cat") { return false }
            var name = g[1] ?? g[2] ?? ""
            for suf in ["으로", "로", "에"] where name.hasSuffix(suf) && name.count > suf.count { name = String(name.dropLast(suf.count)); break }
            if name.isEmpty { return false }
            if let c = findCat(name) { out.cat = c.id; chip("cat", "#" + c.name) } else { out.newCat = String(name.prefix(20)); chip("cat", "새 분류 ‘\(out.newCat!)’") }
            return true
        }
        if out.cat == nil && out.newCat == nil && !skip.contains("cat") {
            take(sp + "#(\\S+)" + end, global: true) { g in
                guard let c = findCat(g[1] ?? "") else { return false }
                out.cat = c.id; chip("cat", "#" + c.name)
                return true
            }
        }

        // 중요
        take(sp + "(중요|!)" + end, global: true, kind: "star") { _ in out.star = true; return true }
        if !skip.contains("star") {
            let tr = s.trimmingCharacters(in: .whitespaces)
            if tr.count > 1 && tr.hasSuffix("!") && !tr.dropLast().hasSuffix(" ") { s = String(tr.dropLast()) + " "; out.star = true }
        }
        if out.star { chip("star", "중요") }

        // 반복
        let rb = skip.contains("repeat")
        take(sp + "매주\\s?([월화수목금토일])(?:요일)?(?:마다)?" + end) { g in
            if rb { return false }
            out.rep = "weekly"; out.date = nextWd(base > today ? base : today, WD[g[1]!]!); chip("repeat", "매주 \(g[1]!)요일"); return true
        }
        take(sp + "([월화수목금토일])요일마다" + end) { g in
            if rb { return false }
            out.rep = "weekly"; out.date = nextWd(today, WD[g[1]!]!); chip("repeat", "매주 \(g[1]!)요일"); return true
        }
        take(sp + "매(?:달|월)\\s?(\\d{1,2})일" + end) { g in
            guard !rb, let n = Int(g[1] ?? ""), n >= 1 && n <= 31 else { return false }
            out.rep = "monthly"
            let p = Day.parts(today)
            var dd = Day.cal.date(from: DateComponents(year: p.y, month: p.m, day: n))!
            if Day.fd(dd) < today { dd = Day.cal.date(from: DateComponents(year: p.y, month: p.m + 1, day: n))! }
            out.date = Day.fd(dd); chip("repeat", "매달 \(n)일"); return true
        }
        take(sp + "(매일|날마다)" + end) { _ in if rb { return false }; out.rep = "daily"; chip("repeat", "매일"); return true }
        take(sp + "평일(?:마다)?" + end) { _ in if rb { return false }; out.rep = "weekdays"; chip("repeat", "평일마다"); return true }
        take(sp + "매주(?:마다)?" + end) { _ in if rb { return false }; out.rep = "weekly"; chip("repeat", "매주"); return true }
        take(sp + "매(?:달|월)(?:마다)?" + end) { _ in if rb { return false }; out.rep = "monthly"; chip("repeat", "매달"); return true }

        // 날짜 · 마감 ("…까지" 는 마감)
        take(sp + dateWord + "(까지|에는|에)?" + end, global: true) { g in
            guard let word = g[1], let hit = dateOf(word, ws: ws) else { return false }
            let post = g[2]
            if post == "까지" ? skip.contains("due") : skip.contains("date") { return false }
            if post == "까지" {
                switch hit {
                case .someday: return false
                case .date(let x): out.due = x
                case .week(let w): out.due = Day.addDays(w, 6)
                }
                chip("due", Day.rel(out.due!, ws: ws) + "까지")
                return true
            }
            switch hit {
            case .someday: out.bucket = "someday"; chip("date", "언젠가")
            case .week(let w):
                out.bucket = "week"; out.weekOf = w
                chip("date", w == Day.weekStartOf(today, ws) ? "이번 주 안에" : "다음 주 안에")
            case .date(let x):
                if out.date != nil && out.rep != nil { return false }
                out.date = x; out.bucket = "day"; chip("date", Day.rel(x, ws: ws))
            }
            return true
        }

        // 시간
        take(sp + "(오전|오후|아침|저녁|밤|낮|새벽)?\\s?(\\d{1,2})시(?:\\s?(\\d{1,2})분|\\s?(반))?(에|까지)?" + end, kind: "time") { g in
            guard let t = hourOf(g[1], g[2] ?? "", g[4] != nil ? "30" : g[3]) else { return false }
            out.time = t; chip("time", Day.time(t) + (g[5] == "까지" ? "까지" : "")); return true
        }
        if out.time == nil {
            take(sp + "(오전|오후)?\\s?(\\d{1,2}):(\\d{2})" + end, kind: "time") { g in
                let h = Int(g[2] ?? "") ?? 99, m = Int(g[3] ?? "") ?? 99
                let t = g[1] != nil ? hourOf(g[1], g[2]!, g[3]) : (h < 24 && m < 60 ? String(format: "%02d:%02d", h, m) : nil)
                guard let tt = t else { return false }
                out.time = tt; chip("time", Day.time(tt)); return true
            }
        }

        if out.rep != nil && out.date == nil && out.bucket != "week" { out.date = base }
        var title = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        title = title.replacingOccurrences(of: "(\\s*[,，]\\s*)+", with: ", ", options: .regularExpression)
        title = title.replacingOccurrences(of: "^[\\s,，·]+|[\\s,，·]+$", with: "", options: .regularExpression)
        out.title = title.trimmingCharacters(in: .whitespaces)
        if out.title.isEmpty { return Quick(title: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return out
    }
}
