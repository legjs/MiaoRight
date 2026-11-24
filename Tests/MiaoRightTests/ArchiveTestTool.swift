import Foundation

enum ArchiveTestTool {
    static var executableURL: URL {
        if let path = ProcessInfo.processInfo.environment["MIAORIGHT_TEST_7ZZ_PATH"] {
            return URL(fileURLWithPath: path)
        }
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        #if arch(x86_64)
        return repository.appendingPathComponent("ThirdParty/7zip/7zz-x86_64")
        #else
        return repository.appendingPathComponent("ThirdParty/7zip/7zz")
        #endif
    }
}
