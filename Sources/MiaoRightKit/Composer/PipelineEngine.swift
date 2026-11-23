import AppKit
import Foundation
import MiaoRightShared

// MARK: - 组合动作数据模型(持久化为 Script.content 里的 JSON)

/// 一个由原子能力组合而成的动作。
/// 存储形态:Script(type: .composed).content = 本结构的 JSON。
struct ComposedAction: Codable {
    var version: Int = 1
    var steps: [ComposedStep]

    struct ComposedStep: Codable {
        var op: String // AtomRegistry 里的原子 id,如 "file.move"
        var params: [String: String] = [:]
    }

    func encoded() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func decode(_ content: String) -> ComposedAction? {
        guard let data = content.data(using: .utf8),
              let action = try? JSONDecoder().decode(ComposedAction.self, from: data)
        else { return nil }
        return action
    }

    /// 步骤里是否包含破坏性原子(移动/删除/重命名原文件)。
    /// 组合动作的确认弹窗由这个自动推导,不靠手写配置 —— 保护跟着积木走。
    var destructiveStepTitles: [String] {
        steps.compactMap { step in
            guard let op = AtomRegistry.operation(step.op) else { return nil }
            if op.id == "builtin.run", let name = step.params["name"],
               ScriptLibrary.libraryScript(named: name)?.confirmBeforeRun == true {
                return ActionNames.name(name)
            }
            return op.isDestructive ? op.title : nil
        }
    }
}

// MARK: - 管道执行引擎

/// 按顺序执行组合动作的步骤:第一步吃右键选中的文件,
/// 之后每一步吃上一步的产物;输出为「空」的旁路步骤(通知/弹窗)
/// 把输入原样传下去,不改变数据流。
enum PipelineEngine {
    /// 执行(供 ScriptExecutor 调用;返回给通知体系的完成描述)
    static func execute(content: String, paths: [String]) async -> Result<String, ScriptError> {
        // 1) 解析定义
        guard let action = ComposedAction.decode(content) else {
            return .failure(.executionFailed("组合动作定义无效"))
        }
        guard !action.steps.isEmpty else {
            return .failure(.executionFailed("组合动作没有任何步骤"))
        }
        // 2) 原子存在性检查(定义可能来自更高版本)
        for step in action.steps {
            guard AtomRegistry.operation(step.op) != nil else {
                return .failure(.executionFailed("未知原子能力「\(step.op)」"))
            }
        }

        // 3) 顺序执行,传递产物
        var value: PipelineValue = .files(paths.map { URL(fileURLWithPath: $0) })
        var lastDescription = ""
        do {
            for (index, step) in action.steps.enumerated() {
                guard let op = AtomRegistry.operation(step.op) else { continue }
                // 类型检查:文本步骤不吃文件,文件步骤不吃文本(any 两者皆可)
                if op.input != .any, op.input != .none, op.input != value.slot {
                    return .failure(.executionFailed(
                        "第 \(index + 1) 步「\(op.title)」需要\(op.input.displayName)输入,但上游传来的是\(value.slot.displayName)。可在编辑器中插入「取文件路径/取文件名」这类信息步骤做转换。"
                    ))
                }
                // 无输入需求的步骤(新建文件等)不吃管道值
                let stepInput: PipelineValue = op.input == .none ? .none : value
                let (output, description) = try await op.run(stepInput, step.params)
                // 旁路步骤(输出为空)不改数据流
                if case .none = output {
                    if op.input != .none { value = stepInput }
                } else {
                    value = output
                }
                lastDescription = description
            }
            return .success(lastDescription.isEmpty ? "组合动作已执行" : lastDescription)
        } catch let error as PipelineError {
            if case .cancelled = error { return .failure(.executionFailed("已取消")) }
            return .failure(.executionFailed(error.localizedDescription))
        } catch {
            return .failure(.executionFailed(error.localizedDescription))
        }
    }

    /// 组合动作是否需要执行前确认(含破坏性原子即确认)。
    /// 供 ScriptExecutor 的确认门使用,替代手写 confirmBeforeRun。
    static func needsConfirm(content: String) -> Bool {
        ComposedAction.decode(content)?.destructiveStepTitles.isEmpty == false
    }

    /// 确认弹窗文案
    static func confirmMessage(content: String, itemCount: Int) -> (title: String, info: String)? {
        guard let action = ComposedAction.decode(content),
              !action.destructiveStepTitles.isEmpty
        else { return nil }
        let itemWord = itemCount == 1 ? "1 个项目" : "\(itemCount) 个项目"
        let steps = action.destructiveStepTitles.joined(separator: "、")
        return (
            L10n.text("此菜单包含会改动或删除文件的操作", "This action modifies or removes files"),
            L10n.text(
                "将对 \(itemWord) 执行包含「\(steps)」的操作,继续吗?",
                "Run \"\(steps)\" on \(itemWord)?"
            )
        )
    }

    /// 弹出确认(主线程);true = 继续
    @MainActor
    static func presentConfirm(content: String, itemCount: Int) -> Bool {
        guard let message = confirmMessage(content: content, itemCount: itemCount) else { return true }
        let alert = NSAlert()
        alert.messageText = message.title
        alert.informativeText = message.info
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("继续", "Continue"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }
}
