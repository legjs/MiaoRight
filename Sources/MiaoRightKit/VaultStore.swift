import AppKit
import CoreGraphics
import Foundation
import MiaoRightShared
import Observation
import Security

/// 加密保险箱:hdiutil AES-256 sparse bundle,解锁=挂载到固定挂载点,锁定=卸载。
/// 密码只经 stdin 传给 hdiutil,不进命令行参数;记住密码为可选的钥匙串存储。
@MainActor @Observable
final class VaultStore {
    static let shared = VaultStore()

    enum State: Equatable { case missing, locked, unlocked }

    struct Entry: Identifiable, Equatable {
        let url: URL
        let isDirectory: Bool
        let size: Int64
        let modified: Date?
        var id: String { url.path }
        var sizeText: String? { isDirectory ? nil : ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    }

    private(set) var config: VaultConfig?
    private(set) var state: State = .missing
    private(set) var isBusy = false
    private(set) var busyText: String?
    private(set) var contents: [Entry] = []
    var lastError: String?

    /// 固定挂载点:镜像位置可变,挂载点保持确定性,便于崩溃恢复与加入/取出。
    let mountPoint = AppGroup.containerURLWithFallback.appendingPathComponent("VaultMount", isDirectory: true)
    private var sessionPassword: String?
    private var idleTimer: Timer?

    private static let autoLockKey = "vault.autoLockMinutes"
    private static let rememberKey = "vault.rememberPassword"

    /// 空闲自动锁定分钟数;0 表示不自动锁定。
    var autoLockMinutes: Int {
        get { AppGroup.standardDefaults.object(forKey: Self.autoLockKey) as? Int ?? 15 }
        set { AppGroup.standardDefaults.set(newValue, forKey: Self.autoLockKey) }
    }
    var rememberPassword: Bool {
        get { !AppGroup.isIsolated && AppGroup.standardDefaults.bool(forKey: Self.rememberKey) }
        set {
            AppGroup.standardDefaults.set(newValue, forKey: Self.rememberKey)
            if !newValue { VaultKeychain.remove() } else if let password = sessionPassword { VaultKeychain.save(password) }
        }
    }

    static func defaultParentDirectory() -> URL {
        AppGroup.containerURLWithFallback.appendingPathComponent("Vault", isDirectory: true)
    }
    static func defaultBundleURL() -> URL {
        defaultParentDirectory().appendingPathComponent(VaultConfig.defaultVolumeName + ".sparsebundle", isDirectory: true)
    }

    private init() {
        installLifecycleObservers()
    }

    // MARK: - 状态

    func refreshState() {
        config = VaultConfig.current
        guard let config, config.bundleExists else {
            state = .missing; contents = []; return
        }
        state = Self.isVolumeMounted(at: mountPoint) ? .unlocked : .locked
        if state == .unlocked { refreshContents() } else { contents = [] }
    }

    /// 挂载点是否真的挂着卷(而不是普通空目录)。
    nonisolated static func isVolumeMounted(at point: URL) -> Bool {
        guard (try? point.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true else { return false }
        return FileManager.default.fileExists(atPath: point.path)
    }

    // MARK: - 创建 / 解锁 / 锁定

    func createVault(password: String, sizeGB: Int) async {
        guard !isBusy else { return }
        isBusy = true; busyText = L10n.text("正在创建保险箱…", "Creating the vault…"); lastError = nil
        defer { isBusy = false }
        do {
            try Self.validatePassword(password)
            let bundle = Self.defaultBundleURL()
            if FileManager.default.fileExists(atPath: bundle.path) {
                throw ScriptError.executionFailed(L10n.text("保险箱已存在。", "The vault already exists."))
            }
            let mount = mountPoint
            try await Task.detached(priority: .userInitiated) {
                try Self.createBundle(bundle: bundle, sizeGB: sizeGB, password: password)
                VaultConfig.save(VaultConfig(bundlePath: bundle.path))
                try Self.attachBundle(bundle: bundle, mountPoint: mount, password: password)
            }.value
            sessionPassword = password
            if rememberPassword { VaultKeychain.save(password) }
            refreshState()
        } catch {
            VaultKeychain.remove()
            refreshState()
            lastError = Self.friendlyError(error)
        }
    }

    func unlock(password: String) async {
        guard !isBusy, let config else { return }
        isBusy = true; busyText = L10n.text("正在解锁保险箱…", "Unlocking the vault…"); lastError = nil
        defer { isBusy = false }
        do {
            try Self.validatePassword(password)
            let mount = mountPoint
            let bundle = config.bundleURL
            try await Task.detached(priority: .userInitiated) {
                try Self.attachBundle(bundle: bundle, mountPoint: mount, password: password)
            }.value
            sessionPassword = password
            if rememberPassword { VaultKeychain.save(password) }
            refreshState()
        } catch {
            refreshState()
            lastError = Self.friendlyError(error)
        }
    }

    func lock() {
        guard state == .unlocked else { return }
        sessionPassword = nil
        stopIdleMonitor()
        do {
            try Self.detachBundle(mountPoint: mountPoint)
        } catch {
            lastError = Self.friendlyError(error)
            return
        }
        refreshState()
    }

    /// 睡眠/退出前的尽力锁定:同步执行,失败不阻塞流程。
    func lockBestEffortSynchronously() {
        guard state == .unlocked else { return }
        sessionPassword = nil
        stopIdleMonitor()
        try? Self.detachBundle(mountPoint: mountPoint)
        refreshState()
    }

    /// 删除保险箱镜像与配置;要求先锁定,密码无法恢复数据。
    func destroyVault() async {
        guard !isBusy, let config else { return }
        if state == .unlocked { lock() }
        guard state == .locked else { return }
        isBusy = true; busyText = L10n.text("正在移除保险箱…", "Removing the vault…"); lastError = nil
        defer { isBusy = false }
        let bundle = config.bundleURL
        await Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: bundle)
        }.value
        VaultConfig.clear()
        VaultKeychain.remove()
        sessionPassword = nil
        refreshState()
    }

