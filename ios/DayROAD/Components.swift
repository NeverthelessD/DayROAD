import SwiftUI

// 여러 화면이 같이 쓰는 조각: 할 일 줄 · 네모 칸 · 빠른 추가 · 7일 띠 · 캘린더 일정

struct CheckBox: View {
    var done: Bool
    var size: CGFloat = 24
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(done ? T.done : T.check, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).fill(done ? T.done : .clear))
            if done {
                Image(systemName: "checkmark").font(.system(size: size * 0.55, weight: .heavy)).foregroundStyle(T.onDone)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 할 일 한 줄. 네모를 누르면 끝내기, 나머지를 누르면 자세히 칸.
struct TaskRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router
    var t: DTask
    var showDay = false      // 날짜도 같이 보여 주기 (모아 보기 등)
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { store.toggle(t.id) }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                CheckBox(done: t.done, size: compact ? 22 : 24).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel(t.done ? "\(t.title) 다시 남은 일로" : "\(t.title) 끝내기")

            Button { router.detail = t.id } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(t.title)
                        .font(F.sans(compact ? 15 : 16, t.done ? .regular : .medium))
                        .foregroundStyle(t.done ? T.muted : T.ink)
                        .strikethrough(t.done, color: T.muted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !t.done || showDay { meta }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, compact ? 8 : 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !t.done && t.progress > 0 {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(t.progress)%").font(F.sans(12, .semibold)).foregroundStyle(T.doneText)
                    ProgressBar(value: t.progress).frame(width: 52, height: 5)
                }
                .accessibilityElement(children: .combine)
            }
            if t.star && !t.done {
                Image(systemName: "star.fill").font(.system(size: 15)).foregroundStyle(T.accent).padding(.leading, 6)
                    .accessibilityLabel("중요")
            }
        }
        .contextMenu {
            Button { store.toggle(t.id) } label: { Label(t.done ? "다시 남은 일로" : "끝냈어요", systemImage: "checkmark.square") }
            if !t.done { Button { store.toTomorrow(t.id) } label: { Label("내일로 미루기", systemImage: "arrow.right") } }
            Button(role: .destructive) {
                let copy = t
                store.delete(t.id)
                Toast.shared.show("‘\(copy.title)’ 지웠어요", undo: { store.restore(copy) })
            } label: { Label("지우기", systemImage: "trash") }
        }
    }

    @ViewBuilder var meta: some View {
        let c = store.cat(t.cat)
        FlowRow(spacing: 9, lineSpacing: 5) {
            if showDay { Text(whenText).font(F.sans(12.5)).foregroundStyle(T.muted) }
            if !t.time.isEmpty { Pill(text: Day.time(t.time)) }
            if !t.due.isEmpty && !t.done {
                let n = Day.between(Day.today(), t.due)
                Pill(text: "\(Day.dueBadge(t.due)) · \(n <= 0 ? "오늘까지" : Day.rel(t.due, ws: store.weekStart) + "까지")",
                     bg: n <= 1 ? T.accentSoft : T.chip, fg: n <= 1 ? T.accentText : T.ink, bold: true)
            }
            if let c = c {
                HStack(spacing: 5) {
                    Circle().fill(T.cat(c.color)).frame(width: 8, height: 8)
                    Text(c.name).font(F.sans(12.5)).foregroundStyle(T.muted)
                }
            }
            if !t.rep.isEmpty {
                Label(repText(t.rep), systemImage: "repeat").font(F.sans(12.5)).foregroundStyle(T.muted).labelStyle(TightLabel())
            }
            if !t.alarm.isEmpty && !t.done {
                Label(Day.time(t.alarm), systemImage: "bell").font(F.sans(12.5)).foregroundStyle(T.muted).labelStyle(TightLabel())
            }
            if !t.carriedFrom.isEmpty && !t.done {
                Pill(text: "\(Day.parts(t.carriedFrom).m)/\(Day.parts(t.carriedFrom).d)에서 넘어옴", bg: T.carryBg, fg: T.carryFg, bold: true)
            }
            if !t.log.isEmpty && compact {
                Label("\(t.log.count)", systemImage: "text.alignleft").font(F.sans(12)).foregroundStyle(T.muted).labelStyle(TightLabel())
            }
        }
    }

    var whenText: String {
        switch t.bucket {
        case "week": return t.weekOf == Day.weekStartOf(Day.today(), store.weekStart) ? "이번 주 안에" : "\(Day.md(t.weekOf)) 주"
        case "someday": return "언젠가"
        default: return Day.rel(t.date, ws: store.weekStart)
        }
    }
}

func repText(_ r: String) -> String {
    ["daily": "매일", "weekdays": "평일", "weekly": "매주", "monthly": "매달"][r] ?? ""
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon.imageScale(.small); configuration.title }
    }
}

struct ProgressBar: View {
    var value: Int
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(T.track)
                Capsule().fill(T.done).frame(width: g.size.width * CGFloat(max(0, min(100, value))) / 100)
            }
        }
        .accessibilityLabel("진행 \(value)%")
    }
}

/// 줄이 넘치면 다음 줄로 (표시 여러 개)
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > w { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += sz.width + spacing
            maxX = max(maxX, x - spacing)
            lineH = max(lineH, sz.height)
        }
        return CGSize(width: min(maxX, w), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y + (lineH > 0 ? 0 : 0)), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
        }
    }
}

