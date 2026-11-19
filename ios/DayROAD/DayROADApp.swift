import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications
import WidgetKit

// DayROAD 아이폰 — 오늘 · 이번 주 할 일 (맥 DayROAD 와 iCloud Drive 로 같은 할 일을 봐요)
// made by. Nevertheless_D

@main
struct DayROADApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared
    @StateObject private var cloud = Cloud.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var router = Router.shared
    @StateObject private var cal = Cal.shared
    @StateObject private var notify = Notify.shared
    @Environment(\.scenePhase) private var phase

    static let refreshID = "com.neverthelessd.dayroad.iphone.refresh"

    init() {
        Demo.setup()
        Store.shared.carryOver = { AppSettings.shared.carryOver }
        Store.shared.afterCommit = {
            Cloud.shared.pushSoon()
            Notify.shared.scheduleSoon()
        }
        Log.write("DayROAD 아이폰 \(appVersion) 켜짐\(Demo.on ? " (시험 모드)" : "")")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(cloud)
                .environmentObject(settings)
                .environmentObject(router)
                .environmentObject(cal)
                .environmentObject(notify)
                .preferredColorScheme(settings.scheme)
                .onOpenURL { router.open($0) }
                .task { await Self.start() }
        }
        .onChange(of: phase) { _, p in
            switch p {
            case .active:
                Store.shared.tick()
                Cloud.shared.startTimer()
                Task { await Cloud.shared.sync("앞으로") }
                Cal.shared.load()
                Notify.shared.scheduleSoon()
                if let t = Router.pendingTask { Router.shared.detail = t; Router.pendingTask = nil }
            case .background:
                Cloud.shared.stopTimer()
                Self.scheduleRefresh()
            default: break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshID)) {
            await Self.backgroundRefresh()
        }
    }

    @MainActor
    static func start() async {
        if Demo.on {
            if Demo.flag("-selftest") {
                let r = SelfTest.run()
                try? r.write(to: Demo.docs.appendingPathComponent("selftest.txt"), atomically: true, encoding: .utf8)
                Log.write("규칙 시험:\n" + r)
            }
            if Demo.flag("-renderWidgets") { WidgetShots.render() }
        }
        Store.shared.tick()
        await Cloud.shared.sync("켬")
        Cal.shared.load()
        await Notify.shared.refreshStatus()
        if Demo.on, Demo.flag("-toggleFirst") {
            // 빌드 서버 시험: 첫 할 일을 끝내서 iCloud 파일에 쓰이는지 봐요
            if let t = Store.shared.d.tasks.first(where: { !$0.done && $0.id == "demo3" }) { Store.shared.toggle(t.id) }
        }
    }

    static func scheduleRefresh() {
        let r = BGAppRefreshTaskRequest(identifier: refreshID)
        r.earliestBeginDate = Date().addingTimeInterval(2 * 3600)
        try? BGTaskScheduler.shared.submit(r)
    }

    /// 뒤에서 가끔: iCloud 에서 맥이 바꾼 것을 받아 알림 · 위젯을 새로
    @MainActor
    static func backgroundRefresh() async {
        scheduleRefresh()
        Store.shared.tick()
        await Cloud.shared.sync("뒤에서")
        await Notify.shared.schedule()
        Store.shared.exportWidget()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["task"] as? String
        await MainActor.run {
            Router.shared.tab = .today
            if let id = id { Router.pendingTask = id; Router.shared.detail = id }
        }
    }
}

// MARK: - 화면 이동

enum Tab: String, CaseIterable { case today, week, lists, settings }

@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    static var pendingTask: String?

    @Published var tab: Tab = .today
    @Published var detail: String?        // 자세히 칸에 연 할 일
    @Published var viewDate = Day.today() // 오늘 탭에서 보고 있는 날
    @Published var month = false          // 이번 주 탭: 한 달 보기

    init() {
        if Demo.on {
            switch Demo.arg("-tab") {
            case "week": tab = .week
            case "month": tab = .week; month = true
            case "lists": tab = .lists
            case "settings": tab = .settings
            default: tab = .today
            }
            if Demo.flag("-detail") { detail = "demo4" }
        }
    }

    /// dayroad://today · dayroad://week · dayroad://task/<id> (위젯 · 알림)
    func open(_ url: URL) {
        guard url.scheme == "dayroad" else { return }
        switch url.host {
        case "week": tab = .week; month = false
        case "task": tab = .today; detail = url.pathComponents.dropFirst().first
        default: tab = .today; viewDate = Day.today()
        }
    }
}

var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0" }

// MARK: - 맨 바깥

struct RootView: View {
    @EnvironmentObject var cloud: Cloud
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: Store
    private let clock = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if !cloud.connected {
                ConnectView()
            } else {
                MainTabs()
            }
        }
        .background(T.paper.ignoresSafeArea())
        .onReceive(clock) { _ in
            let before = store.d.lastDay
            store.tick()
            if before != store.d.lastDay { router.viewDate = Day.today() }
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var store: Store

    var body: some View {
        TabView(selection: $router.tab) {
            TodayView().tag(Tab.today)
                .tabItem { Label("오늘", systemImage: "sun.max") }
            WeekView().tag(Tab.week)
                .tabItem { Label("이번 주", systemImage: "calendar") }
            ListsView().tag(Tab.lists)
                .tabItem { Label("모아 보기", systemImage: "list.bullet") }
            SettingsView().tag(Tab.settings)
                .tabItem { Label("설정", systemImage: "gearshape") }
        }
        .tint(T.accentText)
        .sheet(item: Binding(get: { router.detail.map { DetailID(id: $0) } }, set: { router.detail = $0?.id })) { d in
            DetailSheet(id: d.id)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

struct DetailID: Identifiable { var id: String }
