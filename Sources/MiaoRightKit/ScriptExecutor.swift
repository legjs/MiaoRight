import AppKit
import MiaoRightShared
import Foundation
import os.log
@preconcurrency import UserNotifications

private let executorLogger = Logger(subsystem: "com.miaoright.app", category: "ScriptExecutor")

/// Result of script execution for UI feedback
public struct ScriptExecutionResult: Sendable {
    public let scriptName: String
    public let success: Bool
    public let output: String
    public let error: String?
    public let timestamp: Date
    public let outputPaths: [String]
    public let undoID: UUID?

    static func success(scriptName: String, output: String, outputPaths: [String] = [], undoID: UUID? = nil) -> ScriptExecutionResult {
        ScriptExecutionResult(scriptName: scriptName, success: true, output: output, error: nil, timestamp: Date(), outputPaths: outputPaths, undoID: undoID)
    }

    static func failure(scriptName: String, error: String, outputPaths: [String] = [], undoID: UUID? = nil) -> ScriptExecutionResult {
        ScriptExecutionResult(scriptName: scriptName, success: false, output: "", error: error, timestamp: Date(), outputPaths: outputPaths, undoID: undoID)
    }
}

/// Execution request passed via file from extension to host app
/// (DistributedNotificationCenter strips userInfo between processes)
struct ExecutionRequest: Codable {
    let scriptId: UUID
    let paths: [String]
    let timestamp: Date
    let requestId: UUID // Unique ID to prevent duplicate processing
    /// 动作附加参数,例如「移动到/复制到」的目标文件夹路径。
    let parameter: String?
    /// 工作流执行请求携带的工作流 ID
    let workflowId: UUID?

    init(
        scriptId: UUID,
        paths: [String],
        timestamp: Date = Date(),
        requestId: UUID = UUID(),
        parameter: String? = nil,
        workflowId: UUID? = nil
    ) {
        self.scriptId = scriptId
        self.paths = paths
        self.timestamp = timestamp
        self.requestId = requestId
        self.parameter = parameter
        self.workflowId = workflowId
    }

    private enum CodingKeys: String, CodingKey {
        case scriptId, paths, timestamp, requestId, parameter, workflowId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scriptId = try container.decode(UUID.self, forKey: .scriptId)
        paths = try container.decode([String].self, forKey: .paths)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        requestId = try container.decode(UUID.self, forKey: .requestId)
        parameter = try container.decodeIfPresent(String.self, forKey: .parameter)
        workflowId = try container.decodeIfPresent(UUID.self, forKey: .workflowId)
    }
}

protocol ExecutionRequestFileManaging {
    func fileExists(atPath path: String) -> Bool
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func removeItem(at URL: URL) throws
    func readData(at URL: URL) throws -> Data
}

extension FileManager: ExecutionRequestFileManaging {
    func readData(at URL: URL) throws -> Data {
        try Data(contentsOf: URL)
    }
}

enum PendingExecutionFileConsumer {
    static func consume(
        from pendingURL: URL,
        fileManager: ExecutionRequestFileManaging = FileManager.default,
        claimID: UUID = UUID()
    ) throws -> Data? {
        guard fileManager.fileExists(atPath: pendingURL.path) else { return nil }

        // Rename within the App Group directory to atomically claim this request.
        // The Finder extension can safely write the next atomic request without
        // the host accidentally deleting it after reading the previous payload.
        let claimedURL = pendingURL
            .deletingLastPathComponent()
            .appendingPathComponent(".pending_execution.claimed-\(claimID.uuidString).json")
        try fileManager.moveItem(at: pendingURL, to: claimedURL)

        do {
            let data = try fileManager.readData(at: claimedURL)

            // Fail closed: a request is executable only after its claimed file
            // has been removed successfully, preventing duplicate execution.
            try fileManager.removeItem(at: claimedURL)
            return data
        } catch {
            // Restore the claim for a later attempt when no newer request has
            // taken the canonical pending path. Never execute on this failure.
            if !fileManager.fileExists(atPath: pendingURL.path) {
                try? fileManager.moveItem(at: claimedURL, to: pendingURL)
            }
            throw error
        }
    }
}