/// 빠른 추가 칸: 적고 '추가' 또는 엔터. 알아들은 것(날짜 · 시간 · 마감 · 반복 · 분류 · 중요)을 아래에 보여 주고, × 로 뺄 수 있어요.
struct QuickAddField: View {
    @EnvironmentObject var store: Store
    var base: String? = nil              // 이 날에 넣기 (없으면 오늘)
    var defaults: DTask? = nil           // 이번 주 안에 · 언젠가 칸에서 넣을 때
    var placeholder = "할 일 적기 — 예: 금요일까지 보고서"
    var onAdded: ((DTask) -> Void)? = nil
    @State private var text = ""
    @State private var skip: Set<String> = []
    @FocusState private var focused: Bool

    var parsed: Quick { QuickParse.parse(text, cats: store.cats, ws: store.weekStart, base: base, skip: skip) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 17, weight: .semibold)).foregroundStyle(T.accentText).padding(.leading, 14)
                TextField(placeholder, text: $text)
                    .font(F.sans(15.5))
                    .foregroundStyle(T.ink)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(add)
                    .frame(minHeight: 44)
                    .accessibilityLabel("새 할 일")
                Button(action: add) {
                    Text("추가").font(F.sans(14.5, .semibold)).foregroundStyle(T.onAccent)
                        .padding(.horizontal, 16).frame(minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(T.accent))
                }
                .buttonStyle(.plain)
                .padding(5)
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.field))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(focused ? T.accent : T.line, lineWidth: 1.5))

            let p = parsed
            if !text.isEmpty && (!p.chips.isEmpty || !skip.isEmpty) {
                FlowRow(spacing: 6, lineSpacing: 6) {
                    Text("알아들은 것").font(F.sans(12.5)).foregroundStyle(T.muted)
                    ForEach(p.chips) { c in
                        Button { skip.insert(c.k) } label: {
                            HStack(spacing: 4) {
                                Text(c.label)
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                            }
                            .font(F.sans(12.5, .semibold)).foregroundStyle(T.accentText)
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(T.accentSoft))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(c.label) 빼기")
                    }
                }
            }
        }
        .onChange(of: text) { _, v in if v.isEmpty { skip = [] } }
    }

    func add() {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { focused = false; return }
        var d = defaults
        if d == nil, let b = base { var x = DTask(); x.bucket = "day"; x.date = b; d = x }
        if let t = store.add(parsed, defaults: d) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onAdded?(t)
        }
        text = ""
        skip = []
    }
}

/// 7일 띠 (오늘 화면 위)
struct DayStrip: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var router: Router

    var body: some View {
        let today = Day.today()
        let ws = Day.weekStartOf(router.viewDate, store.weekStart)
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                let d = Day.addDays(ws, i)
                let sel = d == router.viewDate
                let isToday = d == today
                let n = store.d.tasks.filter { $0.bucket == "day" && $0.date == d }.count
                Button { withAnimation(.easeOut(duration: 0.15)) { router.viewDate = d } } label: {
                    VStack(spacing: 1) {
                        Text(Day.dowNames[Day.weekday(d)]).font(F.sans(11.5, .semibold)).foregroundStyle(sel ? T.accentText : T.muted)
                        Text("\(Day.parts(d).d)").font(F.serif(18)).foregroundStyle(sel ? T.accentText : (isToday ? T.accentText : T.ink))
                        Text(n > 0 ? "\(n)개" : "—").font(F.sans(10.5)).foregroundStyle(T.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(sel ? T.accentSoft : T.field))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(sel ? T.accent : (isToday ? T.accentText.opacity(0.5) : T.line), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(Day.mdw(d)), 할 일 \(n)개\(isToday ? ", 오늘" : "")")
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if abs(v.translation.width) > abs(v.translation.height) {
                router.viewDate = Day.addDays(router.viewDate, v.translation.width < 0 ? 7 : -7)
            }
        })
    }
}

struct EventChips: View {
    var items: [EvItem]
    var body: some View {
        if !items.isEmpty {
            FlowRow(spacing: 6, lineSpacing: 6) {
                ForEach(items) { e in
                    HStack(spacing: 7) {
                        Circle().fill(e.color).frame(width: 8, height: 8)
                        if !e.time.isEmpty { Text(Day.time(e.time)).font(F.sans(13, .semibold)) }
                        Text(e.title).font(F.sans(13))
                    }
                    .foregroundStyle(T.ink)
                    .padding(.horizontal, 11).frame(minHeight: 32)
                    .background(Capsule().fill(T.chip))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct SectionTitle: View {
    var text: String
    var body: some View {
        Text(text).font(F.sans(13, .semibold)).foregroundStyle(T.muted).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 잠깐 떴다 사라지는 안내 (되돌리기 단추 포함)
@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published var text: String?
    @Published var undo: (() -> Void)?
    private var hide: Task<Void, Never>?

    func show(_ s: String, undo: (() -> Void)? = nil) {
        text = s
        self.undo = undo
        hide?.cancel()
        hide = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { withAnimation { self.text = nil; self.undo = nil } }
        }
    }
}

struct ToastView: View {
    @ObservedObject var toast = Toast.shared
    var body: some View {
        if let s = toast.text {
            HStack(spacing: 12) {
                Text(s).font(F.sans(14, .medium)).foregroundStyle(T.paper)
                if let u = toast.undo {
                    Button("되돌리기") { u(); toast.text = nil; toast.undo = nil }
                        .font(F.sans(14, .bold)).foregroundStyle(T.accentSoft)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(Capsule().fill(T.ink))
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
