import AppKit
import MiaoRightShared
import SwiftUI

/// 快捷键录制控件:点击进入录制 → 按下任意「修饰键+主键」生效;
/// Esc 取消;纯修饰键松开不生效。生效即全局注册。
struct HotkeyRecorderView: View {
    var shortcut: HotkeyCenter.Shortcut = .history
    @State private var recording = false
    @State private var display: String?
    @State private var conflict = false
    @State private var localMonitor: Any?

    var body: some View {
        Button {
            recording ? stopRecording() : startRecording()
        } label: {
            HStack(spacing: 5) {
                Text(recording ? L10n.text("按下新组合…", "Press new combo…") : (display ?? HotkeyCenter.shared.display(for: shortcut)))
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: recording ? "keyboard" : "pencil")
                    .font(.system(size: 9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(recording ? Color(hexString: "#14B8A6").opacity(0.15) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(recording ? Color(hexString: "#14B8A6") : Color.primary.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(recording ? Color(hexString: "#14B8A6") : Color.primary)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onDisappear { stopRecording() }
        .alert(L10n.text("此快捷键不可用", "This shortcut is unavailable"), isPresented: $conflict) {
            Button(L10n.text("好", "OK"), role: .cancel) {}
        } message: {
            Text(L10n.text("请选择另一个组合键。", "Choose another key combination."))
        }
    }

    private func startRecording() {
        recording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            // Esc:取消录制
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            let carbonMods = HotkeyCenter.carbonModifiers(from: event.modifierFlags)
            // 必须含至少一个修饰键,否则会吃掉普通按键
            guard carbonMods != 0 else { return event }
            conflict = !HotkeyCenter.shared.update(shortcut, modifiers: carbonMods, keyCode: Int(event.keyCode))
            display = HotkeyCenter.shared.display(for: shortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        recording = false
    }
}
