import Foundation
#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Service to check the status of the Finder Sync extension
enum ExtensionStatusService {
    /// Bundle identifier of the Finder Sync extension
    static let extensionBundleId = "com.miaoright.app.FinderSync"

    static func parsePluginKitEnabled(_ output: String) -> Bool {
        output
            .split(whereSeparator: \.isNewline)
            .contains { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("+") && trimmed.contains(extensionBundleId)
            }
    }

    private static func pluginKitOutput() -> String? {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-v", "-i", extensionBundleId]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return nil
        }
    }

    /// Check if the extension is registered and enabled
    static func isExtensionEnabled() -> Bool {
        guard let output = pluginKitOutput() else {
            return false
        }
        return parsePluginKitEnabled(output)
    }

    /// Check if the extension process is currently running
    static func isExtensionRunning() -> Bool {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", "MiaoRightFinder.appex/Contents/MacOS/MiaoRightFinder"]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Combined status check
    static func checkStatus() -> ExtensionStatus {
        let enabled = isExtensionEnabled()
        let running = isExtensionRunning()

        if enabled, running {
            return .active
        } else if enabled, !running {
            return .enabledNotRunning
        } else {
            return .disabled
        }
    }

    #if canImport(SwiftUI)
        static func shouldRefreshStatusOnScenePhaseChange(oldPhase: ScenePhase, newPhase: ScenePhase) -> Bool {
            oldPhase != .active && newPhase == .active
        }
    #endif
}

/// Extension status states
enum ExtensionStatus: Equatable, Sendable {
    case active // Enabled and running
    case enabledNotRunning // Enabled but Finder hasn't loaded it yet
    case disabled // Not enabled in System Settings

    var isUsable: Bool {
        self == .active || self == .enabledNotRunning
    }

    var statusText: String {
        switch self {
        case .active:
            "右键菜单已就绪"
        case .enabledNotRunning:
            "右键菜单等待访达加载"
        case .disabled:
            "需要启用 Finder 扩展"
        }
    }

    var icon: String {
        switch self {
        case .active:
            "checkmark.circle.fill"
        case .enabledNotRunning:
            "clock.fill"
        case .disabled:
            "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .active:
            "green"
        case .enabledNotRunning:
            "orange"
        case .disabled:
            "red"
        }
    }
}
