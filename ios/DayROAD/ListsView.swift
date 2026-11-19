import SwiftUI

// ⑤ 모아 보기 (확정 시안): 마감 다가옴 · 반복하는 일 · 언젠가 · 끝낸 일 카드 → 아래 목록, 분류별 보기 · 분류 추가/고치기/지우기

struct ListsView: View {
    @EnvironmentObject var store: Store
    @State private var pick = "due"
    @State private var catPick: String?       // 분류 하나 보기
    @State private var catForm: CatForm?
    @State private var catDelete: DCategory?

    struct CatForm: Identifiable {
        var id: String { cat?.id ?? "new" }
        var cat: DCategory?
    }

    var body: some View {
        let open = store.d.tasks.filter { !$0.done }
        let due = open.filter { !$0.due.isEmpty }.sorted { $0.due < $1.due }
        let rep = open.filter { !$0.rep.isEmpty }.sorted { ($0.date.isEmpty ? $0.weekOf : $0.date) < ($1.date.isEmpty ? $1.weekOf : $1.date) }
        let some = open.filter { $0.bucket == "someday" }.sorted { $0.order < $1.order }
        let done = doneList()
        let cards: [(String, String, String, Int)] = [
            ("due", "마감 다가옴", "clock", due.count), ("rep", "반복하는 일", "repeat", rep.count),
            ("some", "언젠가", "text.alignleft", some.count), ("done", "끝낸 일", "checkmark", done.count),
        ]
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("모아 보기").font(F.serif(34)).foregroundStyle(T.ink).padding(.top, 8).accessibilityAddTraits(.isHeader)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(cards, id: \.0) { c in
                            let on = catPick == nil && pick == c.0
                            Button { pick = c.0; catPick = nil } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: c.2).font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(c.0 == "done" ? T.doneText : (c.0 == "due" ? T.accentText : T.ink))
                                            .frame(width: 32, height: 32)
                                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(c.0 == "done" ? T.doneSoft : (c.0 == "due" ? T.accentSoft : T.chip)))
                                        Spacer()
                                        Text("\(c.3)").font(F.serif(24)).foregroundStyle(T.ink)
                                    }
                                    Text(c.1).font(F.sans(14.5, .bold)).foregroundStyle(T.ink)
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(on ? T.accentSoft : T.field))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? T.accent : T.line, lineWidth: 1.5))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(c.1) \(c.3)개")
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }

                    let sel: (String, [DTask]) = {
                        if let cid = catPick, let c = store.cat(cid) {
                            return (c.name, Store.sortDay(open.filter { $0.cat == cid }).sorted { order($0) < order($1) })
                        }
                        switch pick {
                        case "rep": return ("반복하는 일", rep)
                        case "some": return ("언젠가", some)
                        case "done": return ("끝낸 일", done)
                        default: return ("마감 다가옴", due)
                        }
                    }()
                    VStack(alignment: .leading, spacing: 0) {
                        SectionTitle(text: sel.0).padding(.top, 10).padding(.bottom, 2)
                        if pick == "some" && catPick == nil {
                            QuickAddField(defaults: somedayDefaults, placeholder: "언젠가 할 일").padding(.vertical, 8)
                        }
                        if sel.1.isEmpty { Text("비어 있어요").font(F.sans(13.5)).foregroundStyle(T.muted).padding(.vertical, 12) }
                        ForEach(sel.1) { t in
                            Rectangle().fill(T.line2).frame(height: 1)
                            TaskRow(t: t, showDay: true, compact: true)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 4)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.field))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.line, lineWidth: 1))

                    SectionTitle(text: "분류").padding(.top, 6)
                    Card {
                        ForEach(store.cats) { c in
                            let n = open.filter { $0.cat == c.id }.count
                            Button { catPick = c.id } label: {
                                HStack(spacing: 12) {
                                    Circle().fill(T.cat(c.color)).frame(width: 11, height: 11)
                                    Text(c.name).font(F.sans(15)).foregroundStyle(T.ink)
                                    Spacer()
                                    Text(n > 0 ? "\(n)" : "").font(F.sans(13)).foregroundStyle(T.muted)
                                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(T.check)
                                }
                                .padding(.horizontal, 14).frame(minHeight: 50)
                                .background(catPick == c.id ? T.accentSoft : .clear)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { catForm = CatForm(cat: c) } label: { Label("이름 · 색 바꾸기", systemImage: "pencil") }
                                Button(role: .destructive) { catDelete = c } label: { Label("분류 지우기", systemImage: "trash") }
                            }
                            .accessibilityHint("길게 누르면 이름 · 색을 바꾸거나 지울 수 있어요")
                            Rectangle().fill(T.line2).frame(height: 1)
                        }
                        Button { catForm = CatForm(cat: nil) } label: {
                            Label("분류 추가", systemImage: "plus").font(F.sans(15, .semibold)).foregroundStyle(T.accentText)
                                .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("분류를 길게 누르면 이름 · 색을 바꾸거나 지울 수 있어요").font(F.sans(12)).foregroundStyle(T.muted)
                }
                .padding(.horizontal, 16).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(T.paper)
            ToastView()
        }
        .sheet(item: $catForm) { f in CatFormSheet(cat: f.cat).presentationDetents([.medium]) }
        .confirmationDialog("‘\(catDelete?.name ?? "")’ 분류를 지울까요?", isPresented: Binding(get: { catDelete != nil }, set: { if !$0 { catDelete = nil } }), titleVisibility: .visible) {
            Button("지우기", role: .destructive) {
                if let c = catDelete { store.deleteCat(c.id); if catPick == c.id { catPick = nil } }
                catDelete = nil
            }
        } message: {
            let n = store.d.tasks.filter { $0.cat == catDelete?.id }.count
            Text(n > 0 ? "이 분류의 할 일 \(n)개는 지워지지 않고 ‘분류 없음’이 돼요." : "")
        }
    }

    var somedayDefaults: DTask { var d = DTask(); d.bucket = "someday"; return d }

    func order(_ t: DTask) -> String {
        switch t.bucket {
        case "day": return t.date
        case "week": return t.weekOf
        default: return "9999"
        }
    }

    /// 끝낸 일: 최근 것부터, 반복하는 일은 한 번만 (마지막으로 끝낸 날 · 몇 번 끝냈는지)
    func doneList() -> [DTask] {
        var seen: [String: Int] = [:]
        var out: [DTask] = []
        for t in store.d.tasks.filter({ $0.done }).sorted(by: { ($0.doneAt, $0.updated) > ($1.doneAt, $1.updated) }) {
            if !t.rep.isEmpty {
                let k = t.title + "|" + t.rep + "|" + t.cat
                if seen[k] != nil { continue }
                seen[k] = 1
            }
            out.append(t)
            if out.count >= 200 { break }
        }
        return out
    }
}

