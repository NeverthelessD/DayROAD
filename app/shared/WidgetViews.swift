// DayROAD — 위젯 화면 (확정 시안: 작게 · 중간 · 크게, 라이트 · 다크)
// made by. Nevertheless_D

import CoreText
import SwiftUI

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, opacity: 1)
    }
}

struct WPalette {
    let paper, ink, muted, accent, done, onDone, track, line, check: Color
    var dark = false

    static func of(_ scheme: ColorScheme) -> WPalette {
        scheme == .dark
            ? WPalette(paper: Color(hex: "#1B1F25"), ink: Color(hex: "#ECE6DA"), muted: Color(hex: "#A2A8B2"), accent: Color(hex: "#F2936B"),
                       done: Color(hex: "#5FA77A"), onDone: Color(hex: "#0F1A13"), track: Color(hex: "#2E343D"), line: Color(hex: "#2A3038"), check: Color(hex: "#7C838E"), dark: true)
            : WPalette(paper: Color(hex: "#FFFDF8"), ink: Color(hex: "#1F2A37"), muted: Color(hex: "#5E6673"), accent: Color(hex: "#B4461C"),
                       done: Color(hex: "#3F7D57"), onDone: Color(hex: "#FFFFFF"), track: Color(hex: "#ECE6DA"), line: Color(hex: "#EFE9DE"), check: Color(hex: "#8C8578"))
    }
}

enum WFont {
    private static var registered = false
    /// 고운바탕(제목 숫자용)을 위젯 안에 들어 있는 파일에서 불러요. 없으면 맥 기본 명조로 보여요.
    static func registerOnce() {
        if registered { return }
        registered = true
        if let u = Bundle.main.url(forResource: "GowunBatang-Bold", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil)
        }
    }
    static func serif(_ size: CGFloat) -> Font {
        registerOnce()
        return .custom("GowunBatang-Bold", size: size)
    }
}

enum WFamily { case small, medium, large }

typealias WToggle = (WItem) -> AnyView

struct WCheck: View {
    let done: Bool
    let p: WPalette
    var size: CGFloat = 17
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(done ? p.done : p.check, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(done ? p.done : Color.clear))
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.55, weight: .heavy))
                    .foregroundStyle(p.onDone)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }
}

struct WRing: View {
    let done: Int
    let total: Int
    let p: WPalette
    var body: some View {
        let frac = total > 0 ? Double(done) / Double(total) : 0
        ZStack {
            Circle().stroke(p.track, lineWidth: 5)
            Circle().trim(from: 0, to: frac)
                .stroke(p.done, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.system(size: 12, weight: .bold)).foregroundStyle(p.ink)
        }
        .frame(width: 46, height: 46)
    }
}

struct WRow: View {
    let item: WItem
    let p: WPalette
    let toggle: WToggle
    var divider = true
    var body: some View {
        HStack(spacing: 9) {
            toggle(item)
            if !item.color.isEmpty && !item.isDone {
                Circle().fill(Color(hex: p.dark ? item.colorDark : item.color)).frame(width: 6, height: 6)
            }
            Text(item.title)
                .font(.system(size: 13, weight: item.isDone ? .regular : .medium))
                .strikethrough(item.isDone, color: p.muted)
                .foregroundStyle(item.isDone ? p.muted : p.ink)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let b = item.badge, !b.isEmpty, !item.isDone {
                Text(b).font(.system(size: 10.5, weight: .bold)).foregroundStyle(p.accent)
            }
            if !item.time.isEmpty {
                Text(item.time).font(.system(size: 11)).foregroundStyle(p.muted).monospacedDigit()
            }
        }
        .frame(height: 30)
        .overlay(alignment: .bottom) { if divider { Rectangle().fill(p.line).frame(height: 1) } }
    }
}

struct DayROADWidgetView: View {
    let t: WToday
    let family: WFamily
    let toggle: WToggle
    let p: WPalette

