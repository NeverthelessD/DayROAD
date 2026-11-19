import SwiftUI

// ① 오늘 (확정 시안): 날짜 · 진행 · 7일 띠 · 캘린더 일정 · 빠른 추가 · 넘어옴 안내 · 남은 일 · 끝낸 일
// 7일 띠에서 다른 날을 누르면 그 날을 보여 주고, 빠른 추가도 그 날에 넣어요.

struct TodayView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var cloud: Cloud
    @EnvironmentObject var cal: Cal
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let day = router.viewDate
        let isToday = day == Day.today()
        let all = store.d.tasks.filter { $0.bucket == "day" && $0.date == day }
        let open = Store.sortDay(all.filter { !$0.done })
        let done = all.filter { $0.done }.sorted { $0.updated > $1.updated }
        let carried = open.filter { !$0.carriedFrom.isEmpty }.count
        let p = Day.parts(day)

        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Logo(size: 28)
                        Text("DayROAD").font(F.serif(20)).foregroundStyle(T.ink)
                        Spacer()
                        SyncChip()
                    }
                    .frame(minHeight: 44)

                    HStack(alignment: .bottom, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(String(p.y))년 \(p.m)월").font(F.sans(13, .medium)).foregroundStyle(T.muted)
                            Text("\(p.d)일 \(Day.dowNames[Day.weekday(day)])요일").font(F.serif(34)).foregroundStyle(T.ink)
                                .accessibilityAddTraits(.isHeader)
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 6) {
                            if !isToday {
                                Button { router.viewDate = Day.today() } label: {
                                    Text("오늘로").font(F.sans(13, .semibold)).foregroundStyle(T.accentText)
                                        .padding(.horizontal, 12).frame(minHeight: 32)
                                        .background(Capsule().stroke(T.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                            (Text("\(all.count)개").font(F.sans(12.5, .bold)).foregroundColor(T.ink)
                             + Text(" 중 ").font(F.sans(12.5)).foregroundColor(T.muted)
                             + Text("\(done.count)개").font(F.sans(12.5, .bold)).foregroundColor(T.doneText)
                             + Text(" 끝냄").font(F.sans(12.5)).foregroundColor(T.muted))
                            ProgressBar(value: all.isEmpty ? 0 : done.count * 100 / all.count).frame(width: 120, height: 6)
                        }
                        .padding(.bottom, 6)
                    }

                    DayStrip()

                    if settings.calendarShow { EventChips(items: cal.events[day] ?? []) }

                    QuickAddField(base: isToday ? nil : day)

                    if isToday && carried > 0 {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right").font(.system(size: 14, weight: .bold))
                            Text("지난 날 못 끝낸 일 \(carried)개를 오늘로 가져왔어요").font(F.sans(13))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(T.carryFg)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.carryBg))
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle(text: "남은 일 · \(open.count)").padding(.bottom, 4)
                        if open.isEmpty {
                            Text(all.isEmpty ? "할 일이 없어요. 위 칸에 적어 보세요." : "다 끝냈어요!")
                                .font(F.sans(14)).foregroundStyle(T.muted).padding(.vertical, 14)
                        }
                        ForEach(open) { t in
                            TaskRow(t: t)
                            Divider().overlay(T.line2)
                        }
                    }

                    if !done.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            SectionTitle(text: "끝낸 일 · \(done.count)").padding(.bottom, 2)
                            ForEach(done) { t in TaskRow(t: t, compact: true) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(T.paper)
            ToastView()
        }
        .animation(.easeOut(duration: 0.2), value: Toast.shared.text)
    }
}

/// 위 오른쪽 'iCloud 맞춤' 표시 → 누르면 설정
struct SyncChip: View {
    @EnvironmentObject var cloud: Cloud
    @EnvironmentObject var router: Router
    @State private var now = Date()
    private let tick = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        let look: (String, String, Color) = {
            switch cloud.state {
            case .ok:
                let s = now.timeIntervalSince(cloud.last ?? now)
                return ("checkmark.icloud", s < 60 ? "맞춤 · 방금" : "맞춤 · \(Int(s / 60))분 전", T.done)
            case .waiting, .starting: return ("arrow.triangle.2.circlepath.icloud", "맞추는 중", T.muted)
            default: return ("exclamationmark.icloud", "확인 필요", T.accentText)
            }
        }()
        Button { router.tab = .settings } label: {
            HStack(spacing: 6) {
                Image(systemName: look.0).foregroundStyle(look.2)
                Text(look.1)
            }
            .font(F.sans(12.5, .semibold)).foregroundStyle(T.muted)
            .padding(.horizontal, 12).frame(minHeight: 44)
            .background(Capsule().fill(T.chip))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("iCloud \(look.1), 설정 열기")
        .onReceive(tick) { now = $0 }
    }
}
