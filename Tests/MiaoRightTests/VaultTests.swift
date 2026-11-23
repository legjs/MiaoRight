import Foundation
import MiaoRightShared
import XCTest
@testable import MiaoRightKit

@MainActor
final class VaultTests: XCTestCase {
    private func directory() throws -> URL {
        XCTAssertTrue(AppGroup.isIsolated)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MiaoRight-Vault-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }

    override func tearDown() {
        VaultConfig.clear()
        VaultTaskPresentation.shared.request = nil
        super.tearDown()
    }

    func testCatalogAndMappingsRegisterVaultAction() throws {
        let entry = try XCTUnwrap(ScriptLibrary.libraryScript(named: "加入保险箱"))
        XCTAssertEqual(NativeAction(script: entry.toScript()), .addToVault)
        XCTAssertTrue(["加入保险箱", "Add to Vault"].contains(ActionNames.name("加入保险箱")))
        XCTAssertTrue(["把文件或文件夹移入加密保险箱，原位置不再保留", "Move files or folders into the encrypted vault; the originals leave their location"]
            .contains(ActionNames.description("把文件或文件夹移入加密保险箱，原位置不再保留")))
        XCTAssertEqual(ActionEmoji.emoji(for: "加入保险箱"), "🔐")
        XCTAssertTrue(ScriptLibrary.allScripts.contains { $0.name == "加入保险箱" })
    }

    func testInteractiveVaultActionOnlyPreparesForm() async throws {
        let root = try directory()
        let file = root.appendingPathComponent("秘密.txt")
        try Data("confidential".utf8).write(to: file)
        defer { VaultTaskPresentation.shared.request = nil }
        let script = try XCTUnwrap(ScriptLibrary.libraryScript(named: "加入保险箱")).toScript()
        await ScriptExecutor.shared.execute(script: script, withPaths: [file.path])
        XCTAssertEqual(VaultTaskPresentation.shared.request?.urls, [file])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["秘密.txt"])
        XCTAssertEqual(try Data(contentsOf: file), Data("confidential".utf8))
    }

    func testVaultAlertConfirmIsSkippedForEmbeddedPreview() throws {
        let script = try XCTUnwrap(ScriptLibrary.libraryScript(named: "加入保险箱")).toScript()
        XCTAssertFalse(ScriptExecutor.shouldConfirm(script))
    }

    func testConfigRoundTripDrivesMenuAvailability() {
        let resolver: (String) -> URL? = { _ in nil }
        XCTAssertNil(VaultConfig.current)
        XCTAssertFalse(VaultConfig.isAvailable)
        let action = QuickMenuAction(id: UUID(), name: VaultConfig.actionName, icon: "lock.shield")
        XCTAssertFalse(QuickMenuPlan.isAvailable(action, resolveBundleID: resolver))

        VaultConfig.save(VaultConfig(bundlePath: "/tmp/不存在的镜像.sparsebundle"))
        XCTAssertEqual(VaultConfig.current?.bundlePath, "/tmp/不存在的镜像.sparsebundle")
        XCTAssertTrue(VaultConfig.isAvailable)
        XCTAssertTrue(QuickMenuPlan.isAvailable(action, resolveBundleID: resolver))

        VaultConfig.clear()
        XCTAssertNil(VaultConfig.current)
        XCTAssertFalse(VaultConfig.isAvailable)
    }

    func testVaultActionGroupsIntoMoreActions() {
        let action = QuickMenuAction(id: UUID(), name: VaultConfig.actionName, icon: "lock.shield")
        let sections = QuickMenuPlan.sections(for: [action])
        let more = sections.last
        XCTAssertEqual(more?.title, L10n.text("更多操作", "More Actions"))
        XCTAssertTrue(more?.actions.contains(action) ?? false)
    }

    func testPasswordValidationRules() {
        XCTAssertThrowsError(try VaultStore.validatePassword(""))
        XCTAssertThrowsError(try VaultStore.validatePassword(String(repeating: "a", count: 2000)))
        XCTAssertThrowsError(try VaultStore.validatePassword("含\n换行"))
        XCTAssertNoThrow(try VaultStore.validatePassword("测试密码123"))
    }

    func testVolumeDetectionAndDefaultLocations() throws {
        let plain = try directory()
        XCTAssertFalse(VaultStore.isVolumeMounted(at: plain))
        XCTAssertFalse(VaultStore.isVolumeMounted(at: plain.appendingPathComponent("缺失")))
        let bundle = VaultStore.defaultBundleURL()
        XCTAssertTrue(bundle.path.hasSuffix("/Vault/保险箱.sparsebundle"))
        XCTAssertTrue(bundle.path.hasPrefix(AppGroup.containerURLWithFallback.path))
    }
}
