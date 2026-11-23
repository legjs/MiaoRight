import Foundation

/// 动作使用频率统计:存 App Group,主 App 记录、Finder 扩展读取,
/// 用于右键菜单「常用动作置顶」与主窗口「最近使用」。
public enum ActionUsage {
    static let fileName = "action_usage.json"
    public static let changedNotification = Notification.Name("com.miaoright.usageChanged")

    /// 保留但不上「常用置顶/最近使用」的动作:功能可用、仍在右键菜单底部
    /// 危险分组中,但不做任何显眼曝光(如「彻底删除」,不经废纸篓易误删)。
    static let hiddenFromFrequent: Set<String> = [ActionID.deletePermanently]

    struct Entry: Codable {
        var count: Int
        var last: Date
    }

    struct Store: Codable {
        var entries: [String: Entry] = [:]
    }

    static var storageURL: URL {
        AppGroup.containerURLWithFallback.appendingPathComponent(fileName)
    }

    static func load() -> Store {
        guard let data = try? Data(contentsOf: storageURL),
              let store = try? JSONDecoder().decode(Store.self, from: data)
        else { return Store() }
        return store
    }

    /// 执行成功后记录(主 App 内调用)
    public static func record(_ actionName: String) {
        var store = load()
        store.entries[actionName, default: Entry(count: 0, last: Date())].count += 1
        store.entries[actionName]?.last = Date()
        if let data = try? JSONEncoder().encode(store) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    /// 按最近使用时间降序的前 N 个动作名(刚用过的排最前)
    public static func top(_ limit: Int) -> [String] {
        let store = load()
        let sorted = store.entries
            .filter { !hiddenFromFrequent.contains($0.key) }
            .sorted { $0.value.last > $1.value.last }
        return sorted.prefix(limit).map { entry in entry.key }
    }

    public static func count(_ actionName: String) -> Int {
        load().entries[actionName]?.count ?? 0
    }

    /// 「最近使用」:按最近时间排序的前 N 个
    public static func recent(_ limit: Int) -> [(name: String, count: Int, last: Date)] {
        let store = load()
        let sorted = store.entries
            .filter { !hiddenFromFrequent.contains($0.key) }
            .sorted { $0.value.last > $1.value.last }
        return sorted.prefix(limit).map { entry in
            (name: entry.key, count: entry.value.count, last: entry.value.last)
        }
    }
}
