import SwiftUI

// ③ 할 일 자세히 (아래에서 올라오는 창): 분류 · 이름 · 날짜 · 언제까지 · 시간 · 알림 · 반복 · 중요 · 진행 % · 기록 남기기/고치기
// 바꾸면 바로 저장돼요 (맥에도 몇 초 안에 보여요).

struct DetailSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let id: String

    @State private var title = ""
    @State private var memo = ""
    @State private var editing: Int? = nil
    @State private var editText = ""
    @State private var picker: PickerKind?
    @State private var confirmDelete = false
    @FocusState private var titleFocus: Bool

    enum PickerKind: String, Identifiable { case date, due, time, alarm; var id: String { rawValue } }

    var body: some View {
        if let t = store.task(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header(t)
                    TextField("할 일 이름", text: $title, axis: .vertical)
                        .font(F.serif(26)).foregroundStyle(T.ink)
                        .focused($titleFocus)
                        .submitLabel(.done)
                        .onSubmit { saveTitle(t) }
                        .onChange(of: titleFocus) { _, f in if !f { saveTitle(t) } }
                        .accessibilityLabel("할 일 이름")
                    fields(t)
                    progress(t)
                    logList(t)
                    buttons(t)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 30)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(T.paper)
            .onAppear { title = t.title }
            .sheet(item: $picker) { k in pickerSheet(k, t).presentationDetents([.medium, .large]) }
            .confirmationDialog("‘\(t.title)’\(Fmt.eul(t.title)) 지울까요?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("지우기", role: .destructive) {
                    let copy = t
                    dismiss()
                    store.delete(t.id)
                    Toast.shared.show("‘\(copy.title)’ 지웠어요", undo: { store.restore(copy) })
                }
                Button("취소", role: .cancel) {}
            }
        } else {
            VStack(spacing: 12) {
                Text("이 할 일은 지워졌어요").font(F.sans(16, .medium)).foregroundStyle(T.muted)
                Button("닫기") { dismiss() }.font(F.sans(15, .semibold)).foregroundStyle(T.accentText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(T.paper)
        }
    }

    func edit(_ t: DTask, _ f: (inout DTask) -> Void) {
        var x = t
        f(&x)
        store.update(x)
    }

    func saveTitle(_ t: DTask) {
        let s = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { title = t.title; return }
        if s != t.title { edit(t) { $0.title = s } }
    }

    // MARK: 위: 분류 · 넘어옴 · 닫기

    @ViewBuilder func header(_ t: DTask) -> some View {
        HStack(spacing: 8) {
            Menu {
                // 아이폰 메뉴는 아이콘 색을 지워서, 분류 색 점을 그림(원래 색 그대로)으로 넣어요
                Picker("분류", selection: Binding(get: { t.cat }, set: { v in edit(t) { $0.cat = v } })) {
                    Text("분류 없음").tag("")
                    ForEach(store.cats) { c in
                        Label { Text(c.name) } icon: { Image(uiImage: Dot.image(c.color, dark: scheme == .dark)) }.tag(c.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    if let c = store.cat(t.cat) {
                        Circle().fill(T.cat(c.color)).frame(width: 9, height: 9)
                        Text(c.name)
                    } else {
                        Text("분류 고르기")
                    }
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                }
                .font(F.sans(13.5, .semibold)).foregroundStyle(T.muted)
                .frame(minHeight: 44)
            }
            if !t.carriedFrom.isEmpty && !t.done {
                Pill(text: "\(Day.parts(t.carriedFrom).m)/\(Day.parts(t.carriedFrom).d)에서 넘어옴", bg: T.carryBg, fg: T.carryFg, bold: true)
            }
            Spacer()
            Button { saveTitle(t); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(T.muted)
                    .frame(width: 30, height: 30).background(Circle().fill(T.chip))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("닫기")
        }
    }

    // MARK: 칸들

    @ViewBuilder func fields(_ t: DTask) -> some View {
        Card {
            row(icon: "calendar", label: "날짜") {
                Menu {
                    Button("오늘") { edit(t) { $0.bucket = "day"; $0.date = Day.today() } }
                    Button("내일") { edit(t) { $0.bucket = "day"; $0.date = Day.addDays(Day.today(), 1) } }
                    Button("날짜 고르기…") { picker = .date }
                    Divider()
                    Button("이번 주 안에") { edit(t) { $0.bucket = "week"; $0.weekOf = Day.weekStartOf(Day.today(), store.weekStart) } }
                    Button("다음 주 안에") { edit(t) { $0.bucket = "week"; $0.weekOf = Day.addDays(Day.weekStartOf(Day.today(), store.weekStart), 7) } }
                    Button("언젠가") { edit(t) { $0.bucket = "someday" } }
                } label: {
                    valueBox(whenText(t))
                }
            }
            divider
            row(icon: "clock", label: "언제까지") {
                Button { picker = .due } label: {
                    if t.due.isEmpty { valueBox("정하지 않음") } else {
                        let n = Day.between(Day.today(), t.due)
                        valueBox("\(Day.mdw(t.due)) · \(Day.dueBadge(t.due))", bg: n <= 1 ? T.accentSoft : T.paper, fg: n <= 1 ? T.accentText : T.ink, border: n <= 1)
                    }
                }
                .buttonStyle(.plain)
            }
            if t.bucket == "day" {
                divider
                row(icon: "timer", label: "시간") {
                    Button { picker = .time } label: { valueBox(t.time.isEmpty ? "정하지 않음" : Day.time(t.time)) }.buttonStyle(.plain)
                }
                divider
                row(icon: "bell", label: "알림") {
                    Button { picker = .alarm } label: { valueBox(t.alarm.isEmpty ? "없음" : Day.time(t.alarm)) }.buttonStyle(.plain)
                }
            }
            if t.bucket != "someday" {
                divider
                VStack(alignment: .leading, spacing: 10) {
                    Label("반복", systemImage: "repeat").font(F.sans(15)).foregroundStyle(T.ink).labelStyle(IconLabel())
                    let opts: [(String, String)] = t.bucket == "week" ? [("", "안 함"), ("weekly", "매주")]
                        : [("", "안 함"), ("daily", "매일"), ("weekdays", "평일"), ("weekly", "매주"), ("monthly", "매달")]
                    Seg(options: opts, value: Binding(get: { t.rep }, set: { v in edit(t) { $0.rep = v } }), label: "반복")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            divider
            row(icon: "star", label: "중요") {
                Toggle("중요", isOn: Binding(get: { t.star }, set: { v in edit(t) { $0.star = v } })).labelsHidden().tint(T.accent)
            }
        }
    }

    var divider: some View { Rectangle().fill(T.line2).frame(height: 1) }

    func row<V: View>(icon: String, label: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(spacing: 10) {
            Label(label, systemImage: icon).font(F.sans(15)).foregroundStyle(T.ink).labelStyle(IconLabel())
            Spacer()
            v()
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
    }

    func valueBox(_ s: String, bg: Color = T.paper, fg: Color = T.ink, border: Bool = false) -> some View {
        Text(s).font(F.sans(14, .semibold)).foregroundStyle(fg)
            .padding(.horizontal, 12).frame(minHeight: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(bg))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(border ? .clear : T.line, lineWidth: 1))
    }

    func whenText(_ t: DTask) -> String {
        switch t.bucket {
        case "week": return t.weekOf == Day.weekStartOf(Day.today(), store.weekStart) ? "이번 주 안에" : "\(Day.md(t.weekOf)) 주 안에"
        case "someday": return "언젠가"
        default:
            let r = Day.rel(t.date, ws: store.weekStart)
            return r.contains("월") ? r : "\(r) (\(Day.md(t.date)))"
        }
    }

    // MARK: 날짜 · 시간 고르기

    @ViewBuilder func pickerSheet(_ k: PickerKind, _ t: DTask) -> some View {
        let isTime = k == .time || k == .alarm
        let cur: String = { switch k { case .date: return t.date; case .due: return t.due; case .time: return t.time; case .alarm: return t.alarm } }()
        PickSheet(title: ["date": "날짜", "due": "언제까지", "time": "시간", "alarm": "알림"][k.rawValue]!, isTime: isTime, value: cur,
                  canClear: k != .date) { v in
            edit(t) { x in
                switch k {
                case .date: if let v = v { x.bucket = "day"; x.date = v }
                case .due: x.due = v ?? ""
                case .time: x.time = v ?? ""
                case .alarm: x.alarm = v ?? ""
                }
            }
            if k == .alarm, v != nil { Task { await Notify.shared.request() } }
        }
    }

    // MARK: 어디까지 했나요

    @ViewBuilder func progress(_ t: DTask) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("어디까지 했나요").font(F.sans(15, .bold)).foregroundStyle(T.ink)
                Spacer()
                Text("\(t.progress)%").font(F.sans(14, .bold)).foregroundStyle(T.doneText)
            }
            ProgressBar(value: t.progress).frame(height: 8)
            HStack(spacing: 5) {
                ForEach([0, 25, 50, 75, 100], id: \.self) { v in
                    let on = t.progress == v
                    Button { store.addLog(t.id, text: "", progress: v) } label: {
                        Text("\(v)%").font(F.sans(13.5, .semibold)).foregroundStyle(on ? T.onDone : T.ink)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? T.done : T.field))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(on ? T.done : T.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("오늘 한 만큼 적어 두기").font(F.sans(13)).foregroundStyle(T.muted).padding(.top, 4)
            HStack(alignment: .bottom, spacing: 6) {
                TextField("예: 2장까지 씀, 표 정리만 남음", text: $memo, axis: .vertical)
                    .lineLimit(2...6)
                    .font(F.sans(15)).foregroundStyle(T.ink)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.field))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.line, lineWidth: 1.5))
                    .accessibilityLabel("오늘 한 만큼 적어 두기")
                Button {
                    store.addLog(t.id, text: memo, progress: nil)
                    memo = ""
                } label: {
                    Text("남기기").font(F.sans(14, .semibold)).foregroundStyle(T.paper)
                        .padding(.horizontal, 14).frame(minHeight: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(T.ink))
                }
                .buttonStyle(.plain)
                .disabled(memo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @ViewBuilder func logList(_ t: DTask) -> some View {
        if !t.log.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(t.log.enumerated()), id: \.offset) { i, l in
                    HStack(alignment: .top, spacing: 10) {
                        Text(l.date == Day.today() ? "오늘" : Day.md(l.date)).font(F.sans(12.5)).foregroundStyle(T.muted)
                            .frame(width: 54, alignment: .leading).padding(.top, 2)
                        if editing == i {
                            VStack(alignment: .trailing, spacing: 6) {
                                TextField("기록", text: $editText, axis: .vertical)
                                    .font(F.sans(14.5)).padding(8)
                                    .background(RoundedRectangle(cornerRadius: 10).fill(T.field))
                                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.accent, lineWidth: 1.5))
                                    .accessibilityLabel("기록 고치기")
                                HStack(spacing: 6) {
                                    Button("지우기") { store.delLog(t.id, i); editing = nil }
                                        .font(F.sans(13, .semibold)).foregroundStyle(T.accentText).frame(minHeight: 36)
                                    Spacer()
                                    Button("취소") { editing = nil }.font(F.sans(13)).foregroundStyle(T.ink)
                                        .padding(.horizontal, 12).frame(minHeight: 36)
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line, lineWidth: 1))
                                    Button("저장") { store.editLog(t.id, i, text: editText); editing = nil }
                                        .font(F.sans(13, .semibold)).foregroundStyle(T.onAccent)
                                        .padding(.horizontal, 12).frame(minHeight: 36)
                                        .background(RoundedRectangle(cornerRadius: 9).fill(T.accent))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.text.isEmpty ? "(진행만 바꿈)" : l.text).font(F.sans(14.5)).foregroundStyle(T.ink)
                                Text("\(l.progress)%까지").font(F.sans(12, .semibold)).foregroundStyle(T.doneText)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button { editing = i; editText = l.text } label: {
                                Image(systemName: "pencil").font(.system(size: 15)).foregroundStyle(T.muted).frame(width: 40, height: 40)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, -8)
                            .accessibilityLabel("\(Day.md(l.date)) 기록 고치기")
                        }
                    }
                    .padding(.vertical, 8)
                    .overlay(alignment: .top) { Rectangle().fill(T.line2).frame(height: 1) }
                }
            }
        }
    }

    // MARK: 아래 단추

    @ViewBuilder func buttons(_ t: DTask) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggle(t.id)
                if !t.done { dismiss() }
            } label: {
                Text(t.done ? "다시 남은 일로" : "끝냈어요").font(F.sans(15, .bold)).foregroundStyle(t.done ? T.ink : T.onDone)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.done ? T.chip : T.done))
            }
            if !t.done && t.bucket != "someday" {
                Button { store.toTomorrow(t.id); dismiss(); Toast.shared.show("내일로 미뤘어요") } label: {
                    Text("내일로").font(F.sans(14.5)).foregroundStyle(T.ink)
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.line, lineWidth: 1))
                }
            }
            Button { confirmDelete = true } label: {
                Image(systemName: "trash").font(.system(size: 17)).foregroundStyle(T.accentText)
                    .frame(width: 50, height: 50)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.line, lineWidth: 1))
            }
            .accessibilityLabel("할 일 지우기")
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }
}

