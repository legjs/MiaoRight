import AppKit
import MiaoRightShared
import Carbon
import Carbon.HIToolbox
import Foundation

/// 全局快捷键中心:Carbon 系统热键(无需辅助功能权限),支持运行时重配置。
/// 为剪贴板面板和直接粘贴分别注册热键。
@MainActor
public final class HotkeyCenter {
    public static let shared = HotkeyCenter()

    enum Shortcut: UInt32, CaseIterable {
        case history = 1
        case previousItem

        var storageKey: String {
            self == .history ? "clipboardHotkey" : "clipboardPreviousItemHotkey"
        }

        var defaultModifiers: Int {
            self == .history ? Int(cmdKey | shiftKey) : Int(cmdKey | controlKey | shiftKey)
        }
    }

    private var hotKeys: [Shortcut: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private let signature = UInt32.random(in: 0x1000...0xFFFFFFF)

    private init() {}

    /// 当前生效的组合(显示用):如 "⇧⌘V"
    public var currentDisplay: String {
        display(for: .history)
    }

    func display(for shortcut: Shortcut) -> String {
        let (mods, code) = combination(for: shortcut)
        return Self.display(modifiers: mods, keyCode: code)
    }

    public var currentCombination: (modifiers: Int, keyCode: Int) {
        combination(for: .history)
    }

    func combination(for shortcut: Shortcut) -> (modifiers: Int, keyCode: Int) {
        let stored = AppGroup.standardDefaults.array(forKey: shortcut.storageKey) as? [Int]
        if let stored, stored.count == 2 {
            return (stored[0], stored[1])
        }
        let defaults = (shortcut.defaultModifiers, Int(kVK_ANSI_V))
        if shortcut == .previousItem && combination(for: .history) == defaults {
            return (Int(cmdKey | controlKey | optionKey), Int(kVK_ANSI_V))
        }
        return defaults
    }

    /// App 启动时注册;设置页改键后调用 reconfigure
    public func registerDefault() {
        for shortcut in Shortcut.allCases {
            guard hotKeys[shortcut] == nil else { continue }
            let combo = combination(for: shortcut)
            _ = register(shortcut, modifiers: combo.modifiers, keyCode: combo.keyCode)
        }
    }

    func update(_ shortcut: Shortcut, modifiers: Int, keyCode: Int) -> Bool {
        guard !Shortcut.allCases.contains(where: { $0 != shortcut && combination(for: $0) == (modifiers, keyCode) })
        else { return false }
        if combination(for: shortcut) == (modifiers, keyCode), hotKeys[shortcut] != nil { return true }
        guard register(shortcut, modifiers: modifiers, keyCode: keyCode) else { return false }
        AppGroup.standardDefaults.set([modifiers, keyCode], forKey: shortcut.storageKey)
        return true
    }

    // MARK: - Carbon 注册

    private func register(_ shortcut: Shortcut, modifiers: Int, keyCode: Int) -> Bool {
        guard !AppGroup.isIsolated, let key = UInt32(exactly: keyCode), let flags = UInt32(exactly: modifiers),
              installHandler() else { return false }
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            key,
            flags,
            EventHotKeyID(signature: signature, id: shortcut.rawValue),
            GetApplicationEventTarget(),
            shortcut == .previousItem ? UInt32(kEventHotKeyExclusive) : 0,
            &reference
        )
        guard status == noErr, let reference else {
            NSLog("[HotkeyCenter] RegisterEventHotKey failed: \(status)")
            return false
        }
        if let old = hotKeys.updateValue(reference, forKey: shortcut) { UnregisterEventHotKey(old) }
        return true
    }

