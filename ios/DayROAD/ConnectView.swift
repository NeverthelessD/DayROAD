import SwiftUI
import UniformTypeIdentifiers

// ⑦ 처음 켤 때 (확정 시안): '파일' 창에서 iCloud Drive › DayROAD 폴더를 한 번 고르면 맥의 할 일이 들어와요.

struct ConnectView: View {
    @EnvironmentObject var cloud: Cloud
    @EnvironmentObject var store: Store
    @EnvironmentObject var notify: Notify
    @State private var picking = false
    @State private var busy = false
    @State private var err = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Logo(size: 64).padding(.top, 40)
                VStack(alignment: .leading, spacing: 8) {
                    Text("맥의 할 일을\n가져올게요").font(F.serif(30)).foregroundStyle(T.ink).lineSpacing(4).accessibilityAddTraits(.isHeader)
                    Text("맥 DayROAD 가 iCloud Drive 에 저장한 할 일을 아이폰에서도 같이 써요. 처음 한 번만 폴더를 골라 주세요.")
                        .font(F.sans(15)).foregroundStyle(T.muted).lineSpacing(4)
                }
                VStack(alignment: .leading, spacing: 10) {
                    step(1, Text("아래 단추를 누르면 아이폰 ‘파일’ 창이 열려요"))
                    step(2, Text("iCloud Drive 에서 ") + Text("DayROAD").bold() + Text(" 폴더를 눌러요"))
                    step(3, Text("오른쪽 위 ") + Text("열기").bold() + Text("를 누르면 끝이에요"))
                }
                folderPreview
                if !err.isEmpty {
                    Text(err).font(F.sans(14)).foregroundStyle(T.accentText)
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(T.accentSoft))
                }
                Button { err = ""; picking = true } label: {
                    HStack {
                        if busy { ProgressView().tint(T.onAccent) }
                        Text(busy ? "가져오는 중…" : "DayROAD 폴더 고르기")
                    }
                    .font(F.sans(16, .bold)).foregroundStyle(T.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(T.accent))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                Text("폴더가 안 보이면 맥 DayROAD › 설정 › iCloud 저장이 켜져 있는지 봐 주세요")
                    .font(F.sans(12.5)).foregroundStyle(T.muted).multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 22).padding(.bottom, 40)
        }
        .background(T.paper)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.folder]) { r in
            switch r {
            case .success(let u):
                busy = true
                Task {
                    if let e = await cloud.connect(u) { err = e } else {
                        Toast.shared.show("할 일 \(store.d.tasks.count)개를 가져왔어요")
                        await notify.request()
                        await Cal.shared.request()
                    }
                    busy = false
                }
            case .failure(let e):
                err = "폴더를 열지 못했어요: \(e.localizedDescription)"
            }
        }
    }

    func step(_ n: Int, _ t: Text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(n)").font(F.sans(13, .bold)).foregroundStyle(T.accentText)
                .frame(width: 26, height: 26).background(Circle().fill(T.accentSoft))
            t.font(F.sans(14.5)).foregroundStyle(T.ink).lineSpacing(3)
        }
    }

    var folderPreview: some View {
        VStack(spacing: 0) {
            HStack {
                Text("iCloud Drive").foregroundStyle(T.muted)
                Spacer()
                Text("열기").bold().foregroundStyle(Color(hex6: "#3366B0"))
            }
            .font(F.sans(13)).padding(.horizontal, 14).padding(.vertical, 10).background(T.side)
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.system(size: 24)).foregroundStyle(Color(hex6: "#7EA6E6"))
                Text("DayROAD").font(F.sans(15, .semibold)).foregroundStyle(T.ink)
                Spacer()
                Text("맥에서").font(F.sans(12)).foregroundStyle(T.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 12).background(T.carryBg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// 빌드 서버 시험용: 위젯 그림 (작게 · 중간 · 크게, 라이트 · 다크) → Documents/widgets-*.png
@MainActor
enum WidgetShots {
    static func render() {
        Store.shared.exportWidget()
        let data = WidgetFiles.load()
        let t = WToday.make(data)
        for dark in [false, true] {
            let p = WPalette.of(dark ? .dark : .light)
            let v = VStack(spacing: 16) {
                let sizes: [(WFamily, CGSize)] = [(.small, CGSize(width: 170, height: 170)), (.medium, CGSize(width: 364, height: 170)), (.large, CGSize(width: 364, height: 382))]
                ForEach(0..<3, id: \.self) { i in
                    let fs = sizes[i]
                    DayROADWidgetView(t: t.empty ? .sample : t, family: fs.0, toggle: { AnyView(WCheck(done: $0.isDone, p: p)) }, p: p)
                        .frame(width: fs.1.width, height: fs.1.height)
                        .background(p.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
            .padding(20)
            .background(dark ? Color.black : Color(white: 0.9))
            .environment(\.colorScheme, dark ? .dark : .light)
            let r = ImageRenderer(content: v)
            r.scale = 2
            if let img = r.uiImage, let png = img.pngData() {
                try? png.write(to: Demo.docs.appendingPathComponent("widgets-\(dark ? "dark" : "light").png"))
            }
        }
        Log.write("위젯 그림을 만들었어요 (앱 그룹 \(Paths.widgetDir == nil ? "없음" : "있음"), 자료 \(data == nil ? "없음" : "있음"))")
    }
}
