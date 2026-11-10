// DayROAD — 맥 기능 연결: 캘린더 · 미리 알림(EventKit) · 알림 센터
// made by. Nevertheless_D
//
// 맥 '시스템 설정 › 인터넷 계정'에 추가된 iCloud · Google 계정의 캘린더를 그대로 읽어요 (앱에서 따로 로그인하지 않아요).
// 할 일을 '미리 알림'의 DayROAD 목록에 보내면 iCloud 로 아이폰에도 함께 떠요.
// 처음 쓸 때 맥이 허락을 물어봐요. 허락하지 않아도 앱의 다른 기능은 그대로 써요.

import AppKit
import EventKit
import UserNotifications

final class Native: NSObject, UNUserNotificationCenterDelegate {
    var store = EKEventStore()
    var onOpenURL: ((URL) -> Void)?
    var onStoreChanged: (() -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.onStoreChanged?()
        }
    }

    typealias Reply = (Any?, String?) -> Void

    func handle(_ type: String, _ b: [String: Any], reply: @escaping Reply) {
        switch type {
        case "status": status(reply)
        case "requestEvents": requestEvents(reply)
        case "requestReminders": requestReminders(reply)
        case "calendars": reply(["items": calendars()], nil)
        case "events": reply(["items": events(from: b["from"] as? String ?? "", to: b["to"] as? String ?? "")], nil)
        case "eventUpsert": eventUpsert(b, reply)
        case "eventDelete": eventDelete(b, reply)
        case "reminderList": reply(["listId": reminderList(b["listId"] as? String ?? "")?.calendarIdentifier ?? ""], nil)
        case "reminderUpsert": reminderUpsert(b, reply)
        case "reminderDelete": reminderDelete(b, reply)
        case "reminderFetch": reminderFetch(b, reply)
        case "notifySchedule": notifySchedule(b, reply)
        case "requestNotify": requestNotify(reply)
        case "openPrivacy": openPrivacy(b["pane"] as? String ?? ""); reply(["ok": true], nil)
        default: reply(nil, "알 수 없는 요청이에요")
        }
    }

    // MARK: 허락

    static func authName(_ s: EKAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .fullAccess: return "full"
        case .writeOnly: return "writeOnly"
        case .authorized: return "full"
        @unknown default: return "denied"
        }
    }

    static func notifyName(_ s: UNAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized, .provisional: return "authorized"
        @unknown default: return "authorized"
        }
    }

    func status(_ reply: @escaping Reply) {
        let ev = Native.authName(EKEventStore.authorizationStatus(for: .event))
        let rem = Native.authName(EKEventStore.authorizationStatus(for: .reminder))
        UNUserNotificationCenter.current().getNotificationSettings { s in
            DispatchQueue.main.async { reply(["events": ev, "reminders": rem, "notify": Native.notifyName(s.authorizationStatus)], nil) }
        }
    }

    func requestEvents(_ reply: @escaping Reply) {
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToEvents { granted, err in
            DispatchQueue.main.async {
                Log.write("캘린더 허락: \(granted) \(err?.localizedDescription ?? "")")
                self.store.reset()
                reply(["granted": granted], nil)
            }
        }
    }

    func requestReminders(_ reply: @escaping Reply) {
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToReminders { granted, err in
            DispatchQueue.main.async {
                Log.write("미리 알림 허락: \(granted) \(err?.localizedDescription ?? "")")
                self.store.reset()
                reply(["granted": granted], nil)
            }
        }
    }

    // MARK: 캘린더

    static func hex(_ c: CGColor?) -> String {
        guard let c = c, let n = NSColor(cgColor: c)?.usingColorSpace(.sRGB) else { return "#8C8578" }
        return String(format: "#%02X%02X%02X", Int(n.redComponent * 255), Int(n.greenComponent * 255), Int(n.blueComponent * 255))
    }

    func calendars() -> [[String: Any]] {
        var out: [[String: Any]] = []
        let defEv = store.defaultCalendarForNewEvents?.calendarIdentifier
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            for c in store.calendars(for: .event) {
                out.append(["id": c.calendarIdentifier, "title": c.title, "color": Native.hex(c.cgColor), "source": c.source?.title ?? "",
                            "kind": "event", "writable": c.allowsContentModifications, "isDefault": c.calendarIdentifier == defEv])
            }
        }
        if EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            for c in store.calendars(for: .reminder) {
                out.append(["id": c.calendarIdentifier, "title": c.title, "color": Native.hex(c.cgColor), "source": c.source?.title ?? "",
                            "kind": "reminder", "writable": c.allowsContentModifications, "isDefault": false])
            }
        }
        return out
    }

    static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    static func day(_ s: String) -> Date? { dayFmt.date(from: s) }

    static func dayTime(_ d: String, _ t: String) -> Date? {
        guard let day = day(d) else { return nil }
        let p = t.split(separator: ":").compactMap { Int($0) }
        guard p.count == 2 else { return day }
        return Calendar.current.date(bySettingHour: p[0], minute: p[1], second: 0, of: day)
    }

    /// 날짜 범위의 일정 (여러 날에 걸친 일정은 날마다 하나씩)
    func events(from: String, to: String) -> [[String: Any]] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let a = Native.day(from), let b0 = Native.day(to) else { return [] }
        let cal = Calendar.current
        let b = cal.date(byAdding: .day, value: 1, to: b0)!
        let pred = store.predicateForEvents(withStart: a, end: b, calendars: nil)
        var out: [[String: Any]] = []
        for e in store.events(matching: pred) {
            guard let s = e.startDate, let en = e.endDate else { continue }
            var d = max(cal.startOfDay(for: s), a)
            let last = min(cal.startOfDay(for: max(s, en.addingTimeInterval(-1))), b0)
            while d <= last {
                let first = cal.isDate(d, inSameDayAs: s)
                let allDay = e.isAllDay || !first
                out.append(["id": e.eventIdentifier ?? "", "title": e.title ?? "(제목 없음)", "date": Native.dayFmt.string(from: d),
                            "time": allDay ? "" : Native.timeFmt.string(from: s), "allDay": allDay,
                            "calendarId": e.calendar?.calendarIdentifier ?? "", "color": Native.hex(e.calendar?.cgColor),
                            "calendar": e.calendar?.title ?? "", "source": e.calendar?.source?.title ?? ""])
                guard let n = cal.date(byAdding: .day, value: 1, to: d), n > d, out.count < 2000 else { break }
                d = n
            }
        }
        return out
    }

    func eventUpsert(_ b: [String: Any], _ reply: @escaping Reply) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { reply(nil, "캘린더 접근이 허락되지 않았어요"); return }
        let id = b["eventId"] as? String ?? ""
        let ev = (id.isEmpty ? nil : store.event(withIdentifier: id)) ?? EKEvent(eventStore: store)
        if ev.calendar == nil {
            let cid = b["calendarId"] as? String ?? ""
            ev.calendar = (cid.isEmpty ? nil : store.calendar(withIdentifier: cid)) ?? store.defaultCalendarForNewEvents
        }
        guard ev.calendar != nil else { reply(nil, "일정을 넣을 캘린더가 없어요"); return }
        ev.title = b["title"] as? String ?? ""
        let date = b["date"] as? String ?? ""
        let time = b["time"] as? String ?? ""
        guard let start = Native.dayTime(date, time) else { reply(nil, "날짜가 맞지 않아요"); return }
        if time.isEmpty {
            ev.isAllDay = true
            ev.startDate = start
            ev.endDate = start
        } else {
            ev.isAllDay = false
            ev.startDate = start
            ev.endDate = start.addingTimeInterval(3600)
        }
        let notes = b["notes"] as? String ?? ""
        ev.notes = notes.isEmpty ? "DayROAD에서 만든 일정" : notes + "\n\nDayROAD에서 만든 일정"
        do {
            try store.save(ev, span: .thisEvent, commit: true)
            reply(["eventId": ev.eventIdentifier ?? ""], nil)
        } catch {
            Log.write("⚠️ 일정 저장 실패: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    func eventDelete(_ b: [String: Any], _ reply: @escaping Reply) {
        let id = b["eventId"] as? String ?? ""
        if let ev = store.event(withIdentifier: id) {
            try? store.remove(ev, span: .thisEvent, commit: true)
        }
        reply(["ok": true], nil)
    }

    // MARK: 미리 알림

    /// 'DayROAD' 목록 (없으면 만들어요)
    func reminderList(_ id: String) -> EKCalendar? {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { return nil }
        if !id.isEmpty, let c = store.calendar(withIdentifier: id), c.allowedEntityTypes.contains(.reminder) { return c }
        if let c = store.calendars(for: .reminder).first(where: { $0.title == "DayROAD" }) { return c }
        let c = EKCalendar(for: .reminder, eventStore: store)
        c.title = "DayROAD"
        c.cgColor = NSColor(srgbRed: 0xD9 / 255, green: 0x57 / 255, blue: 0x2B / 255, alpha: 1).cgColor
        let src = store.defaultCalendarForNewReminders()?.source
            ?? store.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") })
            ?? store.sources.first(where: { $0.sourceType == .local })
        guard let s = src else { return store.defaultCalendarForNewReminders() }
        c.source = s
        do {
            try store.saveCalendar(c, commit: true)
            Log.write("미리 알림에 DayROAD 목록을 만들었어요 (\(s.title))")
            return c
        } catch {
            Log.write("⚠️ 미리 알림 목록을 만들지 못했어요: \(error.localizedDescription)")
            return store.defaultCalendarForNewReminders()
        }
    }

    func reminderUpsert(_ b: [String: Any], _ reply: @escaping Reply) {
        guard let list = reminderList(b["listId"] as? String ?? "") else { reply(nil, "미리 알림 접근이 허락되지 않았어요"); return }
        let id = b["reminderId"] as? String ?? ""
        let r = (id.isEmpty ? nil : store.calendarItem(withIdentifier: id) as? EKReminder) ?? EKReminder(eventStore: store)
        if r.calendar == nil { r.calendar = list }
        r.title = b["title"] as? String ?? ""
        let notes = b["notes"] as? String ?? ""
        r.notes = notes.isEmpty ? nil : notes
        let date = b["date"] as? String ?? ""
        let time = b["time"] as? String ?? ""
        if let d = Native.day(date) {
            var comps = Calendar.current.dateComponents([.year, .month, .day], from: d)
            let p = time.split(separator: ":").compactMap { Int($0) }
            if p.count == 2 { comps.hour = p[0]; comps.minute = p[1] }
            r.dueDateComponents = comps
        } else {
            r.dueDateComponents = nil
        }
        r.isCompleted = b["done"] as? Bool ?? false
        do {
            try store.save(r, commit: true)
            reply(["reminderId": r.calendarItemIdentifier, "listId": list.calendarIdentifier], nil)
        } catch {
            Log.write("⚠️ 미리 알림 저장 실패: \(error.localizedDescription)")
            reply(nil, error.localizedDescription)
        }
    }

    func reminderDelete(_ b: [String: Any], _ reply: @escaping Reply) {
        let id = b["reminderId"] as? String ?? ""
        if let r = store.calendarItem(withIdentifier: id) as? EKReminder {
            try? store.remove(r, commit: true)
        }
        reply(["ok": true], nil)
    }

    func reminderFetch(_ b: [String: Any], _ reply: @escaping Reply) {
        guard let list = reminderList(b["listId"] as? String ?? "") else { reply(["items": []], nil); return }
        let since = Calendar.current.date(byAdding: .day, value: -21, to: Date())
        let p1 = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        let p2 = store.predicateForCompletedReminders(withCompletionDateStarting: since, ending: nil, calendars: [list])
        let map: (EKReminder) -> [String: Any] = { r in
            var date = "", time = ""
            if let c = r.dueDateComponents, let d = Calendar.current.date(from: c) {
                date = Native.dayFmt.string(from: d)
                if c.hour != nil { time = Native.timeFmt.string(from: d) }
            }
            return ["id": r.calendarItemIdentifier, "title": r.title ?? "", "done": r.isCompleted, "date": date, "time": time, "notes": r.notes ?? ""]
        }
        store.fetchReminders(matching: p1) { open in
            self.store.fetchReminders(matching: p2) { done in
                let items = (open ?? []).map(map) + (done ?? []).map(map)
                DispatchQueue.main.async { reply(["items": items, "listId": list.calendarIdentifier], nil) }
            }
        }
    }

    // MARK: 알림

    func requestNotify(_ reply: @escaping Reply) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
            UNUserNotificationCenter.current().getNotificationSettings { s in
                DispatchQueue.main.async { reply(["status": Native.notifyName(s.authorizationStatus)], nil) }
            }
        }
    }

    /// 화면이 정한 알림 목록으로 예약을 통째로 바꿔요 (앞으로 8일, 60개까지)
    func notifySchedule(_ b: [String: Any], _ reply: @escaping Reply) {
        let items = (b["items"] as? [[String: Any]]) ?? []
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { s in
            let go = {
                center.getPendingNotificationRequests { pending in
                    let old = pending.map { $0.identifier }.filter { $0.hasPrefix("dr-") }
                    center.removePendingNotificationRequests(withIdentifiers: old)
                    var n = 0
                    for it in items.prefix(60) {
                        guard let id = it["id"] as? String, let at = it["at"] as? String else { continue }
                        let parts = at.split(separator: "T").map(String.init)
                        guard parts.count == 2, let when = Native.dayTime(parts[0], parts[1]), when > Date() else { continue }
                        let c = UNMutableNotificationContent()
                        c.title = it["title"] as? String ?? "DayROAD"
                        c.body = it["body"] as? String ?? ""
                        c.sound = .default
                        let tid = id.count > 2 ? String(id.dropFirst(2)) : ""
                        c.userInfo = ["url": id.hasPrefix("m-") ? "dayroad://today" : "dayroad://task/\(tid)"]
                        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                        let req = UNNotificationRequest(identifier: "dr-" + id, content: c, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
                        center.add(req, withCompletionHandler: nil)
                        n += 1
                    }
                    if n > 0 || !old.isEmpty { Log.write("알림 예약 \(n)개") }
                    center.getNotificationSettings { s2 in
                        DispatchQueue.main.async { reply(["status": Native.notifyName(s2.authorizationStatus), "count": n], nil) }
                    }
                }
            }
            if s.authorizationStatus == .notDetermined && !items.isEmpty {
                center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in go() }
            } else {
                go()
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let s = response.notification.request.content.userInfo["url"] as? String, let u = URL(string: s) {
            DispatchQueue.main.async { self.onOpenURL?(u) }
        }
        completionHandler()
    }

    // MARK: 맥 설정 열기

    func openPrivacy(_ pane: String) {
        let urls: [String: String] = [
            "calendars": "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "reminders": "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
            "notifications": "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
        ]
        if let s = urls[pane], let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}
