import Foundation
import SwiftUI

// 시험 모드 (맥 빌드 서버에서 화면을 찍을 때만): 실행 인자 -demo
//   -tab today|week|month|lists|settings · -theme light|dark · -detail (자세히 칸 열기) · -connect (처음 켤 때 화면)
//   -selftest (규칙 시험 → Documents/selftest.txt) · -renderWidgets (위젯 그림 → Documents/widgets-*.png)
// iCloud 대신 앱 안의 Documents/DemoCloud/DayROAD 폴더를 써요. 빌드 서버가 그 파일을 고쳐서 맞추기도 시험해요.

enum Demo {
    static let args = ProcessInfo.processInfo.arguments
    static let on = args.contains("-demo")

    static func arg(_ k: String) -> String? {
        guard let i = args.firstIndex(of: k), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func flag(_ k: String) -> Bool { args.contains(k) }

    static var docs: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var cloudDir: URL { docs.appendingPathComponent("DemoCloud/DayROAD", isDirectory: true) }

    @MainActor
    static func setup() {
        guard on else { return }
        if let t = arg("-theme") { AppSettings.shared.theme = t }
        if flag("-connect") { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        let f = cloudDir.appendingPathComponent("data.json")
        if !fm.fileExists(atPath: f.path) || flag("-fresh") {
            try? fm.removeItem(at: Paths.file("data.json"))
            try? Coding.pretty(sample()).write(to: f, options: .atomic)
        }
        Cloud.shared.useDemo(cloudDir)
    }

    static func sample() -> StoreData {
        var d = StoreData()
        let today = Day.today()
        let ws = Day.weekStartOf(today, "sun")
        let now = Fmt.nowMs() - 3_600_000
        d.weekStart = "sun"
        d.weekStartAt = 1
        d.cats = [
            DCategory(id: "work", name: "일", color: "blue", order: 0),
            DCategory(id: "personal", name: "개인", color: "orange", order: 1),
            DCategory(id: "study", name: "공부", color: "purple", order: 2),
            DCategory(id: "health", name: "건강", color: "green", order: 3),
        ]
        var k = 0
        func t(_ title: String, _ cat: String, date: String? = nil, bucket: String = "day", time: String = "", due: String = "", rep: String = "",
               star: Bool = false, done: Bool = false, progress: Int = 0, carried: String = "", log: [LogEntry] = [], alarm: String = "") -> DTask {
            k += 1
            var x = DTask()
            x.id = "demo\(k)"; x.title = title; x.cat = cat; x.bucket = bucket
            x.date = bucket == "day" ? (date ?? today) : ""
            x.weekOf = bucket == "week" ? ws : ""
            x.time = time; x.due = due; x.rep = rep; x.star = star; x.done = done; x.doneAt = done ? today : ""
            x.progress = done ? 100 : progress; x.carriedFrom = carried; x.log = log; x.alarm = alarm
            x.created = now + Int64(k); x.updated = now + Int64(k); x.order = Double(now + Int64(k))
            return x
        }
        let y = Day.addDays(today, -1)
        d.tasks = [
            t("주간 회의 자료 정리", "work", time: "09:30", due: today, rep: "weekly", star: true, progress: 50,
              log: [LogEntry(date: y, text: "1~2장 요약 끝, 그래프 정리만 남음", progress: 50)]),
            t("은행 업무 보기", "personal", time: "11:00", done: true),
            t("디자인 시안 피드백 보내기", "work", time: "14:00", due: Day.addDays(today, 1), progress: 25, alarm: "13:45"),
            t("보고서 초안 쓰기", "work", due: Day.addDays(today, 3), progress: 60, carried: y,
              log: [LogEntry(date: y, text: "목차랑 1장까지 씀. 2장 자료는 폴더에 모아 둠", progress: 60),
                    LogEntry(date: Day.addDays(today, -2), text: "관련 자료 조사 끝", progress: 20)]),
            t("운동 30분", "health", rep: "daily"),
            t("영어 단어 20개 외우기", "study", rep: "daily", done: true),
            t("우유 · 계란 사기", "personal", carried: y),
            t("치과 예약", "health", date: Day.addDays(today, 1), time: "15:00"),
            t("팀 점심", "work", date: Day.addDays(today, 2), time: "12:00"),
            t("대청소", "personal", date: Day.addDays(today, 3)),
            t("책 한 권 끝까지 읽기", "study", bucket: "week"),
            t("자동차 보험 갱신하기", "personal", bucket: "week"),
            t("사진 정리하기", "personal", bucket: "someday"),
            t("새 언어 배우기", "study", bucket: "someday"),
        ]
        d.lastDay = today
        return d
    }

    static func events() -> [String: [EvItem]] {
        let today = Day.today()
        return [
            today: [EvItem(id: "e1", title: "팀 점심", time: "12:00", color: T.cat("blue")),
                    EvItem(id: "e2", title: "엄마 생신 저녁", time: "19:30", color: T.cat("pink"))],
            Day.addDays(today, 2): [EvItem(id: "e3", title: "교회 모임", time: "", color: T.cat("teal"))],
        ]
    }
}

// MARK: - 규칙 시험 (-selftest): 맥 엔진과 같은 답이 나오는지

@MainActor
enum SelfTest {
    static func run() -> String {
        var out: [String] = []
        func check(_ name: String, _ ok: Bool) { out.append((ok ? "PASS  " : "FAIL  ") + name) }
        let ws = "sun"
        let cats = [DCategory(id: "w", name: "일", color: "blue", order: 0), DCategory(id: "s", name: "사역", color: "teal", order: 1)]
        let today = Day.today()

        var q = QuickParse.parse("금요일까지 보고서", cats: cats, ws: ws)
        check("빠른 추가: 금요일까지 → 마감", q.title == "보고서" && q.due == QuickParse.nextWd(today, 5))
        q = QuickParse.parse("내일 오후 3시 치과", cats: cats, ws: ws)
        check("빠른 추가: 내일 오후 3시", q.title == "치과" && q.date == Day.addDays(today, 1) && q.time == "15:00")
        q = QuickParse.parse("매주 월 9시 회의", cats: cats, ws: ws)
        check("빠른 추가: 매주 월 9시", q.title == "회의" && q.rep == "weekly" && q.time == "09:00" && q.date == QuickParse.nextWd(today, 1))
        q = QuickParse.parse("분류는 사역, 회의 준비 !", cats: cats, ws: ws)
        check("빠른 추가: 분류는 사역 · 중요", q.title == "회의 준비" && q.cat == "s" && q.star)
        q = QuickParse.parse("분류는 운동, 스트레칭", cats: cats, ws: ws)
        check("빠른 추가: 없는 분류는 새로", q.newCat == "운동" && q.title == "스트레칭")
        q = QuickParse.parse("분류 작업 하기", cats: cats, ws: ws)
        check("빠른 추가: 그냥 '분류' 낱말은 그대로", q.title == "분류 작업 하기" && q.cat == nil && q.newCat == nil)
        q = QuickParse.parse("다음 주 장보기", cats: cats, ws: ws)
        check("빠른 추가: 다음 주 안에", q.bucket == "week" && q.weekOf == Day.addDays(Day.weekStartOf(today, ws), 7))
        q = QuickParse.parse("12월 25일 성탄 예배 오전 11시", cats: cats, ws: ws)
        check("빠른 추가: 12월 25일 오전 11시", q.title == "성탄 예배" && q.time == "11:00" && (q.date ?? "").hasSuffix("-12-25"))

        check("날짜: 매달 31일 → 다음 달 말일", Day.nextOccurrence("2026-01-31", "monthly") == "2026-02-28")
        check("날짜: 평일 다음 차례 (금 → 월)", Day.nextOccurrence("2026-11-20", "weekdays") == "2026-11-23")
        check("날짜: 주 첫날 (일요일 시작)", Day.weekStartOf("2026-11-19", "sun") == "2026-11-15")
        check("날짜: 주 첫날 (월요일 시작)", Day.weekStartOf("2026-11-19", "mon") == "2026-11-16")

        // 맥이 쓴 파일 모양 그대로 읽기 (Go 가 쓴 숫자 · 빈 칸)
        let goJSON = """
        {"v":1,"tasks":[{"id":"a1","title":"맥에서","note":"","bucket":"day","date":"2026-11-19","weekOf":"","time":"","cat":"","star":false,"done":false,"doneAt":"","due":"","alarm":"","repeat":"daily","progress":0,"log":[],"carriedFrom":"","calendar":false,"eventId":"E","reminderId":"","nextId":"","order":1795063540972,"created":1795063540972,"updated":1795063540972}],
         "cats":[{"id":"w","name":"일","color":"blue","order":0}],"lastDay":"2026-11-19","deleted":{"x9":1795063540000},"catsUpdated":0,"weekStart":"mon","weekStartAt":5}
        """
        let g = try? JSONDecoder().decode(StoreData.self, from: Data(goJSON.utf8))
        check("맥 파일 읽기", g?.tasks.first?.rep == "daily" && g?.tasks.first?.order == 1795063540972 && g?.deleted["x9"] == 1795063540000 && g?.weekStart == "mon")
        let back = String(data: Coding.pretty(g!), encoding: .utf8) ?? ""
        check("맥이 읽을 수 있게 쓰기 (repeat · 큰 숫자)", back.contains("\"repeat\" : \"daily\"") && back.contains("1795063540972") && !back.contains("1.795"))
        check("같을 때 고르는 기준(맥과 같은 글자)",
              Store.tieKey(g!.tasks[0]) == ["E", "", "", "", "2026-11-19", "", "0", "0", "", "", "", "맥에서"].joined(separator: "\u{01}"))
        check("바이트 순서 비교", Store.greater("b", "a") && !Store.greater("a", "a") && Store.greater("가", "z"))
        return out.joined(separator: "\n") + "\n"
    }
}
