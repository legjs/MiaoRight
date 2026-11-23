import AppKit
@testable import MiaoRightKit
import XCTest

@MainActor
final class ClipboardSlideViewportTests: XCTestCase {
    func testSlidingContentIsClippedAtEachScreenEdge() {
        _ = NSApplication.shared
        // 三屏横排,包含负坐标与不同高度;前两屏右侧都有相邻屏幕。
        let screens = [
            NSRect(x: -1920, y: 0, width: 1920, height: 1080),
            NSRect(x: 0, y: 0, width: 2560, height: 1440),
            NSRect(x: 2560, y: 200, width: 1920, height: 1080)
        ]
        for screen in screens {
            let frame = NSRect(x: screen.maxX - 224, y: screen.minY, width: 224, height: screen.height)
            let panel = ClipboardSlidePanel(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
            let viewport = ClipboardSlideViewport(content: content)
            panel.contentView = viewport
            defer { panel.orderOut(nil) }
            let fixedFrame = panel.frame
            XCTAssertEqual(viewport.layer?.masksToBounds, true)
            viewport.setRevealed(false, animated: false)
            XCTAssertTrue(content.frame.intersection(viewport.bounds).isEmpty)
            viewport.setRevealed(true, animated: false)
            XCTAssertEqual(content.frame, viewport.bounds)
            // 检查滑入/滑出途中的裁剪区域始终位于当前屏幕内。
            for step in 0...10 {
                content.setFrameOrigin(NSPoint(x: 224 * CGFloat(step) / 10, y: 0))
                let visible = content.frame.intersection(viewport.bounds)
                if !visible.isEmpty {
                    let global = visible.offsetBy(dx: frame.minX, dy: frame.minY)
                    XCTAssertTrue(screen.contains(global))
                }
                XCTAssertEqual(panel.frame, fixedFrame)
            }
        }
    }

    func testContentFillsViewportAfterChangingScreenHeight() {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 224, height: 1080))
        let viewport = ClipboardSlideViewport(content: content)
        viewport.setRevealed(false, animated: false)
        viewport.setFrameSize(NSSize(width: 224, height: 1440))
        viewport.setRevealed(true, animated: false)
        XCTAssertEqual(content.frame, viewport.bounds)
    }
}