    private func installHandler() -> Bool {
        if eventHandler != nil { return true }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, _ in
            var hkID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            // 回调不在主线程上下文 → 派发到主线程
            if hkID.signature != 0 {
                Task { @MainActor in
                    HotkeyCenter.shared.handleHotkey(id: hkID.id, signature: hkID.signature)
                }
            }
            return noErr
        }
        return InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &eventHandler) == noErr
    }

    @MainActor
    private func handleHotkey(id: UInt32, signature: UInt32) {
        guard signature == self.signature, let shortcut = Shortcut(rawValue: id) else { return }
        switch shortcut {
        case .history:
            ClipboardFloatingPanel.shared.toggle()
        case .previousItem:
            Task { await ClipboardHistoryService.shared.pastePreviousItem() }
        }
    }

    // MARK: - 显示

    /// 组合键的可读字符串(⇧⌃⌥⌘ + 键名)
    static func display(modifiers: Int, keyCode: Int) -> String {
        var parts: [String] = []
        if modifiers & Int(controlKey) != 0 { parts.append("⌃") }
        if modifiers & Int(optionKey) != 0 { parts.append("⌥") }
        if modifiers & Int(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & Int(cmdKey) != 0 { parts.append("⌘") }
        return parts.joined() + keyName(keyCode)
    }

    /// 主键名(KeyCode → 字符);不可打印键给出通用名
    static func keyName(_ keyCode: Int) -> String {
        switch keyCode {
        case kVK_ANSI_A: "A"; case kVK_ANSI_B: "B"; case kVK_ANSI_C: "C"; case kVK_ANSI_D: "D"
        case kVK_ANSI_E: "E"; case kVK_ANSI_F: "F"; case kVK_ANSI_G: "G"; case kVK_ANSI_H: "H"
        case kVK_ANSI_I: "I"; case kVK_ANSI_J: "J"; case kVK_ANSI_K: "K"; case kVK_ANSI_L: "L"
        case kVK_ANSI_M: "M"; case kVK_ANSI_N: "N"; case kVK_ANSI_O: "O"; case kVK_ANSI_P: "P"
        case kVK_ANSI_Q: "Q"; case kVK_ANSI_R: "R"; case kVK_ANSI_S: "S"; case kVK_ANSI_T: "T"
        case kVK_ANSI_U: "U"; case kVK_ANSI_V: "V"; case kVK_ANSI_W: "W"; case kVK_ANSI_X: "X"
        case kVK_ANSI_Y: "Y"; case kVK_ANSI_Z: "Z"
        case kVK_ANSI_0: "0"; case kVK_ANSI_1: "1"; case kVK_ANSI_2: "2"; case kVK_ANSI_3: "3"
        case kVK_ANSI_4: "4"; case kVK_ANSI_5: "5"; case kVK_ANSI_6: "6"; case kVK_ANSI_7: "7"
        case kVK_ANSI_8: "8"; case kVK_ANSI_9: "9"
        case kVK_Space: "空格"; case kVK_Return: "回车"; case kVK_Tab: "Tab"
        case kVK_Escape: "Esc"; case kVK_Delete: "删除"
        case kVK_LeftArrow: "←"; case kVK_RightArrow: "→"; case kVK_UpArrow: "↑"; case kVK_DownArrow: "↓"
        case kVK_F1: "F1"; case kVK_F2: "F2"; case kVK_F3: "F3"; case kVK_F4: "F4"; case kVK_F5: "F5"
        case kVK_F6: "F6"; case kVK_F7: "F7"; case kVK_F8: "F8"; case kVK_F9: "F9"; case kVK_F10: "F10"
        case kVK_F11: "F11"; case kVK_F12: "F12"
        default: "键(\(keyCode))"
        }
    }

    /// NSEvent 修饰符 → Carbon 修饰符(录制控件转换用)
    static func carbonModifiers(from eventModifiers: NSEvent.ModifierFlags) -> Int {
        var carbon = 0
        if eventModifiers.contains(.command) { carbon |= Int(cmdKey) }
        if eventModifiers.contains(.option) { carbon |= Int(optionKey) }
        if eventModifiers.contains(.control) { carbon |= Int(controlKey) }
        if eventModifiers.contains(.shift) { carbon |= Int(shiftKey) }
        return carbon
    }
}