    // MARK: - 内容操作

    func refreshContents() {
        guard state == .unlocked else { contents = []; return }
        let mount = mountPoint
        Task.detached(priority: .utility) {
            let entries = Self.readContents(mount: mount)
            await MainActor.run { self.contents = entries }
        }
    }

    /// 把选中项移入保险箱根部;走 FileOperationJournal,撤销时移回原位。
    func addItems(_ urls: [URL]) async throws -> [URL] {
        guard state == .unlocked, let config else {
            throw ScriptError.executionFailed(L10n.text("保险箱已锁定。", "The vault is locked."))
        }
        let mount = mountPoint.path
        let bundle = config.bundlePath
        let title = L10n.text("加入保险箱", "Add to Vault")
        return try await Task.detached(priority: .userInitiated) { () -> [URL] in
            var moves: [FileMove] = []
            for url in urls {
                let path = url.standardizedFileURL.path
                // 保险箱自身与已挂载内容不重复收入。
                if path == mount || path.hasPrefix(mount + "/") { continue }
                if path == bundle || path.hasPrefix(bundle + "/") { continue }
                let destination = NativeActionExecutor.uniqueDestinationURL(
                    in: URL(fileURLWithPath: mount, isDirectory: true),
                    preferredName: url.deletingPathExtension().lastPathComponent,
                    pathExtension: url.pathExtension
                )
                moves.append(FileMove(source: url, destination: destination))
            }
            guard !moves.isEmpty else { return [] }
            return try FileOperationJournal.shared.perform(moves, title: title)
        }.value
    }

    /// 取出到指定目录:复制语义,保险箱内原件保留。
    func extractItems(_ urls: [URL], to destination: URL) async throws -> [URL] {
        guard state == .unlocked else {
            throw ScriptError.executionFailed(L10n.text("保险箱已锁定。", "The vault is locked."))
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScriptError.executionFailed(L10n.text("请选择有效的目标文件夹。", "Choose a valid destination folder."))
        }
        return try await Task.detached(priority: .userInitiated) { () -> [URL] in
            var results: [URL] = []
            for url in urls {
                let target = NativeActionExecutor.uniqueDestinationURL(
                    in: destination, preferredName: url.deletingPathExtension().lastPathComponent, pathExtension: url.pathExtension
                )
                try FileManager.default.copyItem(at: url, to: target)
                results.append(target)
            }
            FileOperationJournal.shared.recordOutputs(results)
            return results
        }.value
    }

    /// 直接删除保险箱内项目;调用方负责确认。
    func deleteItems(_ urls: [URL]) async throws -> Int {
        guard state == .unlocked else {
            throw ScriptError.executionFailed(L10n.text("保险箱已锁定。", "The vault is locked."))
        }
        let mount = mountPoint.path
        return try await Task.detached(priority: .userInitiated) { () -> Int in
            var deleted = 0
            for url in urls where url.path.hasPrefix(mount + "/") {
                try FileManager.default.removeItem(at: url)
                deleted += 1
            }
            return deleted
        }.value
    }