    var body: some View {
        Group {
            if t.empty {
                emptyView
            } else {
                switch family {
                case .small: small
                case .medium: medium
                case .large: large
                }
            }
        }
        .foregroundStyle(p.ink)
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t.dow).font(.system(size: 12, weight: .bold)).foregroundStyle(p.accent)
            Text("\(t.day)").font(WFont.serif(40)).lineLimit(1).minimumScaleFactor(0.6)
        }
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            dateBlock
            Spacer(minLength: 0)
            Text("DayROAD를 한 번 열어 주세요").font(.system(size: 13, weight: .semibold))
            Text("앱에서 적은 할 일이 여기에 보여요").font(.system(size: 11)).foregroundStyle(p.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                dateBlock
                Spacer(minLength: 0)
                WRing(done: t.done, total: t.total, p: p)
            }
            Spacer(minLength: 0)
            if let n = t.next {
                Text("다음 할 일").font(.system(size: 11)).foregroundStyle(p.muted)
                Text((n.time.isEmpty ? "" : n.time + " ") + n.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(2)
                    .lineSpacing(1)
            } else {
                Text(t.total > 0 ? "오늘 할 일을\n다 끝냈어요" : "오늘은\n할 일이 없어요").font(.system(size: 13.5, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var countBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(t.total)개 중 \(t.done)개").font(.system(size: 11)).foregroundStyle(p.muted)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.track)
                    Capsule().fill(p.done).frame(width: t.total > 0 ? g.size.width * CGFloat(t.done) / CGFloat(t.total) : 0)
                }
            }
            .frame(height: 5)
        }
    }

    private func rows(_ n: Int) -> some View {
        let list = Array(t.items.prefix(n))
        return VStack(spacing: 0) {
            if list.isEmpty {
                Spacer(minLength: 0)
                Text(t.total > 0 ? "오늘 할 일을 다 끝냈어요" : "오늘은 할 일이 없어요").font(.system(size: 13, weight: .medium)).foregroundStyle(p.muted)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { i, it in
                    WRow(item: it, p: p, toggle: toggle, divider: i < list.count - 1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                dateBlock
                Spacer(minLength: 0)
                countBar
            }
            .frame(width: 92)
            rows(4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
    }

    private var large: some View {
        let remaining = t.items.filter { !$0.isDone }.count
        let maxTotal = max(1, t.week.map { $0.total }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("이번 주").font(WFont.serif(20))
                Spacer(minLength: 4)
                Text("\(t.weekLabel) · \(t.weekTotal)개 중 \(t.weekDone)개").font(.system(size: 11.5)).foregroundStyle(p.muted).lineLimit(1)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(Array(t.week.enumerated()), id: \.offset) { _, d in
                    VStack(spacing: 5) {
                        Spacer(minLength: 0)
                        let h = max(8, CGFloat(d.total) / CGFloat(maxTotal) * 70)
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.track).frame(width: 22, height: h)
                            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.done)
                                .frame(width: 22, height: d.total > 0 ? h * CGFloat(d.done) / CGFloat(d.total) : 0)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        Text(d.dow).font(.system(size: 11, weight: .semibold)).foregroundStyle(d.today ? p.accent : p.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96)
            Rectangle().fill(p.line).frame(height: 1)
            HStack {
                Text("오늘 · \(t.dow) \(t.day)일 · 남은 일 \(remaining)").font(.system(size: 12, weight: .bold)).foregroundStyle(p.accent)
                Spacer(minLength: 0)
                if t.stale { Text("앱을 열면 정리돼요").font(.system(size: 10.5)).foregroundStyle(p.muted) }
            }
            rows(6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
    }
}

extension WToday {
    /// 위젯 목록에서 처음 보여 줄 견본
    static var sample: WToday {
        let items = [
            WItem(id: "1", title: "주간 회의 자료 정리", time: "09:30", done: false, color: "#3366B0", colorDark: "#7EA6E6", badge: nil),
            WItem(id: "2", title: "은행 업무 보기", time: "11:00", done: true, color: "#C9502A", colorDark: "#F2936B", badge: nil),
            WItem(id: "3", title: "디자인 시안 피드백 보내기", time: "14:00", done: false, color: "#3366B0", colorDark: "#7EA6E6", badge: "D-2"),
            WItem(id: "4", title: "운동 30분", time: "", done: false, color: "#2F7D50", colorDark: "#6FC08F", badge: nil),
            WItem(id: "5", title: "우유 · 계란 사기", time: "", done: false, color: "#C9502A", colorDark: "#F2936B", badge: nil),
        ]
        let names = ["월", "화", "수", "목", "금", "토", "일"]
        let tot = [3, 6, 4, 2, 5, 1, 0], dn = [3, 2, 0, 0, 0, 0, 0]
        let week = (0..<7).map { WDay(dow: names[$0], day: 9 + $0, total: tot[$0], done: dn[$0], today: $0 == 1) }
        return WToday(dow: "화요일", day: 10, items: items, total: 6, done: 2, next: items[2], week: week, weekLabel: "11월 9일 – 15일",
                      weekTotal: 21, weekDone: 5, stale: false, empty: false)
    }
}
