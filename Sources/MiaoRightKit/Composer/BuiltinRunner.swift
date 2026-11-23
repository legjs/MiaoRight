import Foundation
import MiaoRightShared

/// 按名称调用「内置菜单」(原 100 个内置动作)。
/// 组合菜单可以把它当作一块积木,从而复用全部内置能力;
/// 也是旧工作流迁移的翻译基础。
enum BuiltinRunner {
    /// 快照执行前的目录状态,用于检测菜单「产生了哪些新文件」(产物传递)
    final class ProducedTracker {
        let startDate = Date()
        let dirs: [URL]

        init(paths: [String]) {
            var seen = Set<String>()
            var dirs: [URL] = []
            for path in paths {
                let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
                if seen.insert(dir.standardizedFileURL.path).inserted {
                    dirs.append(dir)
                }
            }
            self.dirs = dirs
        }

        func produced(excluding originals: [String]) -> [String] {
            let originalSet = Set(originals)
            var out: [String] = []
            for dir in dirs {
                let items = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey])) ?? []
                for item in items {
                    let path = item.path
                    if originalSet.contains(path) { continue }
                    let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let modified, modified >= startDate {
                        out.append(path)
                    }
                }
            }
            return out.sorted()
        }
    }

    @MainActor
    private static func executeUIActionOnMain(
        _ action: NativeAction,
        paths: [String],
        parameter: String?
    ) throws -> String {
        try NativeActionExecutor.executeUIAction(action, paths: paths, parameter: parameter)
    }

    /// 按内置菜单名执行:原生优先,脚本菜单回退 shell。返回 (描述, 差分产物)
    @MainActor
    static func run(named name: String, inputPaths: [String]) async throws -> (String, [String]) {
        guard let library = ScriptLibrary.libraryScript(named: name) else {
            throw PipelineError.param("内置菜单不存在:\(name)")
        }
        let tracker = ProducedTracker(paths: inputPaths)

        let message: String
        if let action = NativeAction(rawValue: name), action.requiresNativeRuntime {
            if NativeActionExecutor.requiresMainActorUI(action) {
                message = try executeUIActionOnMain(action, paths: inputPaths, parameter: nil)
            } else {
                message = try NativeActionExecutor.execute(action, paths: inputPaths, parameter: nil)
            }
        } else {
            switch library.type {
            case .bash:
                let result = ScriptExecutor.runProcess(
                    executableURL: URL(fileURLWithPath: "/bin/bash"),
                    arguments: ["-c", library.content, "bash"] + inputPaths)
                message = try result.get()
            case .applescript:
                let script = "on run argv\n\(library.content)\nend run"
                let result = ScriptExecutor.runProcess(
                    executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                    arguments: ["-e", script] + inputPaths)
                message = try result.get()
            case .automator:
                throw PipelineError.runtime("Automator 菜单暂不支持在组合菜单中使用")
            case .composed:
                // 嵌套组合:交给管道引擎
                let result = await PipelineEngine.execute(content: library.content, paths: inputPaths)
                message = try result.get()
            }
        }
        return (message, tracker.produced(excluding: inputPaths))
    }
}
