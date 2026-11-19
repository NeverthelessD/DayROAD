import EventKit
import Foundation
import SwiftUI
import UserNotifications

// 아이폰에만 있는 설정 · 알림 · 캘린더
// (한 주의 시작은 맥과 같아야 해서 할 일 파일(data.json)에 있어요 — Store.setWeekStart)

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let ud = UserDefaults.standard

    @Published var theme: String { didSet { ud.set(theme, forKey: "theme") } }            // system | light | dark
    @Published var carryOver: Bool { didSet { ud.set(carryOver, forKey: "carryOver"); Store.shared.tick() } }
    @Published var morningOn: Bool { didSet { ud.set(morningOn, forKey: "morningOn"); Notify.shared.scheduleSoon() } }
    @Published var morningTime: String { didSet { ud.set(morningTime, forKey: "morningTime"); Notify.shared.scheduleSoon() } }
    @Published var dueOn: Bool { didSet { ud.set(dueOn, forKey: "dueOn"); Notify.shared.scheduleSoon() } }
    @Published var dueDays: Int { didSet { ud.set(dueDays, forKey: "dueDays"); Notify.shared.scheduleSoon() } }
    @Published var dueTime: String { didSet { ud.set(dueTime, forKey: "dueTime"); Notify.shared.scheduleSoon() } }
    @Published var calendarShow: Bool { didSet { ud.set(calendarShow, forKey: "calendarShow") } }

    init() {
        theme = ud.string(forKey: "theme") ?? "system"
        carryOver = ud.object(forKey: "carryOver") as? Bool ?? true
        morningOn = ud.object(forKey: "morningOn") as? Bool ?? false
        morningTime = ud.string(forKey: "morningTime") ?? "08:30"
        dueOn = ud.object(forKey: "dueOn") as? Bool ?? true
        dueDays = ud.object(forKey: "dueDays") as? Int ?? 1
        dueTime = ud.string(forKey: "dueTime") ?? "09:00"
        calendarShow = ud.object(forKey: "calendarShow") as? Bool ?? true
    }

    var scheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
}

// MARK: - 알림

@MainActor
final class Notify: ObservableObject {
    static let shared = Notify()
    @Published var status: UNAuthorizationStatus = .notDetermined
    private var pending: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()

    func refreshStatus() async {
        status = await center.notificationSettings().authorizationStatus
    }

