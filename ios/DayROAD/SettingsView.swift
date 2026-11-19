import SwiftUI
import UniformTypeIdentifiers

// ⑥ 설정 (확정 시안): 남은 사용 기간(7칸) · iCloud 맞춤 상태 · 할 일 · 알림 · 화면 · 한 주의 시작 · 버전 · 진단 · made by

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var cloud: Cloud
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var notify: Notify
    @EnvironmentObject var cal: Cal
    @ObservedObject private var upd = AppUpdate.shared
    @State private var pass = AppPass.read()
    @State private var pickTime: String?      // morning | due
    @State private var showDiag = false
    @State private var reconnect = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("설정").font(F.serif(34)).foregroundStyle(T.ink).padding(.top, 8).accessibilityAddTraits(.isHeader)
                passCard
                cloudCard
                if notify.status == .denied {
                    warn("알림이 꺼져 있어요", "할 일 알림 · 아침 알림을 받으려면 아이폰 설정에서 DayROAD 알림을 켜 주세요", "아이폰 설정 열기") {
                        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
                    }
                }
                SectionTitle(text: "할 일 · 알림").padding(.top, 6)
                Card {
                    toggleRow("못 끝낸 일 오늘로 가져오기", "자정이 지나면 어제 남은 일이 오늘로 와요", $settings.carryOver)
                    line
                    toggleRow("아침 알림", "오늘 할 일을 알려 줘요", Binding(get: { settings.morningOn }, set: { v in settings.morningOn = v; if v { ask() } }),
                              time: settings.morningOn ? ("morning", settings.morningTime) : nil)
                    line
                    toggleRow("마감 미리 알려 주기", "‘언제까지’가 정해진 일", Binding(get: { settings.dueOn }, set: { v in settings.dueOn = v; if v { ask() } }),
                              time: settings.dueOn ? ("due", settings.dueTime) : nil)
                    if settings.dueOn {
                        Seg(options: [(0, "당일"), (1, "하루 전"), (2, "이틀 전"), (3, "사흘 전")], value: $settings.dueDays, label: "며칠 전")
                            .padding(.horizontal, 14).padding(.bottom, 12)
                    }
                    line
                    toggleRow("아이폰 캘린더 일정 보여 주기", cal.allowed || !settings.calendarShow ? "오늘 · 이번 주 화면에 일정도 함께" : "캘린더 접근을 허락하면 보여요",
                              Binding(get: { settings.calendarShow }, set: { v in settings.calendarShow = v; if v { Task { await cal.request() } } else { cal.load() } }))
                }
                SectionTitle(text: "화면").padding(.top, 6)
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("화면 모드").font(F.sans(15, .medium)).foregroundStyle(T.ink)
                        Seg(options: [("system", "아이폰 설정"), ("light", "라이트"), ("dark", "다크")], value: $settings.theme, label: "화면 모드")
                        Text("한 주의 시작").font(F.sans(15, .medium)).foregroundStyle(T.ink).padding(.top, 4)
                        Seg(options: [("sun", "일요일"), ("mon", "월요일")], value: Binding(get: { store.weekStart }, set: { store.setWeekStart($0) }), label: "한 주의 시작")
                        Text("처음에는 일요일이에요 · 바꾸면 맥 DayROAD 도 같이 바뀌어요").font(F.sans(12)).foregroundStyle(T.muted)
                    }
                }
                Card {
                    HStack {
                        Text("버전").font(F.sans(15))
                        Spacer()
                        Text(appVersion).font(F.sans(15, .semibold))
                    }
                    .foregroundStyle(T.ink).padding(.horizontal, 14).frame(minHeight: 50)
                    line
                    if let v = upd.latest {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("새 버전 \(v) 이 나왔어요").font(F.sans(15, .bold)).foregroundStyle(T.accentText)
                            Text("맥 DayROAD 가 아이폰용 파일을 받아 둬요. 다음에 아이폰을 맥에 연결하고 Xcode 에서 ▶ 를 누르면 들어와요.")
                                .font(F.sans(13)).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
                            ForEach(upd.notes, id: \.self) { n in Text("· " + n).font(F.sans(12.5)).foregroundStyle(T.muted) }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(T.accentSoft)
                        line
                    }
                    Button { showDiag = true } label: {
                        HStack {
                            Text("진단 정보 보기").font(F.sans(15))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(T.check)
                        }
                        .foregroundStyle(T.ink).padding(.horizontal, 14).frame(minHeight: 50).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("made by. Nevertheless_D").font(F.sans(12.5)).foregroundStyle(T.muted).frame(maxWidth: .infinity).padding(.top, 4)
            }
            .padding(.horizontal, 16).padding(.bottom, 40)
        }
        .background(T.paper)
        .onAppear { pass = AppPass.read(); Task { await notify.refreshStatus(); await upd.check() } }
        .sheet(item: Binding(get: { pickTime.map { DetailID(id: $0) } }, set: { pickTime = $0?.id })) { k in
            PickSheet(title: k.id == "morning" ? "아침 알림" : "마감 알림", isTime: true,
                      value: k.id == "morning" ? settings.morningTime : settings.dueTime, canClear: false) { v in
                if let v = v { if k.id == "morning" { settings.morningTime = v } else { settings.dueTime = v } }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showDiag) { DiagView() }
        .fileImporter(isPresented: $reconnect, allowedContentTypes: [.folder]) { r in
            if case .success(let u) = r { Task { if let e = await cloud.connect(u) { Toast.shared.show(e) } } }
        }
    }

    func ask() { Task { await notify.request() } }

    var line: some View { Rectangle().fill(T.line2).frame(height: 1) }

    func toggleRow(_ title: String, _ sub: String, _ on: Binding<Bool>, time: (String, String)? = nil) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(F.sans(15, .medium)).foregroundStyle(T.ink)
                Text(sub).font(F.sans(12.5)).foregroundStyle(T.muted)
            }
            Spacer(minLength: 6)
            if let tm = time {
                Button { pickTime = tm.0 } label: {
                    Text(Day.time(tm.1)).font(F.sans(13.5, .semibold)).foregroundStyle(T.ink)
                        .padding(.horizontal, 10).frame(minHeight: 36)
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Toggle(title, isOn: on).labelsHidden().tint(T.done)
        }
        .padding(.horizontal, 14).frame(minHeight: 62)
    }

    func warn(_ t: String, _ sub: String, _ btn: String, _ f: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t).font(F.sans(15, .bold)).foregroundStyle(T.accentText)
            Text(sub).font(F.sans(13)).foregroundStyle(T.ink)
            Button(btn, action: f).font(F.sans(14, .semibold)).foregroundStyle(T.ink)
                .padding(.horizontal, 14).frame(minHeight: 40)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line, lineWidth: 1))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(T.accentSoft))
    }

    // MARK: 남은 사용 기간

    var passCard: some View {
        let days = pass.daysLeft
        let warnOn = (days ?? 7) <= 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("남은 사용 기간").font(F.sans(13, .bold)).foregroundStyle(warnOn ? T.accentText : T.muted)
                    if let d = days {
                        (Text("\(d)").font(F.serif(46)) + Text(" 일").font(F.sans(17, .bold))).foregroundStyle(T.ink)
                    } else {
                        Text("정해지지 않음").font(F.serif(26)).foregroundStyle(T.ink)
                    }
                }
                Spacer()
                if !pass.untilText.isEmpty {
                    Text("\(pass.untilText)\n까지 써져요").font(F.sans(13)).foregroundStyle(T.muted).multilineTextAlignment(.trailing)
                }
            }
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(i < pass.cells ? (warnOn ? T.accent : T.done) : T.line).frame(height: 9)
                }
            }
            .accessibilityElement().accessibilityLabel("7일 중 \(days ?? 0)일 남음")
            Group {
                if pass.expires == nil {
                    Text("Xcode 에서 직접 설치한 앱이 아니라서 사용 기간이 없어요.")
                } else {
                    Text("기간이 ") + Text("끝난 뒤에").bold() + Text(" 아이폰을 맥에 연결하고 Xcode에서 ▶ 를 누르면 새로 7일이 시작돼요. 할 일은 iCloud 에 있어서 그대로예요. 끝나기 하루 전에 알림으로 알려 드려요.")
                }
            }
            .font(F.sans(13)).foregroundStyle(T.ink).lineSpacing(3)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(warnOn ? T.accentSoft : T.side))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(warnOn ? T.accent : T.line, lineWidth: 1.5))
    }

    // MARK: iCloud

    var cloudCard: some View {
        let ok = cloud.state == .ok
        let (title, sub): (String, String) = {
            switch cloud.state {
            case .ok:
                let f = DateFormatter(); f.locale = Locale(identifier: "ko_KR"); f.dateFormat = "a h:mm"
                return ("맥과 같은 할 일을 보고 있어요", "iCloud Drive › DayROAD · 마지막으로 맞춘 때 \(cloud.last.map { f.string(from: $0) } ?? "방금")")
            case .waiting, .starting: return ("iCloud 와 맞추는 중이에요", cloud.msg.isEmpty ? "잠시만 기다려 주세요" : cloud.msg)
            default: return ("iCloud 와 맞추지 못했어요", cloud.msg)
            }
        }()
        return Card {
            HStack(spacing: 12) {
                Image(systemName: ok ? "checkmark.icloud" : "exclamationmark.icloud").font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ok ? T.doneText : T.accentText)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 10).fill(ok ? T.doneSoft : T.accentSoft))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(F.sans(15, .bold)).foregroundStyle(T.ink)
                    Text(sub).font(F.sans(12.5)).foregroundStyle(T.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            HStack(spacing: 8) {
                Button { Task { await cloud.sync("지금 맞추기"); Toast.shared.show(cloud.state == .ok ? "맥과 맞췄어요" : "맞추지 못했어요") } } label: {
                    Text("지금 맞추기").font(F.sans(14, .semibold)).foregroundStyle(T.paper)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(RoundedRectangle(cornerRadius: 11).fill(T.ink))
                }
                Button { reconnect = true } label: {
                    Text("폴더 다시 고르기").font(F.sans(14)).foregroundStyle(T.ink)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 11).stroke(T.line, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
    }
}

struct DiagView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: Store
    @EnvironmentObject var cloud: Cloud

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    let pass = AppPass.read()
                    let summary = """
                    DayROAD 아이폰 \(appVersion) · iOS \(UIDevice.current.systemVersion)
                    할 일 \(store.d.tasks.count)개 (남은 일 \(store.d.tasks.filter { !$0.done }.count)) · 분류 \(store.d.cats.count) · 지운 기록 \(store.d.deleted.count)
                    한 주의 시작 \(store.weekStart) · 마지막 정리 \(store.d.lastDay)
                    iCloud \(cloud.state.rawValue) \(cloud.msg) · 마지막 \(cloud.last.map { "\($0)" } ?? "-")
                    위젯 폴더 \(Paths.widgetDir == nil ? "없음(앱 그룹 못 씀)" : "있음")
                    사용 기간 \(pass.expires.map { "\($0)" } ?? "없음") · 팀 \(pass.teamName)
                    """
                    Text(summary).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    Text(String(Log.text().suffix(20000))).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                }
                .padding()
            }
            .navigationTitle("진단 정보")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .cancellationAction) {
                    ShareLink(item: Log.text()) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("기록 보내기")
                }
            }
        }
    }
}
