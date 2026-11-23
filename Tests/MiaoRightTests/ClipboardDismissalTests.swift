import AppKit
@testable import MiaoRightKit
import XCTest

@MainActor
final class ClipboardDismissalTests: XCTestCase {
    private func settle() async {
        try? await Task.sleep(for: .milliseconds(450))
    }

    private func click(_ window: NSWindow) {
        let event = NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: 1
        )!
        NSApp.sendEvent(event)
    }

    func testOutsideClicksMenusPinningAndEarlyClose() async {
        _ = NSApplication.shared
        let controller = ClipboardFloatingPanel.shared
        let defaults = UserDefaults.standard
        let previousPin = defaults.object(forKey: ClipboardPanelPreferences.keepOpenKey)
        defaults.set(false, forKey: ClipboardPanelPreferences.keepOpenKey)
        let other = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 80, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        defer {
            controller.slideOut()
            defaults.set(previousPin, forKey: ClipboardPanelPreferences.keepOpenKey)
            other.orderOut(nil)
        }
        controller.slideIn()
        await settle()
        guard let panel = NSApp.windows.first(where: { $0.title == "MiaoRight Clipboard" }) else {
            XCTFail("Clipboard panel was not created")
            return
        }
        click(panel)
        await settle()
        XCTAssertTrue(controller.isVisible)

        let menu = NSMenu()
        NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
        click(other)
        await settle()
        XCTAssertTrue(controller.isVisible)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        click(other)
        await settle()
        XCTAssertFalse(controller.isVisible)

        // 每次呼出都应重新安装监听;固定后外部点击不收起,手动关闭仍生效。
        defaults.set(true, forKey: ClipboardPanelPreferences.keepOpenKey)
        controller.slideIn()
        await settle()
        click(other)
        await settle()
        XCTAssertTrue(controller.isVisible)
        controller.slideOut()
        await settle()
        XCTAssertFalse(controller.isVisible)

        defaults.set(false, forKey: ClipboardPanelPreferences.keepOpenKey)
        controller.slideIn()
        controller.slideOut() // 展开动画期间收到的关闭不能被丢弃
        await settle()
        await settle()
        XCTAssertFalse(controller.isVisible)

        controller.slideIn()
        await settle()
        if let external = NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didActivateApplicationNotification, object: nil,
                userInfo: [NSWorkspace.applicationUserInfoKey: external]
            )
            await settle()
            XCTAssertFalse(controller.isVisible)
        } else {
            click(other)
            await settle()
            XCTAssertFalse(controller.isVisible)
        }
    }
}
