import Foundation

/// App Group identifier and container access shared by the host app and the
/// Finder Sync extension. On macOS the group id does not need a team-id prefix
/// for local development builds.
public enum AppGroup {
    public static let identifier = "group.com.miaoright.app"
    public static var isIsolated: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["MIAORIGHT_TEST_STORAGE"] != nil || env["MIAORIGHT_OFFSCREEN_TESTING"] == "1"
            || env["XCTestSessionIdentifier"] != nil || env["XCTestConfigurationFilePath"] != nil
    }

    private static var testContainerURL: URL? {
        let env = ProcessInfo.processInfo.environment
        guard isIsolated else { return nil }
        let url = env["MIAORIGHT_TEST_STORAGE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent("MiaoRightTests/AppGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    public static var containerURL: URL? {
        testContainerURL ?? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Container URL with a fallback to Application Support so host-side tooling
    /// keeps working if the App Group is unavailable. The sandboxed extension
    /// cannot use the fallback, so callers there must handle nil.
    public static var containerURLWithFallback: URL {
        containerURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MiaoRight", isDirectory: true)
    }

    public static var userDefaults: UserDefaults? {
        UserDefaults(suiteName: isolatedDefaultsDomain ?? identifier)
    }

    public static var standardDefaults: UserDefaults {
        if let domain = isolatedDefaultsDomain { return UserDefaults(suiteName: domain + ".preferences")! }
        return UserDefaults.standard
    }

    private static var isolatedDefaultsDomain: String? {
        testContainerURL.map { url in
            let hash = url.path.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
            return identifier + ".tests." + String(hash, radix: 16)
        }
    }
}
