import Foundation
import ServiceManagement
import XCTest
@testable import MiaoRightKit

final class LoginItemTests: XCTestCase {
    func testBuiltAppCanRegisterOutsideApplications() throws {
        var registrations = 0
        var removals = 0
        let app = URL(fileURLWithPath: "/workspace/MiaoRight/build/MiaoRight.app")
        try AppPolicies.setLoginItemEnabled(true, bundleURL: app, register: { registrations += 1 }, unregister: { removals += 1 })
        try AppPolicies.setLoginItemEnabled(false, bundleURL: app, register: { registrations += 1 }, unregister: { removals += 1 })
        XCTAssertEqual(registrations, 1)
        XCTAssertEqual(removals, 1)
    }

    func testUnbundledLaunchAndSystemErrorsAreReported() {
        var called = false
        XCTAssertThrowsError(try AppPolicies.setLoginItemEnabled(true, bundleURL: URL(fileURLWithPath: "/tmp/MiaoRightApp"), register: { called = true }))
        XCTAssertFalse(called)
        struct RegistrationFailure: Error {}
        XCTAssertThrowsError(try AppPolicies.setLoginItemEnabled(true, bundleURL: URL(fileURLWithPath: "/Applications/MiaoRight.app"), register: { throw RegistrationFailure() })) { error in
            XCTAssertTrue(error is RegistrationFailure)
        }
    }

    func testSystemApprovalRemainsDistinctFromEnabled() {
        XCTAssertEqual(AppPolicies.loginItemState(statusProvider: { .enabled }), .enabled)
        XCTAssertEqual(AppPolicies.loginItemState(statusProvider: { .requiresApproval }), .requiresApproval)
        XCTAssertTrue(AppPolicies.loginItemState(statusProvider: { .requiresApproval }).isRequested)
        XCTAssertEqual(AppPolicies.loginItemState(statusProvider: { .notRegistered }), .disabled)
        XCTAssertFalse(AppPolicies.loginItemState(statusProvider: { .notRegistered }).isRequested)
        XCTAssertEqual(AppPolicies.loginItemState(statusProvider: { .notFound }), .unavailable)
    }
}
