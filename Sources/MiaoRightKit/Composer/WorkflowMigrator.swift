import Foundation
import MiaoRightShared

/// 旧工作流 → 组合菜单 一次性迁移。
/// 把 workflows.json 里的每条工作流按链序翻译成 builtin.run 步骤的组合菜单,
/// 写入 scripts.json;原文件改名为 workflows.migrated.json 保留备份(幂等锚点)。
public enum WorkflowMigrator {
    @MainActor
    public static func migrateIfNeeded(store: ScriptStore) {
        let source = WorkflowStore.storageURL
        guard FileManager.default.fileExists(atPath: source.path) else { return }

        let workflows = WorkflowStore.load()
        let existingNames = Set(store.scripts.map(\.name))

        var pending: [Script] = []
        for workflow in workflows {
            // 链序:链头按横向位置排序
            let chain = orderedChain(of: workflow)
            guard !chain.isEmpty else { continue }
            guard !existingNames.contains(workflow.name) else { continue } // 同名跳过(重复迁移保护)

            let steps = chain.map { node in
                ComposedAction.ComposedStep(op: "builtin.run", params: ["name": node.actionName])
            }
            let script = Script(
                name: workflow.name,
                type: .composed,
                content: ComposedAction(steps: steps).encoded(),
                isEnabled: workflow.enabled,
                icon: "square.stack.3d.up",
                appliesTo: .allItems,
                libraryCategory: ScriptStore.topCategoryKey
            )
            pending.append(script)
        }

        store.appendScriptsForMigration(pending)
        // 改名锚点:无论是否翻译出条目,都标志着迁移已处理
        let archived = source.deletingLastPathComponent().appendingPathComponent("workflows.migrated.json")
        try? FileManager.default.removeItem(at: archived)
        try? FileManager.default.moveItem(at: source, to: archived)
    }

    /// 工作流是"链头 + 下游"的树;按迁移时的简单语义取主链(链头 x 序)
    private static func orderedChain(of workflow: Workflow) -> [WorkflowNode] {
        var chain: [WorkflowNode] = []
        var current: WorkflowNode? = workflow.headNodes.first
        let allByID = Dictionary(uniqueKeysWithValues: workflow.nodes.map { ($0.id, $0) })
        var visited = Set<UUID>()
        while let node = current, visited.insert(node.id).inserted {
            chain.append(node)
            let next = workflow.nextNodes(after: node).first ?? allByID[node.input == nil ? node.id : UUID()] // 单链语义
            current = workflow.nextNodes(after: node).first
        }
        return chain
    }
}