struct IconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.foregroundStyle(T.muted).frame(width: 20)
            configuration.title
        }
    }
}

/// 날짜 · 시간 고르는 작은 창
struct PickSheet: View {
    @Environment(\.dismiss) private var dismiss
    var title: String
    var isTime: Bool
    var value: String
    var canClear: Bool
    var done: (String?) -> Void
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if isTime {
                    DatePicker(title, selection: $date, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel).labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                    HStack(spacing: 6) {
                        ForEach(["09:00", "12:00", "15:00", "18:00", "21:00"], id: \.self) { s in
                            Button(Day.time(s).replacingOccurrences(of: ":00", with: "시")) { done(s); dismiss() }
                                .font(F.sans(13, .semibold)).foregroundStyle(T.ink)
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .background(RoundedRectangle(cornerRadius: 9).fill(T.chip))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)
                } else {
                    DatePicker(title, selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical).labelsHidden()
                        .environment(\.locale, Locale(identifier: "ko_KR"))
                        .tint(T.accent)
                        .padding(.horizontal)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 8)
            .background(T.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if canClear && !value.isEmpty {
                        Button("없애기") { done(nil); dismiss() }.foregroundStyle(T.accentText)
                    } else {
                        Button("취소") { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("정하기") { done(isTime ? Day.hm(date) : Day.fd(date)); dismiss() }.fontWeight(.bold).foregroundStyle(T.accentText)
                }
            }
        }
        .onAppear {
            if isTime { date = Day.at(Day.today(), value.isEmpty ? "09:00" : value) ?? Date() } else { date = Day.pd(value.isEmpty ? Day.today() : value) }
        }
    }
}
