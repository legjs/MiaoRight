import XCTest
@testable import MiaoRightShared

final class FinderExtensionManagerTests: XCTestCase {
    func testParsesBundleIdentifierRatherThanRegistrationUUID() {
        let output = """
        +    com.miaoright.app.FinderSync(1.0.0)\tSELF-UUID\t2026-11-18 00:00:00 +0000\t/Applications/MiaoRight.app/Contents/PlugIns/MiaoRightFinder.appex
        -    com.example.Disabled(2.0)\tDISABLED-UUID\t2026-11-18 00:00:00 +0000\t/Applications/Other App.app/Contents/PlugIns/Finder Extension.appex
             com.example.Automatic(3.0)\tAUTO-UUID\t2026-11-18 00:00:00 +0000\t/Applications/Another.app/Contents/PlugIns/Finder.appex
         (3 plug-ins)
        """
        let extensions = FinderExtensionManager.parseList(output)
        XCTAssertEqual(extensions.count, 3)
        XCTAssertEqual(extensions.first?.bundleID, "com.miaoright.app.FinderSync")
        XCTAssertEqual(extensions.first?.isSelf, true)
        XCTAssertEqual(extensions.first?.isEnabled, true)
        XCTAssertEqual(extensions.first(where: { $0.bundleID == "com.example.Disabled" })?.isEnabled, false)
        XCTAssertEqual(extensions.first(where: { $0.bundleID == "com.example.Disabled" })?.path,
                       "/Applications/Other App.app/Contents/PlugIns/Finder Extension.appex")
        XCTAssertEqual(extensions.first(where: { $0.bundleID == "com.example.Automatic" })?.isEnabled, false)
    }

    func testIgnoresNonRegistrationOutput() {
        XCTAssertEqual(FinderExtensionManager.parseList("error: no matches\n (0 plug-ins)").count, 0)
        XCTAssertEqual(FinderExtensionManager.parseList("/invalid.appex").count, 0)
    }
}
