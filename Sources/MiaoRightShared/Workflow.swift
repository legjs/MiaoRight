import Foundation

/// 可视化工作流:用户把内置动作串成流水线,保存为一个右键菜单项。
/// 节点间用「输入指针」表达数据流向(node.input = 上一步节点 id,
/// 为 nil 的是链头,作用于 Finder 选中的文件)。
public struct Workflow: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var icon: String        // emoji
    public var enabled: Bool
    public var nodes: [WorkflowNode]

    public init(id: UUID = UUID(), name: String, icon: String, enabled: Bool = true, nodes: [WorkflowNode]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.enabled = enabled
        self.nodes = nodes
    }

    /// 链头节点(无输入来源的节点,按横向位置排序)
    public var headNodes: [WorkflowNode] {
        nodes
            .filter { node in node.input == nil }
            .sorted { $0.x < $1.x }
    }

    /// 某节点的直接下游(按横向位置排序;分支时依次执行)
    public func nextNodes(after node: WorkflowNode) -> [WorkflowNode] {
        nodes
            .filter { $0.input == node.id }
            .sorted { $0.x < $1.x }
    }

    public func node(withID id: UUID) -> WorkflowNode? {
        nodes.first { $0.id == id }
    }
}

public struct WorkflowNode: Codable, Identifiable, Equatable {
    public var id: UUID
    public var actionName: String   // 内置动作名(100 个动作库的键)
    public var x: Double
    public var y: Double
    public var input: UUID?         // 数据来源节点;nil = 链头

    public init(id: UUID = UUID(), actionName: String, x: Double, y: Double, input: UUID? = nil) {
        self.id = id
        self.actionName = actionName
        self.x = x
        self.y = y
        self.input = input
    }
}

public enum WorkflowStore {
    static let fileName = "workflows.json"
    public static let changedNotification = Notification.Name("com.miaoright.workflowsChanged")

    public static var storageURL: URL {
        AppGroup.containerURLWithFallback.appendingPathComponent(fileName)
    }

    public static func load() -> [Workflow] {
        guard let data = try? Data(contentsOf: storageURL),
              let list = try? JSONDecoder().decode([Workflow].self, from: data)
        else { return [] }
        return list
    }

    public static func save(_ workflows: [Workflow]) {
        guard let data = try? JSONEncoder().encode(workflows) else { return }
        try? data.write(to: storageURL, options: .atomic)
        guard !AppGroup.isIsolated else { return }
        DistributedNotificationCenter.default().postNotificationName(
            changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    public static func upsert(_ workflow: Workflow) {
        var list = load()
        if let idx = list.firstIndex(where: { $0.id == workflow.id }) {
            list[idx] = workflow
        } else {
            list.append(workflow)
        }
        save(list)
    }

    public static func remove(id: UUID) {
        var list = load()
        list.removeAll { $0.id == id }
        save(list)
    }

    /// 预置模板:首次启动写入,开箱即用
    @discardableResult
    public static func seedTemplatesIfNeeded() -> [Workflow] {
        if FileManager.default.fileExists(atPath: storageURL.path) { return load() }

        func node(_ action: String, x: Double, y: Double, input: UUID? = nil) -> WorkflowNode {
            WorkflowNode(actionName: action, x: x, y: y, input: input)
        }

        // 📸 照片归档:HEIC 转 JPG → 按日期整理
        let photoHead = node("HEIC 转 JPG", x: 60, y: 60)
        let photoTail = node("按日期整理", x: 320, y: 60, input: photoHead.id)
        let photo = Workflow(name: "照片归档", icon: "📸", nodes: [photoHead, photoTail])

        // 🧹 清理下载文件夹:按类型整理 → 清理 .DS_Store → 清除空文件夹
        let clean1 = node("按类型整理", x: 60, y: 60)
        let clean2 = node("清理 .DS_Store 文件", x: 320, y: 60, input: clean1.id)
        let clean3 = node("清除空文件夹", x: 580, y: 60, input: clean2.id)
        let clean = Workflow(name: "清理下载文件夹", icon: "🧹", nodes: [clean1, clean2, clean3])

        // 📤 发给别人:压缩为 ZIP → 隔空投送
        let send1 = node("压缩为 ZIP", x: 60, y: 60)
        let send2 = node("隔空投送…", x: 320, y: 60, input: send1.id)
        let send = Workflow(name: "发给别人", icon: "📤", nodes: [send1, send2])

        let templates = [photo, clean, send]
        save(templates)
        return templates
    }
}
