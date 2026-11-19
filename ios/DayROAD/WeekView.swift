import SwiftUI

// ④ 이번 주 (확정 시안): 한 주 / 한 달 · 앞뒤 주 넘기기 · '이번 주 안에' 칸 · 날마다 칸(누르면 그 날에 바로 추가)

struct WeekView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    @EnvironmentObject var cal: Cal
    @EnvironmentObject var settings: AppSettings
    @State private var weekOf = ""
    @State private var monthOf = ""
    @State private var addDay: String?        // 그 날 칸에 빠른 추가 열기
    @State private var addWeek = false
    @State private var pickDay: String?       // 한 달 보기에서 고른 날

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    Seg(options: [(false, "한 주"), (true, "한 달")], value: $router.month, label: "보는 범위")
                    if router.month { monthBody } else { weekBody }
                }
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(T.paper)
            ToastView()
        }
        .onAppear { fix() }
        .onChange(of: store.weekStart) { _, _ in weekOf = Day.weekStartOf(weekOf.isEmpty ? Day.today() : weekOf, store.weekStart) }
    }

    func fix() {
        if weekOf.isEmpty { weekOf = Day.weekStartOf(Day.today(), store.weekStart) }
        if monthOf.isEmpty { monthOf = String(Day.today().prefix(8)) + "01" }
    }

    var header: some View {
        let wk = weekOf.isEmpty ? Day.weekStartOf(Day.today(), store.weekStart) : weekOf
        let mo = monthOf.isEmpty ? String(Day.today().prefix(8)) + "01" : monthOf
        let a = Day.parts(wk), b = Day.parts(Day.addDays(wk, 6))
        let thisWeek = wk == Day.weekStartOf(Day.today(), store.weekStart)
        let sub = router.month ? "\(String(Day.parts(mo).y))년" : (a.m == b.m ? "\(a.m)월 \(a.d)일 – \(b.d)일" : "\(a.m)월 \(a.d)일 – \(b.m)월 \(b.d)일")
        let big = router.month ? "\(Day.parts(mo).m)월" : (thisWeek ? "이번 주" : (wk < Day.weekStartOf(Day.today(), store.weekStart) ? "지난 주" : "다음 주"))
        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sub).font(F.sans(13, .medium)).foregroundStyle(T.muted)
                Text(big).font(F.serif(34)).foregroundStyle(T.ink).accessibilityAddTraits(.isHeader)
            }
            Spacer()
            HStack(spacing: 4) {
                navButton("chevron.left", router.month ? "지난달" : "지난주") { step(-1) }
                navButton("chevron.right", router.month ? "다음 달" : "다음 주") { step(1) }
            }
        }
    }

    func navButton(_ icon: String, _ label: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: icon).font(.system(size: 15, weight: .bold)).foregroundStyle(T.ink)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.field))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    func step(_ n: Int) {
        fix()
        if router.month {
            let p = Day.parts(monthOf)
            let d = Day.cal.date(from: DateComponents(year: p.y, month: p.m + n, day: 1))!
            monthOf = Day.fd(d)
            pickDay = nil
        } else {
            weekOf = Day.addDays(weekOf, 7 * n)
        }
    }

    // MARK: 한 주

    @ViewBuilder var weekBody: some View {
        let wk = weekOf.isEmpty ? Day.weekStartOf(Day.today(), store.weekStart) : weekOf
        let bucket = store.d.tasks.filter { $0.bucket == "week" && $0.weekOf == wk }.sorted { ($0.done ? 1 : 0, $0.order) < ($1.done ? 1 : 0, $1.order) }
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                (Text(wk == Day.weekStartOf(Day.today(), store.weekStart) ? "이번 주 안에" : "이 주 안에").font(F.sans(13.5, .bold)).foregroundColor(T.ink)
                 + Text(" · 날짜 없이 이 주에 할 일").font(F.sans(13, .semibold)).foregroundColor(T.muted))
                Spacer()
                addButton("이 주 안에 할 일 추가") { addWeek.toggle() }
            }
            if addWeek {
                QuickAddField(defaults: weekDefaults(wk), placeholder: "이 주 안에 할 일") { _ in }
                    .padding(.vertical, 6)
            }
            ForEach(bucket) { t in TaskRow(t: t, compact: true) }
            if bucket.isEmpty && !addWeek { Text("비어 있어요").font(F.sans(13)).foregroundStyle(T.muted).padding(.vertical, 8) }
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.side))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.line, lineWidth: 1))

        ForEach(0..<7, id: \.self) { i in
            dayBox(Day.addDays(wk, i))
        }
    }

    func weekDefaults(_ wk: String) -> DTask {
        var d = DTask()
        d.bucket = "week"
        d.weekOf = wk
        return d
    }

    func addButton(_ label: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            Image(systemName: "plus").font(.system(size: 17, weight: .bold)).foregroundStyle(T.accentText).frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    @ViewBuilder func dayBox(_ d: String) -> some View {
        let today = Day.today()
        let isToday = d == today
        let past = d < today
        let items = Store.sortDay(store.d.tasks.filter { $0.bucket == "day" && $0.date == d })
        let left = items.filter { !$0.done }.count
        let evs = settings.calendarShow ? (cal.events[d] ?? []) : []
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button { router.viewDate = d; router.tab = .today } label: {
                    HStack(spacing: 10) {
                        Text("\(Day.parts(d).d)").font(F.serif(22)).foregroundStyle(isToday ? T.accentText : (past ? T.muted : T.ink)).frame(minWidth: 28, alignment: .leading)
                        Text(Day.dowNames[Day.weekday(d)] + "요일").font(F.sans(13.5, .bold)).foregroundStyle(isToday ? T.accentText : T.muted)
                        if isToday {
                            Text("오늘").font(F.sans(11.5, .bold)).foregroundStyle(T.onAccent)
                                .padding(.horizontal, 8).padding(.vertical, 1)
                                .background(RoundedRectangle(cornerRadius: 6).fill(T.accent))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Day.mdw(d)) 오늘 화면에서 보기")
                Spacer()
                Text(items.isEmpty ? "" : (left > 0 ? "남은 일 \(left)개" : "다 끝냈어요")).font(F.sans(12)).foregroundStyle(T.muted)
                addButton("\(Day.md(d))에 할 일 추가") { addDay = addDay == d ? nil : d }
                    .padding(.trailing, -8)
            }
            if !evs.isEmpty { EventChips(items: evs).padding(.bottom, 6) }
            if addDay == d {
                QuickAddField(base: d, placeholder: "\(Day.md(d))에 할 일") { _ in }.padding(.vertical, 6)
            }
            ForEach(items) { t in
                Rectangle().fill(T.line2).frame(height: 1)
                TaskRow(t: t, compact: true)
            }
            if items.isEmpty && addDay != d { Text("비어 있어요").font(F.sans(13)).foregroundStyle(T.muted).padding(.bottom, 10) }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(isToday ? T.accentSoft : T.field))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isToday ? T.accent : T.line, lineWidth: 1.5))
    }

    // MARK: 한 달

    @ViewBuilder var monthBody: some View {
        let mo = monthOf.isEmpty ? String(Day.today().prefix(8)) + "01" : monthOf
        let first = Day.weekStartOf(mo, store.weekStart)
        let m = Day.parts(mo).m
        let w0 = store.weekStart == "sun" ? 0 : 1
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Day.dowNames[(i + w0) % 7]).font(F.sans(12, .semibold)).foregroundStyle(T.muted).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { r in
                let rowStart = Day.addDays(first, r * 7)
                if r < 5 || Day.parts(rowStart).m == m {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { c in monthCell(Day.addDays(rowStart, c), inMonth: Day.parts(Day.addDays(rowStart, c)).m == m) }
                    }
                }
            }
        }
        let sel = pickDay ?? (Day.parts(Day.today()).m == m ? Day.today() : mo)
        let items = Store.sortDay(store.d.tasks.filter { $0.bucket == "day" && $0.date == sel })
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(Day.mdw(sel)).font(F.sans(15, .bold)).foregroundStyle(T.ink)
                Spacer()
                addButton("\(Day.md(sel))에 할 일 추가") { addDay = addDay == sel ? nil : sel }
            }
            if addDay == sel { QuickAddField(base: sel, placeholder: "\(Day.md(sel))에 할 일") { _ in }.padding(.vertical, 6) }
            ForEach(items) { t in TaskRow(t: t, compact: true) }
            if items.isEmpty { Text("비어 있어요").font(F.sans(13)).foregroundStyle(T.muted).padding(.vertical, 8) }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.field))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.line, lineWidth: 1))
    }

    func monthCell(_ d: String, inMonth: Bool) -> some View {
        let l = store.d.tasks.filter { $0.bucket == "day" && $0.date == d }
        let left = l.filter { !$0.done }.count
        let isToday = d == Day.today()
        let sel = d == pickDay
        return Button { pickDay = d } label: {
            VStack(spacing: 3) {
                Text("\(Day.parts(d).d)").font(F.serif(16)).foregroundStyle(isToday ? T.accentText : (inMonth ? T.ink : T.muted.opacity(0.6)))
                HStack(spacing: 2) {
                    ForEach(0..<min(3, l.count), id: \.self) { i in
                        Circle().fill(i < left ? T.accent : T.done).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(sel ? T.accentSoft : (isToday ? T.side : .clear)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(sel ? T.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Day.mdw(d)), 할 일 \(l.count)개, 남은 일 \(left)개")
    }
}