    nonisolated private static func readContents(mount: URL) -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let items = (try? FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return items.compactMap { url -> Entry? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let isDirectory = values.isDirectory == true
            return Entry(url: url, isDirectory: isDirectory,
                         size: isDirectory ? 0 : Int64(values.fileSize ?? 0),
                         modified: values.contentModificationDate)
        }.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.url.lastPathComponent.localizedStandardCompare(rhs.url.lastPathComponent) == .orderedAscending
        }
    }

    // MARK: - 自动锁定

    private func installLifecycleObservers() {
        guard !AppGroup.isIsolated else { return }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockBestEffortSynchronously() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.lockBestEffortSynchronously() }
        }
    }

    private func startIdleMonitor() {
        stopIdleMonitor()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.lockIfIdle() }
        }
    }

    private func stopIdleMonitor() {
        idleTimer?.invalidate(); idleTimer = nil
    }

    private func lockIfIdle() {
        guard state == .unlocked, autoLockMinutes > 0 else { return }
        if Self.systemIdleSeconds() >= Double(autoLockMinutes) * 60 { lock() }
    }

    /// 综合键鼠输入的空闲时长(最近一次活动距今的秒数)。
    static func systemIdleSeconds() -> Double {
        let types: [CGEventType] = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        return types.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }.min() ?? 0
    }

    // MARK: - 校验与进程调用

    static func validatePassword(_ password: String) throws {
        guard !password.isEmpty else {
            throw ScriptError.executionFailed(L10n.text("请输入保险箱密码。", "Enter the vault password."))
        }
        guard password.utf8.count <= 1024, password.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 }) else {
            throw ScriptError.executionFailed(L10n.text("密码过长或包含控制字符。", "The password is too long or contains control characters."))
        }
    }

    private static func friendlyError(_ error: Error) -> String {
        if let scriptError = error as? ScriptError { return scriptError.localizedDescription }
        let message = error.localizedDescription
        let lowered = message.lowercased()
        if lowered.contains("认证错误") || lowered.contains("authentication error") {
            return L10n.text("密码不正确。", "The password is incorrect.")
        }
        if lowered.contains("busy") || lowered.contains("占用") {
            return L10n.text("保险箱中的文件正在被使用，请关闭相关窗口后重试。", "Files in the vault are in use. Close them and try again.")
        }
        if lowered.contains("no space left") || lowered.contains("磁盘已满") {
            return L10n.text("保险箱空间已满，请先取出或删除部分内容。", "The vault is full. Extract or delete some content first.")
        }
        return message
    }

    // 以下进程封装都是纯阻塞调用,由调用方放到后台任务里执行。

    nonisolated static func runHDIUtil(_ arguments: [String], password: String? = nil) throws -> (status: Int32, message: String) {
        guard !AppGroup.isIsolated else {
            throw ScriptError.executionFailed(L10n.text("离屏测试不执行保险箱命令。", "Offscreen testing does not run vault commands."))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments
        let output = Pipe(), errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let input = Pipe()
        process.standardInput = password == nil ? FileHandle.nullDevice : input.fileHandleForReading
        if let password {
            // hdiutil -stdinpass 读取原始字节到 EOF:不能带换行,否则换行会成为密码的一部分。
            try input.fileHandleForWriting.write(contentsOf: Data(password.utf8))
        }
        try input.fileHandleForWriting.close()
        try process.run()
        try input.fileHandleForReading.close()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile() + errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    nonisolated static func createBundle(bundle: URL, sizeGB: Int, password: String) throws {
        try FileManager.default.createDirectory(at: bundle.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let result = try runHDIUtil([
            "create", bundle.path, "-volname", VaultConfig.defaultVolumeName, "-type", "SPARSEBUNDLE",
            "-fs", "APFS", "-encryption", "AES-256", "-stdinpass", "-size", "\(sizeGB)g"
        ], password: password)
        guard result.status == 0 else { throw ScriptError.executionFailed(result.message) }
    }

    nonisolated static func attachBundle(bundle: URL, mountPoint: URL, password: String) throws {
        try FileManager.default.createDirectory(at: mountPoint, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // 异常退出后卷可能仍挂着:视为已解锁,不重复挂载。
        if isVolumeMounted(at: mountPoint) { return }
        let result = try runHDIUtil(["attach", bundle.path, "-stdinpass", "-mountpoint", mountPoint.path, "-noverify"], password: password)
        guard result.status == 0 else { throw ScriptError.executionFailed(result.message) }
        // 关闭该卷的 Spotlight 索引,避免解锁期间文件名进入系统搜索。
        let marker = mountPoint.appendingPathComponent(".metadata_never_index")
        if !FileManager.default.fileExists(atPath: marker.path) { FileManager.default.createFile(atPath: marker.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
    }

    nonisolated static func detachBundle(mountPoint: URL) throws {
        guard isVolumeMounted(at: mountPoint) else { return }
        var lastMessage = ""
        for attempt in 0..<3 {
            let result = try runHDIUtil(["detach", mountPoint.path])
            if result.status == 0 { return }
            lastMessage = result.message
            if attempt < 2 { Thread.sleep(forTimeInterval: 1) }
        }
        throw ScriptError.executionFailed(lastMessage)
    }
}

/// 可选的「记住密码」走登录钥匙串;离屏测试一律不触达钥匙串。
enum VaultKeychain {
    private static let service = "com.miaoright.app.vault"
    private static let account = VaultConfig.defaultVolumeName

    static func save(_ password: String) {
        guard !AppGroup.isIsolated else { return }
        SecItemDelete(query() as CFDictionary)
        var attributes = query()
        attributes[kSecValueData as String] = Data(password.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        guard !AppGroup.isIsolated else { return nil }
        var search = query()
        search[kSecReturnData as String] = true
        search[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    static func remove() {
        guard !AppGroup.isIsolated else { return }
        SecItemDelete(query() as CFDictionary)
    }

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
