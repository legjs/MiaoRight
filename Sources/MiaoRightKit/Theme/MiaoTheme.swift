import MiaoRightShared
import SwiftUI

/// 「菜单工作台」主题令牌:极光弥散渐变打底,内容坐在半透明玻璃卡上。
/// 全部界面通过 `MiaoScreen` 获得一致背景,组件从这里取色,禁止散落定义。
enum MiaoTheme {
    /// 品牌强调色(青绿,取自整理归档场景色)
    static let accent = Color(hexString: "#14B8A6")
    static let accentIndigo = Color(hexString: "#6366F1")
    static let accentPink = Color(hexString: "#EC4899")
    static let accentSky = Color(hexString: "#38BDF8")

    /// 场景色唯一来源:BuiltInMenuCategory.colorHex;顶层动作用品牌青绿
    static func sceneColor(_ scene: BuiltInMenuCategory?) -> Color {
        guard let scene else { return accent }
        return Color(hexString: scene.colorHex)
    }

    /// 主按钮等强调元素用的品牌渐变
    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accentIndigo],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// 场景磁贴用的纵向渐变(实色 → 半透)
    static func tileGradient(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color, color.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

/// 全屏容器:极光底 + 内容。所有详情页的根视图。
struct MiaoScreen<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            base.ignoresSafeArea()
            AuroraBlobs(dark: colorScheme == .dark).ignoresSafeArea()
            content
        }
    }

    private var base: Color {
        colorScheme == .dark ? Color(hexString: "#0B0D16") : Color(hexString: "#F2F3F9")
    }
}

/// 极光弥散光斑:大尺寸径向渐变圆,缓慢漂移。
/// 用径向渐变代替高斯模糊,避免大范围 blur 的渲染开销。
struct AuroraBlobs: View {
    let dark: Bool
    @State private var drift = false

    private var opacity: Double { dark ? 0.30 : 0.38 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                blob(MiaoTheme.accentIndigo, diameter: w * 0.42, x: w * 0.06, y: h * 0.02, dx: 60, dy: 34)
                blob(MiaoTheme.accentPink, diameter: w * 0.36, x: w * 0.70, y: h * 0.06, dx: -50, dy: 42)
                blob(MiaoTheme.accent, diameter: w * 0.46, x: w * 0.28, y: h * 0.58, dx: 44, dy: -38)
                blob(MiaoTheme.accentSky, diameter: w * 0.32, x: w * 0.74, y: h * 0.60, dx: -36, dy: -30)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 26).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private func blob(_ color: Color, diameter: CGFloat, x: CGFloat, y: CGFloat, dx: CGFloat, dy: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .offset(x: x + (drift ? dx : 0), y: y + (drift ? dy : 0))
    }
}

/// 玻璃卡:材质圆角卡 + 玻璃描边 + 轻投影,全站统一的容器。
struct GlassCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(rim, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.06), radius: 10, y: 3)
    }

    private var rim: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.55)
    }
}

/// 十六进制颜色便捷初始化(全站唯一)
extension Color {
    init(hexString hex: String) {
        var value: UInt64 = 0
        var hexString = hex
        if hexString.hasPrefix("#") { hexString.removeFirst() }
        Scanner(string: hexString).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