struct CatFormSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    var cat: DCategory?
    @State private var name = ""
    @State private var color = "teal"
    @State private var err = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                TextField("예: 운동, 육아, 사역", text: $name)
                    .font(F.sans(16)).padding(.horizontal, 12).frame(minHeight: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(T.field))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line, lineWidth: 1.5))
                    .accessibilityLabel("분류 이름")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                    ForEach(Palette.keys, id: \.self) { k in
                        Button { color = k } label: {
                            Circle().fill(T.cat(k)).frame(width: 30, height: 30)
                                .overlay(Circle().stroke(color == k ? T.ink : .clear, lineWidth: 2.5).padding(-4))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Palette.names[k] ?? k) 고르기")
                        .accessibilityAddTraits(color == k ? .isSelected : [])
                    }
                }
                if !err.isEmpty { Text(err).font(F.sans(13)).foregroundStyle(T.accentText) }
                Spacer()
            }
            .padding(18)
            .background(T.paper)
            .navigationTitle(cat == nil ? "새 분류" : "분류 바꾸기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("취소") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(cat == nil ? "추가" : "저장") {
                        if store.saveCat(id: cat?.id, name: name, color: color) != nil { dismiss() } else {
                            err = name.trimmingCharacters(in: .whitespaces).isEmpty ? "분류 이름을 적어 주세요" : "같은 이름의 분류가 이미 있어요"
                        }
                    }
                    .fontWeight(.bold).foregroundStyle(T.accentText)
                }
            }
        }
        .onAppear {
            name = cat?.name ?? ""
            color = cat?.color ?? store.nextColor()
        }
    }
}
