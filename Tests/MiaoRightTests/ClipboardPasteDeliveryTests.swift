import AppKit
import MiaoRightShared
import XCTest
@testable import MiaoRightKit

@MainActor
final class ClipboardPasteDeliveryTests: XCTestCase {
    @MainActor private final class Harness {
        var authorized = true
        var version = 7
        var frontmost: pid_t? = 12345
        var panelHasKey = true
        var restoreSucceeds = true
        var ticks = 0
        var events: [String] = []
        var onPause: (() -> Void)?
        lazy var delivery = ClipboardPasteDelivery(environment: .init(
            authorized: { self.authorized }, clipboardVersion: { self.version },
            frontmostProcess: { self.frontmost }, restoreTarget: { pid in self.events.append("restore:\(pid)"); return self.restoreSucceeds },
            panelHasKey: { self.panelHasKey }, postPaste: { pid in self.events.append("paste:\(pid)"); return true },
            pause: { self.ticks += 1; self.onPause?() }))
    }

    func testPasteWaitsForPanelFocusReleaseAndTargetsOriginalApplication() async {
        let harness = Harness()
        harness.onPause = { if harness.ticks == 3 { harness.panelHasKey = false } }
        let result = await harness.delivery.deliver(to: 12345, clipboardVersion: 7)
        XCTAssertEqual(result, .pasted)
        XCTAssertEqual(harness.ticks, 4)
        XCTAssertEqual(harness.events, ["restore:12345", "paste:12345"])
    }

    func testSwitchingApplicationsOrClipboardCancelsPaste() async {
        for changesClipboard in [false, true] {
            let harness = Harness()
            harness.onPause = {
                harness.panelHasKey = false
                if changesClipboard { harness.version += 1 } else { harness.frontmost = 54321 }
            }
            let result = await harness.delivery.deliver(to: 12345, clipboardVersion: 7)
            XCTAssertEqual(result, .changed)
            XCTAssertEqual(harness.events, ["restore:12345"])
        }
        let harness = Harness()
        harness.frontmost = 54321
        let result = await harness.delivery.deliver(to: 12345, clipboardVersion: 7)
        XCTAssertEqual(result, .changed)
        XCTAssertTrue(harness.events.isEmpty)
    }

    func testPermissionAndTargetFailuresDoNotSendKeys() async {
        let denied = Harness()
        denied.authorized = false
        let deniedResult = await denied.delivery.deliver(to: 12345, clipboardVersion: 7)
        XCTAssertEqual(deniedResult, .permissionDenied)
        XCTAssertTrue(denied.events.isEmpty)
        let missing = Harness()
        let missingResult = await missing.delivery.deliver(to: nil, clipboardVersion: 7)
        XCTAssertEqual(missingResult, .unavailable)
        XCTAssertTrue(missing.events.isEmpty)
        let timeout = Harness()
        let timeoutResult = await timeout.delivery.deliver(to: 12345, clipboardVersion: 7)
        XCTAssertEqual(timeoutResult, .unavailable)
        XCTAssertEqual(timeout.events, ["restore:12345"])
    }

    func testReopeningPanelCancelsPendingPaste() async {
        let harness = Harness()
        harness.onPause = { harness.delivery.cancel() }
        let result = await harness.delivery.deliver(to: 12345, clipboardVersion: 7)
        XCTAssertEqual(result, .cancelled)
        XCTAssertEqual(harness.events, ["restore:12345"])
    }

    func testEveryPresentationStartsAtFirstItemWithoutStaleMultiSelection() {
        var state = ClipboardListState(selection: 8, picked: [UUID(), UUID()])
        state.beginPresentation()
        XCTAssertEqual(state.selection, 0)
        XCTAssertTrue(state.picked.isEmpty)
        state.selection = 3
        state.picked = [UUID()]
        state.beginPresentation()
        XCTAssertEqual(state.selection, 0)
        XCTAssertTrue(state.picked.isEmpty)
    }

    func testReuseOnlyPreparesClipboardAndDoesNotDeliverPaste() {
        XCTAssertTrue(AppGroup.isIsolated)
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let item = ClipboardItem(kind: .text, content: "Isolated paste preparation")
        XCTAssertTrue(ClipboardHistoryService.shared.reuse(item, pasteboard: board))
        XCTAssertEqual(board.string(forType: .string), item.content)
        // 真实输入事件由隔离 guard 阻止；这里只使用独立命名的粘贴板。
        XCTAssertFalse(AutoPaste.paste(to: ProcessInfo.processInfo.processIdentifier))
    }
}
