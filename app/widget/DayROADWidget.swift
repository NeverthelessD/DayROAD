// DayROAD 위젯 (바탕화면 · 알림 센터)
// made by. Nevertheless_D
//
// 작게: 오늘 진행률 + 다음 할 일 · 중간: 오늘 할 일 4개 · 크게: 이번 주 막대 + 오늘 할 일 6개
// 체크박스를 누르면(ToggleTaskIntent) 앱을 열지 않아도 끝낸 일이 돼요. 위젯을 누르면 앱이 열려요.

import AppIntents
import SwiftUI
import WidgetKit

struct DayEntry: TimelineEntry {
    let date: Date
    let today: WToday
}

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry {
        DayEntry(date: Date(), today: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let data = WidgetFiles.load()
        if context.isPreview && (data == nil || data!.items.isEmpty) {
            completion(DayEntry(date: Date(), today: .sample))
        } else {
            completion(DayEntry(date: Date(), today: WToday.make(data)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let now = Date()
        let entry = DayEntry(date: now, today: WToday.make(WidgetFiles.load(), now: now))
        // 자정이 지나면 날짜를 바꿔 그리고, 그 사이에도 15분마다 다시 읽어요 (앱에서 바꾸면 앱이 바로 새로 그리게 해요)
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now)!).addingTimeInterval(5)
        let next = min(midnight, now.addingTimeInterval(15 * 60))
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "할 일 끝내기"
    static var description = IntentDescription("DayROAD 할 일을 끝낸 일로 표시하거나 되돌려요.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "할 일")
    var taskID: String

    @Parameter(title: "끝냄")
    var done: Bool

    init() {}

    init(taskID: String, done: Bool) {
        self.taskID = taskID
        self.done = done
    }

    func perform() async throws -> some IntentResult {
        WidgetFiles.toggle(id: taskID, done: done)
        return .result()
    }
}

struct DayWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) var family
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let p = WPalette.of(scheme)
        let fam: WFamily = family == .systemSmall ? .small : (family == .systemLarge ? .large : .medium)
        DayROADWidgetView(t: entry.today, family: fam, toggle: { item in
            AnyView(
                Button(intent: ToggleTaskIntent(taskID: item.id, done: !item.isDone)) {
                    WCheck(done: item.isDone, p: p)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isDone ? "다시 남은 일로" : "끝낸 일로 표시")
            )
        }, p: p)
        .containerBackground(for: .widget) { p.paper }
        .widgetURL(URL(string: fam == .large ? "dayroad://week" : "dayroad://today"))
    }
}

struct DayROADWidget: Widget {
    let kind = "DayROADWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayProvider()) { entry in
            DayWidgetView(entry: entry)
        }
        .configurationDisplayName("DayROAD")
        .description("오늘 할 일과 이번 주를 한눈에 보고, 눌러서 바로 끝낼 수 있어요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

@main
struct DayROADWidgets: WidgetBundle {
    var body: some Widget {
        DayROADWidget()
    }
}
