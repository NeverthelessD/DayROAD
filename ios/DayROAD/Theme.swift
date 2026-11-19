import SwiftUI
import UIKit

// 확정 디자인 (맥 DayROAD 와 같은 '종이 플래너' 색) — 라이트 · 다크

extension Color {
    static func dyn(_ light: String, _ dark: String) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

enum T {
    static let paper = Color.dyn("#FFFDF8", "#1B1F25")
    static let side = Color.dyn("#F6F2EA", "#20252C")
    static let line = Color.dyn("#E6DFD2", "#2E343D")
    static let line2 = Color.dyn("#EEE8DD", "#262B33")
    static let ink = Color.dyn("#1F2A37", "#ECE6DA")
    static let muted = Color.dyn("#5E6673", "#A2A8B2")
    static let accent = Color.dyn("#C9502A", "#E8703F")
    static let accentText = Color.dyn("#B4461C", "#F2936B")
    static let accentSoft = Color.dyn("#FBE9E0", "#3A2A22")
    static let onAccent = Color.dyn("#FFFFFF", "#1A0F08")
    static let check = Color.dyn("#8C8578", "#7C838E")
    static let field = Color.dyn("#FFFFFF", "#151920")
    static let done = Color.dyn("#3F7D57", "#5FA77A")
    static let doneText = Color.dyn("#2F6B47", "#7CC495")
    static let onDone = Color.dyn("#FFFFFF", "#0F1A13")
    static let doneSoft = Color.dyn("#E3F0E7", "#1F2E25")
    static let track = Color.dyn("#ECE6DA", "#2E343D")
    static let chip = Color.dyn("#F1ECE2", "#2A3038")
    static let carryBg = Color.dyn("#EAF0FA", "#232B3A")
    static let carryFg = Color.dyn("#2F4F86", "#A9C0EC")
    static let knobOff = Color.dyn("#D8CFBF", "#3A414B")

    static func cat(_ key: String) -> Color {
        guard let p = Palette.colors[key] else { return muted }
        return .dyn(p.0, p.1)
    }
}

/// 글꼴: 본문 IBM Plex Sans KR · 제목과 날짜 숫자 고운바탕 Bold (둘 다 앱 안에 들어 있어요, OFL)
enum F {
    static func sans(_ size: CGFloat, _ w: Font.Weight = .regular) -> Font {
        let name: String
        switch w {
        case .bold, .heavy, .black: name = "IBMPlexSansKR-Bold"
        case .semibold: name = "IBMPlexSansKR-SemiBold"
        case .medium: name = "IBMPlexSansKR-Medium"
        default: name = "IBMPlexSansKR-Regular"
        }
        return .custom(name, size: size, relativeTo: .body)
    }

    static func serif(_ size: CGFloat) -> Font { .custom("GowunBatang-Bold", size: size, relativeTo: .title) }
}

/// 앱 아이콘 모양 (작게 그리는 로고)
struct Logo: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous).fill(Color(hex6: "#D9572B"))
            VStack(alignment: .leading, spacing: size * 0.07) {
                RoundedRectangle(cornerRadius: size * 0.03).fill(Color(hex6: "#3F7D57")).frame(width: size * 0.12, height: size * 0.12)
                Capsule().fill(Color(hex6: "#1F2A37")).frame(width: size * 0.36, height: size * 0.06)
                Capsule().fill(Color(hex6: "#1F2A37")).frame(width: size * 0.28, height: size * 0.06)
            }
            .padding(size * 0.1)
            .frame(width: size * 0.56, height: size * 0.66, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: size * 0.07).fill(Color(hex6: "#FFFDF8")))
            .rotationEffect(.degrees(-6))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex6: String) { self.init(uiColor: UIColor(hex: hex6)) }
}

/// 분류 색 점 그림 — 메뉴 안에서도 색이 보이게 (원래 색 그대로 그리기)
enum Dot {
    static func image(_ key: String, dark: Bool) -> UIImage {
        let p = Palette.colors[key] ?? ("#56606E", "#A9B2BE")
        let c = UIColor(hex: dark ? p.1 : p.0)
        let r = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16))
        return r.image { ctx in
            c.setFill()
            ctx.cgContext.fillEllipse(in: CGRect(x: 2, y: 2, width: 12, height: 12))
        }.withRenderingMode(.alwaysOriginal)
    }
}

/// 둥근 상자 (설정 · 자세히 칸)
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(T.field))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(T.line, lineWidth: 1))
    }
}

/// 켜고 끄는 단추 (시안의 초록 스위치)
struct DRToggle: View {
    var label: String
    @Binding var on: Bool
    var body: some View {
        Toggle(label, isOn: $on).labelsHidden().tint(T.done)
    }
}

/// 몇 가지 중 하나 고르기 (시안의 회색 바탕 버튼 줄)
struct Seg<V: Hashable>: View {
    var options: [(V, String)]
    @Binding var value: V
    var label: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let on = o.0 == value
                Button { value = o.0 } label: {
                    Text(o.1).font(F.sans(13.5, on ? .bold : .medium))
                        .foregroundStyle(on ? T.ink : T.muted)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? T.field : Color.clear)
                            .shadow(color: on ? Color.black.opacity(0.12) : .clear, radius: 1, y: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(T.chip))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// 작은 표시 (시간 · 마감 · 넘어옴)
struct Pill: View {
    var text: String
    var bg: Color = T.chip
    var fg: Color = T.ink
    var bold = false
    var body: some View {
        Text(text).font(F.sans(12.5, bold ? .semibold : .medium)).foregroundStyle(fg)
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(bg))
    }
}
