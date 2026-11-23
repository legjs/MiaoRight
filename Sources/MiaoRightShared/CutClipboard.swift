import Foundation

/// 「剪切」状态:Finder 原生不支持文件剪切,这里把要移动的文件路径记录在
/// App Group 容器中,之后在目标文件夹执行「粘贴」时由主 App 完成移动。
public struct CutClipboardState: Codable {
    public var paths: [String]
    public var timestamp: Date
}

public enum CutClipboard {
    private static let fileName = "cut_clipboard.json"

    public static var storageURL: URL {
        AppGroup.containerURLWithFallback.appendingPathComponent(fileName)
    }

    public static func load() -> CutClipboardState? {
        guard let data = try? Data(contentsOf: storageURL),
              let state = try? JSONDecoder().decode(CutClipboardState.self, from: data)
        else {
            return nil
        }
        // 剪切状态只保留 10 分钟,避免残留导致意外的移动。
        guard Date().timeIntervalSince(state.timestamp) < 600 else {
            clear()
            return nil
        }
        return state
    }

    public static func save(paths: [String]) {
        let state = CutClipboardState(paths: paths, timestamp: Date())
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: storageURL)
    }

    /// 取出并清空剪切状态(仅供粘贴流程使用)。
    public static func takePaths() -> [String] {
        guard let state = load() else { return [] }
        clear()
        return state.paths.filter { FileManager.default.fileExists(atPath: $0) }
    }
}
