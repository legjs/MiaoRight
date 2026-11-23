import AppKit
@testable import MiaoRightKit
import XCTest

@MainActor
final class ClipboardKeyboardTests: XCTestCase {
    private final class Editor: NSTextView {
        var composing = false
        var keys: [UInt16] = []
        override func hasMarkedText() -> Bool { composing }
        override func keyDown(with event: NSEvent) { keys.append(event.keyCode) }
    }

    @MainActor private final class KeyLog {
        var keys: [Int] = []
    }

    private func withPanel(_ check: (ClipboardSlidePanel, Editor, KeyLog) -> Void) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let panel = ClipboardSlidePanel(
            contentRect: NSRect(x: -12000, y: -12000, width: 100, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        let editor = Editor(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        panel.contentView = editor
        let log = KeyLog()
        let token = NotificationCenter.default.addObserver(forName: .clipPanelKey, object: nil, queue: .main) { note in
            guard let key = note.userInfo?["keyCode"] as? Int else { return }
            MainActor.assumeIsolated { log.keys.append(key) }
        }
        defer {
            NotificationCenter.default.removeObserver(token)
            XCTAssertFalse(panel.isVisible)
            XCTAssertFalse(panel.isKeyWindow)
            XCTAssertFalse(NSApp.isActive)
            panel.orderOut(nil)
        }
        check(panel, editor, log)
    }

    private func send(_ key: UInt16, to panel: ClipboardSlidePanel) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: panel.windowNumber, context: nil,
            characters: key == 49 ? " " : "\r", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: key
        )!
        panel.sendEvent(event)
    }

    func testListShortcutsIgnoreInactiveTextResponder() {
        withPanel { panel, editor, log in
            // 搜索结束后,残留的原生文本响应者不能继续吞掉列表快捷键。
            XCTAssertTrue(panel.makeFirstResponder(editor))
            for key: UInt16 in [36, 76, 49, 18] { send(key, to: panel) }
            XCTAssertEqual(log.keys, [36, 36, 49, 18])
            XCTAssertTrue(editor.keys.isEmpty)
        }
    }

    func testSearchReturnThenListReturnAndSpace() {
        withPanel { panel, editor, log in
            XCTAssertTrue(panel.makeFirstResponder(editor))
            panel.setSearchFocused(true)
            send(49, to: panel)
            XCTAssertEqual(editor.keys, [49])
            XCTAssertTrue(log.keys.isEmpty)
            send(36, to: panel)
            XCTAssertFalse(panel.searchIsFocused)
            XCTAssertFalse(panel.firstResponder === editor)
            XCTAssertTrue(log.keys.isEmpty) // 确认搜索这一拍不能复制记录
            send(49, to: panel)
            send(36, to: panel)
            XCTAssertEqual(log.keys, [49, 36])
        }
    }

    func testNavigationLeavesSearchAndRestoresMultiSelection() {
        withPanel { panel, editor, log in
            XCTAssertTrue(panel.makeFirstResponder(editor))
            panel.setSearchFocused(true)
            for key: UInt16 in [125, 49, 125, 49, 36] { send(key, to: panel) }
            XCTAssertFalse(panel.searchIsFocused)
            XCTAssertEqual(log.keys, [125, 49, 125, 49, 36])
            XCTAssertTrue(editor.keys.isEmpty)
        }
    }

    func testCompositionKeepsReturnSpaceAndArrowsInSearch() {
        withPanel { panel, editor, log in
            XCTAssertTrue(panel.makeFirstResponder(editor))
            panel.setSearchFocused(true)
            editor.composing = true
            for key: UInt16 in [36, 49, 125, 126, 53] { send(key, to: panel) }
            XCTAssertTrue(panel.searchIsFocused)
            XCTAssertEqual(editor.keys, [36, 49, 125, 126, 53])
            XCTAssertTrue(log.keys.isEmpty)
            editor.composing = false
            send(76, to: panel)
            XCTAssertFalse(panel.searchIsFocused)
            XCTAssertTrue(log.keys.isEmpty)
            send(76, to: panel)
            XCTAssertEqual(log.keys, [36])
        }
    }
}
