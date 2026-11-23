import AppKit
import SwiftUI

/// NSVisualEffectView 封装:窗口级「毛玻璃」效果。
/// `behindWindow` 混合模式会把窗口后方的内容(桌面/其他窗口)实时模糊进去,
/// 配合深色主题即类 HUD 的磨砂质感。
struct GlassEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var emphasized: Bool = false
    var state: NSVisualEffectView.State = .followsWindowActiveState
    var opacity: Double = 1
    var appearance: NSAppearance? = nil
    var tint: NSColor = .clear

    func makeNSView(context: Context) -> FrostedVisualEffectView {
        let view = FrostedVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = emphasized
        view.alphaValue = opacity
        view.appearance = appearance
        view.tintColor = tint
        return view
    }

    func updateNSView(_ view: FrostedVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
        view.isEmphasized = emphasized
        view.state = state
        view.alphaValue = opacity
        view.appearance = appearance
        view.tintColor = tint
    }
}

/// 底色放在原生材质的子视图中，不把整个模糊层变成半透明图层。
class FrostedVisualEffectView: NSVisualEffectView {
    private let tintView = NSView()
    var tintColor: NSColor = .clear {
        didSet { tintView.layer?.backgroundColor = tintColor.cgColor }
    }

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        tintView.wantsLayer = true
        tintView.frame = bounds
        tintView.autoresizingMask = [.width, .height]
        addSubview(tintView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// 作为 NSHostingView 下方的原生兄弟视图，不覆盖 SwiftUI 自己绘制的内容。
struct MainWindowFrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> FrostedBackdropAnchor { FrostedBackdropAnchor() }
    func updateNSView(_ view: FrostedBackdropAnchor, context: Context) { view.installBackdrop() }
}

final class FrostedBackdropAnchor: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.installBackdrop() }
    }

    func installBackdrop() {
        guard let window, let content = window.contentView, let container = content.superview else { return }
        window.backgroundColor = .clear
        window.isOpaque = false
        content.layer?.backgroundColor = NSColor.clear.cgColor
        if let backdrop = container.subviews.first(where: { $0 is WindowFrostedBackdrop }) as? WindowFrostedBackdrop {
            backdrop.frame = content.frame
            backdrop.refreshMaterial()
            return
        }
        let backdrop = WindowFrostedBackdrop(frame: content.frame)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.setAccessibilityHidden(true)
        container.addSubview(backdrop, positioned: .below, relativeTo: content)
    }
}

final class WindowFrostedBackdrop: FrostedVisualEffectView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        refreshMaterial()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshMaterial()
    }

    @objc private func accessibilityChanged() { refreshMaterial() }

    func refreshMaterial() {
        material = .underWindowBackground
        blendingMode = .behindWindow
        state = .active
        alphaValue = 1
        let solid = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency || NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        tintColor = solid ? .windowBackgroundColor : (dark ? NSColor.black : .white).withAlphaComponent(dark ? 0.50 : 0.60)
    }
}

/// 系统原生的窗口后方模糊；减少透明度或提高对比度时使用实色表面。
struct FrostedWindowBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if reduceTransparency || contrast == .increased {
            Color(nsColor: .windowBackgroundColor)
        } else {
            GlassEffectView(material: .underWindowBackground, state: .active,
                            appearance: NSAppearance(named: scheme == .dark ? .vibrantDark : .vibrantLight),
                            tint: (scheme == .dark ? NSColor.black : .white)
                                .withAlphaComponent(scheme == .dark ? 0.50 : 0.60))
        }
    }
}

extension View {
    /// 把毛玻璃铺在视图最底层(替代 `.background(Color)` 的用法)。
    /// `tintOpacity` 追加一层深色,保证毛玻璃上的文字对比度。
    func glassBackground(tintOpacity: Double = 0.10) -> some View {
        background {
            ZStack {
                GlassEffectView()
                Color.black.opacity(tintOpacity)
            }
            .ignoresSafeArea()
        }
    }
}

/// 毛玻璃卡片用的半透明底色(透出底层模糊)
extension Color {
    static let frostedCard = Color.frostedCardBase.opacity(0.55)
}