/// Where an action's output should be surfaced once it finishes.
/// This is the single, pure decision computed from a script's `outputMode`
/// (and, for `.standard`, the existing self-notification suppression), so the
/// surfacing logic stays unit-testable away from the side effects.
enum OutputSink: Equatable {
    case none // Surface nothing.
    case standardNotification // Today's "<name> completed/failed" notification path.
    case clipboard(String) // Copy this text to the clipboard.
    case notification(String) // Post a notification whose body is this text.
    case window(String) // Show this text in a result window.
}

/// Executes scripts with selected file paths
public final class ScriptExecutor: @unchecked Sendable {
    public static let shared = ScriptExecutor()

    /// Published execution results for UI to observe
    @MainActor static var lastResult: ScriptExecutionResult?

    /// Notification posted when execution completes
    static let executionCompletedNotification = Notification.Name("com.miaoright.executionCompleted")

    /// Notification posted when an action with `.showResult` finishes, so the host
    /// app can present a result window. `userInfo["result"]` carries the
    /// `ScriptExecutionResult`.
    public static let showResultNotification = Notification.Name("com.miaoright.showResult")

    /// Output longer than this is trimmed before it goes into a notification body.
    static let notificationOutputLimit = 240

    /// File-based IPC: extension writes here, host app reads
    private static var pendingExecutionURL: URL? {
        guard let containerURL = AppGroup.containerURL else {
            return nil
        }
        return containerURL.appendingPathComponent("pending_execution.json")
    }

    /// Lock file for cross-process synchronization
    private static var lockFileURL: URL? {
        guard let containerURL = AppGroup.containerURL else {
            return nil
        }
        return containerURL.appendingPathComponent(".execution.lock")
    }

    private let queue = DispatchQueue(label: "com.miaoright.executor", qos: .userInitiated)

    /// Track recently processed request IDs to prevent duplicates
    private var processedRequestIds = Set<UUID>()
    private let processedIdsLock = NSLock()

    /// Maximum age for processed request IDs (10 seconds)
    private let maxProcessedIdAge: TimeInterval = 10

    private init() {
        guard !AppGroup.isIsolated else { return }
        NSLog("[ScriptExecutor] Initializing with file-based IPC")
        executorLogger.info("Initializing ScriptExecutor")

        // Listen for execution signal from extension (notification is just a trigger)
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.miaoright.executeScript"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            NSLog("[ScriptExecutor] Received executeScript signal, checking for pending request file...")
            self?.processPendingExecution()
        }