    func request() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        await refreshStatus()
        scheduleSoon()
    }

    func scheduleSoon() {
        pending?.cancel()
        pending = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            await schedule()
        }
    }

    /// 앞으로 8일의 할 일 알림 · 아침 알림 · 마감 미리 알림 · 사용 기간 알림을 통째로 다시 예약해요 (dr- 로 시작, 60개까지)
    func schedule() async {
        await refreshStatus()
        guard status == .authorized || status == .provisional else { return }
        let st = Store.shared, s = AppSettings.shared
        let now = Date()
        let today = Day.today()
        var list: [(Date, String, String, String)] = []   // 언제 · id · 제목 · 내용
        let open = st.d.tasks.filter { !$0.done }
        for t in open where t.bucket == "day" && !t.alarm.isEmpty && t.date >= today && t.date <= Day.addDays(today, 8) {
            if let at = Day.at(t.date, t.alarm), at > now {
                list.append((at, "dr-a-\(t.id)", t.title, t.time.isEmpty ? "할 일 알림" : "\(Day.time(t.time))에 할 일"))
            }
        }
        if s.morningOn {
            for k in 0...7 {
                let day = Day.addDays(today, k)
                let l = Store.sortDay(open.filter { $0.bucket == "day" && $0.date == day })
                guard !l.isEmpty, let at = Day.at(day, s.morningTime), at > now else { continue }
                let first = l.prefix(3).map { $0.title }.joined(separator: " · ")
                list.append((at, "dr-m-\(day)", "오늘 할 일 \(l.count)개", first))
            }
        }
        if s.dueOn {
            for t in open where !t.due.isEmpty {
                let day = Day.addDays(t.due, -s.dueDays)
                guard let at = Day.at(day, s.dueTime), at > now else { continue }
                let when = s.dueDays == 0 ? "오늘까지" : s.dueDays == 1 ? "내일까지" : "\(Day.mdw(t.due))까지"
                list.append((at, "dr-d-\(t.id)", "마감 \(when)", t.title))
            }
        }
        let pass = AppPass.read()
        if let e = pass.expires, pass.free {
            let a = e.addingTimeInterval(-86400), b = e.addingTimeInterval(-7200)
            if a > now { list.append((a, "dr-p-1", "DayROAD 사용 기간이 내일 끝나요", "\(pass.untilText)까지예요. 끝난 뒤 아이폰을 맥에 연결하고 Xcode에서 ▶ 를 눌러 주세요. 할 일은 iCloud 에 그대로 있어요.")) }
            if b > now { list.append((b, "dr-p-2", "DayROAD 사용 기간이 2시간 남았어요", "끝나면 앱이 열리지 않아요. 끝난 뒤 맥 Xcode에서 ▶ 를 누르면 새로 7일이 시작돼요.")) }
            let c = e.addingTimeInterval(60)
            if c > now { list.append((c, "dr-p-3", "DayROAD 사용 기간이 끝났어요", "지금 아이폰을 맥에 연결하고 Xcode에서 ▶ 를 누르면 새로 7일이 시작돼요.")) }
        }
        list.sort { $0.0 < $1.0 }
        let pendingIDs = await center.pendingNotificationRequests().map { $0.identifier }.filter { $0.hasPrefix("dr-") }
        center.removePendingNotificationRequests(withIdentifiers: pendingIDs)
        for (at, id, title, body) in list.prefix(60) {
            let c = UNMutableNotificationContent()
            c.title = title
            c.body = body
            c.sound = .default
            if id.hasPrefix("dr-a-") || id.hasPrefix("dr-d-") { c.userInfo = ["task": String(id.dropFirst(5))] }
            let comps = Day.cal.dateComponents([.year, .month, .day, .hour, .minute], from: at)
            try? await center.add(UNNotificationRequest(identifier: id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)))
        }
    }
}

// MARK: - 아이폰 캘린더 (보기만)

struct EvItem: Identifiable, Hashable {
    var id: String
    var title: String
    var time: String     // "" = 하루 종일
    var color: Color
}

@MainActor
final class Cal: ObservableObject {
    static let shared = Cal()
    private let store = EKEventStore()
    @Published var status: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published var events: [String: [EvItem]] = [:]

    var allowed: Bool { status == .fullAccess || status == .authorized }

    func request() async {
        _ = try? await store.requestFullAccessToEvents()
        status = EKEventStore.authorizationStatus(for: .event)
        load()
    }

    /// 이번 주 앞뒤로 6주
    func load() {
        if Demo.on { events = Demo.events(); return }
        guard allowed, AppSettings.shared.calendarShow else { events = [:]; return }
        let start = Day.pd(Day.addDays(Day.today(), -14))
        let end = Day.pd(Day.addDays(Day.today(), 28))
        let pred = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var out: [String: [EvItem]] = [:]
        for e in store.events(matching: pred) {
            var day = e.startDate ?? start
            let last = e.endDate ?? day
            var n = 0
            repeat {
                let key = Day.fd(day)
                let time = e.isAllDay || Day.fd(e.startDate) != key ? "" : Day.hm(e.startDate)
                out[key, default: []].append(EvItem(id: (e.eventIdentifier ?? UUID().uuidString) + key, title: e.title ?? "",
                                                    time: time, color: Color(cgColor: e.calendar.cgColor)))
                day = Day.cal.date(byAdding: .day, value: 1, to: Day.cal.startOfDay(for: day))!
                n += 1
            } while day < last && n < 14
        }
        for k in out.keys { out[k]?.sort { ($0.time.isEmpty ? "00" : $0.time) < ($1.time.isEmpty ? "00" : $1.time) } }
        events = out
    }
}