        // 轮询兜底:分布式通知可能因锁屏/会话状态丢失,
        // 让 pending 文件总能被认领(每 2 秒一次 stat,开销可忽略)
        let poll = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.processPendingExecution()
        }
        RunLoop.main.add(poll, forMode: .common)
    }

    public func processPendingExecutionAfterLaunchRequest() {
        guard !AppGroup.isIsolated else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.processPendingExecution()
        }
    }

    /// Process pending execution request from file with proper locking
    private func processPendingExecution() {
        // Process on serial queue to prevent concurrent access from multiple triggers
        queue.async { [weak self] in
            self?.processPendingExecutionLocked()
        }
    }

    /// Actual processing with file locking - must be called on queue
    private func processPendingExecutionLocked() {
        guard let pendingURL = Self.pendingExecutionURL,
              let lockURL = Self.lockFileURL
        else {
            NSLog("[ScriptExecutor] No pending execution URL (App Group not available)")
            return
        }

        // Create lock file if needed
        if !FileManager.default.fileExists(atPath: lockURL.path) {
            FileManager.default.createFile(atPath: lockURL.path, contents: nil)
        }

        // Open lock file for exclusive locking
        let lockFd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard lockFd >= 0 else {
            NSLog("[ScriptExecutor] Failed to open lock file")
            return
        }
        defer { close(lockFd) }

        // Try to acquire exclusive lock (non-blocking)
        guard flock(lockFd, LOCK_EX | LOCK_NB) == 0 else {
            // Another process holds the lock, skip this attempt
            return
        }
        defer { flock(lockFd, LOCK_UN) }

        do {
            guard let data = try PendingExecutionFileConsumer.consume(from: pendingURL) else {
                return
            }
            NSLog("[ScriptExecutor] Claimed pending execution request")

            // Decode request - handle missing requestId for backward compatibility
            let request: ExecutionRequest
            if let decoded = try? JSONDecoder().decode(ExecutionRequest.self, from: data) {
                request = decoded
            } else {
                // Legacy format without requestId - decode manually
                struct LegacyRequest: Codable {
                    let scriptId: UUID
                    let paths: [String]
                    let timestamp: Date
                }
                let legacy = try JSONDecoder().decode(LegacyRequest.self, from: data)
                request = ExecutionRequest(scriptId: legacy.scriptId, paths: legacy.paths, timestamp: legacy.timestamp)
            }

            // Check for duplicate request
            processedIdsLock.lock()
            let alreadyProcessed = processedRequestIds.contains(request.requestId)
            if !alreadyProcessed {
                processedRequestIds.insert(request.requestId)
            }
            processedIdsLock.unlock()

            if alreadyProcessed {
                NSLog("[ScriptExecutor] Ignoring duplicate request: \(request.requestId)")
                return
            }

            // Ignore stale requests (older than 10 seconds)
            if Date().timeIntervalSince(request.timestamp) > maxProcessedIdAge {
                NSLog("[ScriptExecutor] Ignoring stale request from \(request.timestamp)")
                return
            }

            NSLog("[ScriptExecutor] Processing request: scriptId=\(request.scriptId), requestId=\(request.requestId), itemCount=\(request.paths.count)")

            // Find and execute the script on main thread
            DispatchQueue.main.async {
                // License-gate windows never mount ContentView, so ScriptStore
                // would stay empty and Finder actions would miss. Load here so
                // a live trial or license can still run from the host app.
                ScriptStore.shared.loadIfNeeded()
                if let script = ScriptStore.shared.scripts.first(where: { $0.id == request.scriptId }) {
                    // Ask before running, if this action opts in. The decision
                    // (`shouldConfirm`) is pure and unit-tested; only the alert
                    // presentation here is non-headless. Cancel aborts the run.
                    if Self.shouldConfirm(script), !self.confirmRun(of: script, itemCount: request.paths.count) {
                        NSLog("[ScriptExecutor] User cancelled confirmed action: \(script.name)")
                        return
                    }

                    NSLog("[ScriptExecutor] Found script: \(script.name), executing...")
                    Task {
                        await self.execute(script: script, withPaths: request.paths, parameter: request.parameter)
                    }
                } else {
                    NSLog("[ScriptExecutor] Script not found for id: \(request.scriptId)")
                }
            }

            // Clean up old processed IDs periodically
            cleanupOldProcessedIds()
        } catch {
            NSLog("[ScriptExecutor] Failed to process pending execution: \(error)")
        }
    }

    /// Remove processed request IDs older than maxProcessedIdAge
    private func cleanupOldProcessedIds() {
        // Simple cleanup: if we have too many IDs, clear them all
        // (A more sophisticated approach would track timestamps per ID)
        processedIdsLock.lock()
        if processedRequestIds.count > 100 {
            processedRequestIds.removeAll()
        }
        processedIdsLock.unlock()
    }

    /// Execute a script with the given file paths
    func execute(script: Script, withPaths paths: [String], parameter: String? = nil) async {
        if let action = NativeAction(script: script), action == .compressionOptions || action == .batchRenamePreview || action == .addToVault {
            await MainActor.run {
                switch action {
                case .compressionOptions:
                    FileTaskPresentation.shared.present(.compress, urls: paths.map { URL(fileURLWithPath: $0) }, encrypted: parameter == "encrypted")
                case .batchRenamePreview: FileTaskPresentation.shared.present(.rename, urls: paths.map { URL(fileURLWithPath: $0) })
                default: VaultTaskPresentation.shared.present(urls: paths.map { URL(fileURLWithPath: $0) })
                }
            }
            return
        }
        let id = UUID()
        if NativeAction(script: script) == .extractZIPHere, !AppGroup.isIsolated {
            await extractWithProgress(script: script, paths: paths, parameter: parameter, id: id)
            return
        }
        await FileTaskContext.$executionID.withValue(id) {
            await executeTracked(script: script, withPaths: paths, parameter: parameter, executionID: id)
        }
    }

    @MainActor
    private func extractWithProgress(script: Script, paths: [String], parameter: String?, id: UUID) async {
        let presentation = FileTaskPresentation.shared
        guard !presentation.isBusy else { return }
        presentation.isBusy = true
        presentation.extractionProgress = nil
        let showProgress = Task {
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            presentation.showExtractionProgress()
        }
        defer {
            showProgress.cancel()
            presentation.closeExtractionProgress()
            presentation.isBusy = false
        }
        await SevenZipArchive.$extractionProgress.withValue({ fraction in
            Task { @MainActor in
                guard !showProgress.isCancelled else { return }
                presentation.extractionProgress = fraction
            }
        }) {
            await FileTaskContext.$executionID.withValue(id) {
                await executeTracked(script: script, withPaths: paths, parameter: parameter, executionID: id)
            }
        }
    }

    private func executeTracked(script: Script, withPaths paths: [String], parameter: String?, executionID: UUID) async {
        let result: Result<String, ScriptError>
        if let nativeAction = NativeAction(script: script), nativeAction.requiresNativeRuntime {
            result = await executeNativeAction(nativeAction, paths: paths, parameter: parameter)
        } else {
            result = switch script.type {
            case .bash:
                await Self.executeBash(content: script.content, paths: paths)
            case .applescript:
                await Self.executeAppleScript(content: script.content, paths: paths)
            case .automator:
                await executeAutomator(workflowPath: script.content, paths: paths)
            case .composed:
                await PipelineEngine.execute(content: script.content, paths: paths)
            }
        }

        // Create execution result for UI
        let summary = FileOperationJournal.shared.summary(for: executionID)
        let executionResult: ScriptExecutionResult = switch result {
        case let .success(output):
            .success(scriptName: script.name, output: output, outputPaths: summary.outputPaths, undoID: summary.undoID)
        case let .failure(error):
            .failure(scriptName: script.name, error: error.localizedDescription, outputPaths: summary.outputPaths, undoID: summary.undoID)
        }

        if executionResult.success {
            ActionUsage.record(script.name)
        }

        // Update on main thread and post notification
        await MainActor.run {
            ScriptExecutor.lastResult = executionResult
            if !executionResult.outputPaths.isEmpty || executionResult.undoID != nil { ActionResultPresentation.shared.present(executionResult) }
            NotificationCenter.default.post(
                name: ScriptExecutor.executionCompletedNotification,
                object: nil,
                userInfo: ["result": executionResult]
            )
        }

        // Surface the output according to the action's chosen output mode. The
        // decision (which sink) is pure and unit-tested; only acting on it here
        // touches AppKit/notifications. Acting on a non-standard sink replaces
        // the standard completion notification so we never double-notify.
        await surface(sink: Self.outputSink(for: script, result: executionResult), result: executionResult, script: script)

}

    // MARK: - Output Surfacing

    /// Pure decision: where this action's output should go once it finishes.
    /// `.standard` keeps the existing behavior, including the self-notification
    /// suppression (scripts that already raise their own notification stay silent).
    /// Any explicitly chosen mode overrides that suppression and surfaces the
    /// result the way the user asked.
    static func outputSink(for script: Script, result: ScriptExecutionResult) -> OutputSink {
        switch script.outputMode {
        case .standard:
            // Keep today's behavior: scripts that raise their own notification
            // (display notification / osascript -e) stay silent so we don't
            // double up. Any explicit mode below overrides this suppression.
            scriptSelfNotifies(script) ? .none : .standardNotification
        case .copyResult:
            // On failure, don't wipe the clipboard with "" and claim success;
            // surface the real error via the standard notification path.
            result.success ? .clipboard(result.output) : .standardNotification
        case .notifyResult:
            // On failure, surface the real error instead of "Finished (no output)".
            result.success ? .notification(result.output) : .standardNotification
        case .showResult:
            .window(result.output)
        }
    }

    // MARK: - Run Confirmation

    /// Pure decision: should the user be asked to confirm before this action runs?
    /// 组合动作(composed)按定义中是否含破坏性原子自动推导 ——
    /// 保护跟着积木走,不依赖手写配置;其他类型沿用显式 confirmBeforeRun。
    static func shouldConfirm(_ script: Script) -> Bool {
        // 这些入口只打开内嵌预览；确认按钮位于实际执行的内嵌页面。
        if let action = NativeAction(script: script), [.batchRenamePreview, .addToVault].contains(action) { return false }
        if script.type == .composed {
            return PipelineEngine.needsConfirm(content: script.content)
        }
        return script.confirmBeforeRun
    }

    /// Presents the confirmation alert and returns whether the user chose to run.
    /// This is intentionally the only non-headless part of the confirmation flow;
    /// the decision of *whether* to confirm lives in `shouldConfirm`.
    @MainActor
    private func confirmRun(of script: Script, itemCount: Int) -> Bool {
        guard !AppGroup.isIsolated else { return false }
        if script.type == .composed {
            return PipelineEngine.presentConfirm(content: script.content, itemCount: itemCount)
        }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        let count = script.name == ActionID.paste ? (CutClipboard.load()?.paths.count ?? 0) : itemCount
        let title = ActionNames.name(script.name)
        alert.messageText = L10n.text("对 \(count) 个项目执行“\(title)”？", "Run “\(title)” on \(count) items?")
        alert.informativeText = L10n.text("此操作会修改或移动文件，请确认后继续。", "This action changes or moves files. Confirm to continue.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("继续", "Continue"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))

        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Acts on a previously decided `OutputSink`. Kept off the pure decision path
    /// so the decision stays testable.
    private func surface(sink: OutputSink, result: ScriptExecutionResult, script: Script) async {
        guard !AppGroup.isIsolated else { return }
        switch sink {
        case .none:
            break
        case .standardNotification:
            maybeNotifyUser(for: result, script: script)
        case let .clipboard(text):
            await MainActor.run {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(text, forType: .string)
            }
            // Confirm the copy itself, since clipboard writes are otherwise silent.
            postResultNotification(title: script.name, body: "Result copied to clipboard")
        case let .notification(text):
            let body = Self.truncatedForNotification(text)
            postResultNotification(title: script.name, body: body.isEmpty ? "Finished (no output)" : body)
        case .window:
            await MainActor.run {
                NotificationCenter.default.post(
                    name: Self.showResultNotification,
                    object: nil,
                    userInfo: ["result": result]
                )
            }
        }
    }

    /// Trim output to a notification-friendly length.
    static func truncatedForNotification(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > notificationOutputLimit else { return trimmed }
        let endIndex = trimmed.index(trimmed.startIndex, offsetBy: notificationOutputLimit)
        return String(trimmed[trimmed.startIndex ..< endIndex]) + "…"
    }

    // MARK: - User Notifications

    private func maybeNotifyUser(for result: ScriptExecutionResult, script: Script) {
        let defaults = AppGroup.standardDefaults
        if defaults.object(forKey: "showActionNotifications") == nil {
            defaults.set(true, forKey: "showActionNotifications")
        }

        guard defaults.bool(forKey: "showActionNotifications") else { return }
        guard shouldNotify(for: script) else { return }

        let body = if result.success {
            "\(script.name) completed"
        } else if let error = result.error {
            "\(script.name) failed: \(error)"
        } else {
            "\(script.name) failed"
        }

        postNotification(title: "妙右", body: body)
    }

    /// Posts a result-bearing notification for an explicitly chosen output mode
    /// (copy/notify). Unlike `maybeNotifyUser`, this intentionally does NOT gate
    /// on `showActionNotifications` or the self-notification suppression: the user
    /// opted this action into surfacing its result, so we always honor that.
    private func postResultNotification(title: String, body: String) {
        postNotification(title: title, body: body)
    }

    /// Builds and delivers a `UNUserNotification`, requesting authorization the
    /// first time. Shared by the standard completion path and the result modes.
    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    if granted {
                        center.add(request)
                    }
                }
            case .authorized, .provisional:
                center.add(request)
            default:
                break
            }
        }
    }

    private func shouldNotify(for script: Script) -> Bool {
        !Self.scriptSelfNotifies(script)
    }

    /// Pure helper: does this script raise its own notification (so MiaoRight's
    /// standard completion notification would be redundant)? Scripts that call
    /// `osascript` themselves are never double-notified. Used by both
    /// `outputSink(.standard)` and `shouldNotify`.
    static func scriptSelfNotifies(_ script: Script) -> Bool {
        let lowerContent = script.content.lowercased()
        return lowerContent.contains("display notification") || lowerContent.contains("osascript -e")
    }

    // MARK: - Execution Methods

    private final class ProcessPipeCollector: @unchecked Sendable {
            let pipe = Pipe()

            private let completion = DispatchGroup()
            private let lock = NSLock()
            private var buffer = Data()
            private var finished = false

            init() {
                completion.enter()
                pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                    self?.consume(handle.availableData)
                }
            }

            func finish(before deadline: DispatchTime) -> Data? {
                guard completion.wait(timeout: deadline) == .success else { return nil }
                lock.lock()
                defer { lock.unlock() }
                return buffer
            }

            func cancel() {
                pipe.fileHandleForReading.readabilityHandler = nil
                finishOnce()
            }

            private func consume(_ data: Data) {
                guard !data.isEmpty else {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    finishOnce()
                    return
                }

                lock.lock()
                buffer.append(data)
                lock.unlock()
            }

            private func finishOnce() {
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    return
                }
                finished = true
                lock.unlock()
                completion.leave()
            }
        }

        static func runProcess(
            executableURL: URL,
            arguments: [String],
            standardInput: Data? = nil
        ) -> Result<String, ScriptError> {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let outputCollector = ProcessPipeCollector()
            let errorCollector = ProcessPipeCollector()
            process.standardOutput = outputCollector.pipe
            process.standardError = errorCollector.pipe

            let inputPipe = standardInput == nil ? nil : Pipe()
            process.standardInput = inputPipe

            do {
                try process.run()
                outputCollector.pipe.fileHandleForWriting.closeFile()
                errorCollector.pipe.fileHandleForWriting.closeFile()

                if let standardInput, let inputPipe {
                    inputPipe.fileHandleForWriting.write(standardInput)
                    inputPipe.fileHandleForWriting.closeFile()
                }

                process.waitUntilExit()
                // A background descendant can inherit either pipe after this command exits.
                // Bound only the final drain, never the command's own running time.
                let drainDeadline = DispatchTime.now() + .seconds(2)
                guard let outputData = outputCollector.finish(before: drainDeadline),
                      let errorData = errorCollector.finish(before: drainDeadline)
                else {
                    outputCollector.cancel()
                    errorCollector.cancel()
                    return .failure(.executionFailed(
                        "A background process kept the command output open. Redirect its output and try again."
                    ))
                }
                let output = String(data: outputData, encoding: .utf8) ?? ""

                guard process.terminationStatus != 0 else {
                    return .success(output)
                }

                let errorOutput = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let message = if let errorOutput, !errorOutput.isEmpty {
                    errorOutput
                } else {
                    "Command exited with status \(process.terminationStatus)."
                }
                return .failure(.executionFailed(message))
            } catch {
                outputCollector.cancel()
                errorCollector.cancel()
                inputPipe?.fileHandleForWriting.closeFile()
                return .failure(.launchFailed(error.localizedDescription))
            }
        }

        static func executeBash(content: String, paths: [String]) async -> Result<String, ScriptError> {
            Self.runProcess(
                executableURL: URL(fileURLWithPath: "/bin/bash"),
                arguments: ["-c", content, "bash"] + paths
            )
        }

        static func executeAppleScript(content: String, paths: [String]) async -> Result<String, ScriptError> {
            let fullScript = """
            on run argv
                \(content)
            end run
            """

            return Self.runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", fullScript] + paths
            )
        }

        private func executeAutomator(workflowPath: String, paths: [String]) async -> Result<String, ScriptError> {
            guard FileManager.default.fileExists(atPath: workflowPath) else {
                return .failure(.workflowNotFound(workflowPath))
            }

            let pathsString = paths.joined(separator: "\n")
            return Self.runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/automator"),
                arguments: [workflowPath],
                standardInput: pathsString.data(using: .utf8)
            )
        }

        /// Runs a native-runtime action (OCR/PDF/copy-path variants plus the
        /// native-preferred image transforms) on the direct build. The direct
        /// build is non-sandboxed, so no `MonitoredFolders.beginAccess` scope is
        /// needed — these actions only read, copy to the clipboard, or write new
        /// files next to the source (image transforms write a new file via
        /// `uniqueDestinationURL` and never edit the original).
        private func executeNativeAction(
            _ action: NativeAction,
            paths: [String],
            parameter: String?
        ) async -> Result<String, ScriptError> {
            do {
                let output: String
                if NativeActionExecutor.requiresMainActorUI(action) {
                    output = try await MainActor.run {
                        try NativeActionExecutor.executeUIAction(action, paths: paths, parameter: parameter)
                    }
                } else {
                    output = try NativeActionExecutor.execute(action, paths: paths, parameter: parameter)
                }
                return .success(output)
            } catch let error as ScriptError {
                return .failure(error)
            } catch {
                return .failure(.executionFailed(error.localizedDescription))
            }
        }
}

// MARK: - Errors

enum ScriptError: Error, LocalizedError, Sendable {
    case launchFailed(String)
    case executionFailed(String)
    case workflowNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .launchFailed(reason):
            "Failed to launch script: \(reason)"
        case let .executionFailed(reason):
            "Script execution failed: \(reason)"
        case let .workflowNotFound(path):
            "Automator workflow not found: \(path)"
        }
    }
}
