import MiaoRightShared
import SwiftUI

struct FileTaskView: View {
    let request: FileTaskPresentation.Request
    @State private var tasks = FileTaskPresentation.shared
    @State private var format = SevenZipArchive.Format.zip
    @State private var password = ""
    @State private var confirmation = ""
    @State private var rule = BatchRenameRule(mode: .affixes)
    @State private var plan: BatchRenamePlan?
    @State private var error: String?

    init(request: FileTaskPresentation.Request, initialRule: BatchRenameRule = BatchRenameRule(mode: .affixes)) {
        self.request = request
        _rule = State(initialValue: initialRule)
        _plan = State(initialValue: request.kind == .rename ? BatchRenamePlan(urls: request.urls, rule: initialRule) : nil)
    }

    private var compressing: Bool { request.kind == .compress }
    private var passwordIssue: String? {
        if format == .tarGzip || password.isEmpty { return nil }
        if password != confirmation { return L10n.text("请再次输入相同的密码。", "Enter the same password again.") }
        if password.utf8.count > 1024 || password.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) {
            return L10n.text("密码过长或含有控制字符。", "The password is too long or contains control characters.")
        }
        if format == .zip && !password.unicodeScalars.allSatisfy({ $0.value < 128 }) {
            return L10n.text("中文密码请选择 7Z 格式。", "Choose 7Z for passwords containing non-ASCII characters.")
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { tasks.request = nil } label: { Label(L10n.text("返回设置", "Back to Settings"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless).disabled(tasks.isBusy).padding(.bottom, 18)
                PreferenceHeader(title: compressing ? L10n.text("压缩文件", "Compress Files") : L10n.text("批量重命名", "Batch Rename"),
                                 subtitle: L10n.text("已选择 \(request.urls.count) 项。确认下面的设置后再执行。", "\(request.urls.count) items selected. Review the settings before applying."))
                if compressing { compressionSettings } else { renameSettings }
                if let error { Text(error).foregroundStyle(.red).font(.system(size: 12)).textSelection(.enabled).padding(.vertical, 12) }
                HStack(spacing: 12) {
                    Button(tasks.isBusy ? L10n.text("正在处理…", "Working…") : (compressing ? L10n.text("开始压缩", "Compress") : L10n.text("确认重命名", "Apply Rename"))) { execute() }
                        .buttonStyle(.borderedProminent)
                        .disabled(tasks.isBusy || request.urls.isEmpty || (compressing ? passwordIssue != nil : plan?.canApply != true))
                    if tasks.isBusy { ProgressView().controlSize(.small) }
                    Text(compressing ? L10n.text("创建新的压缩包，原文件会保留。", "Creates a new archive and keeps the originals.") : L10n.text("先检查名称与冲突，完成后可撤销。", "Check names and conflicts first. You can undo the rename afterward."))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(.top, 24)
            }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
        .onAppear { refreshPlan() }
        .onChange(of: rule) { _, _ in refreshPlan() }
        .onChange(of: format) { _, format in if format == .tarGzip { password = ""; confirmation = "" } }
    }

    private var compressionSettings: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceRow(title: L10n.text("格式", "Format"), icon: "archivebox") {
                Picker(L10n.text("格式", "Format"), selection: $format) {
                    ForEach(SevenZipArchive.Format.allCases, id: \.rawValue) { Text($0.rawValue.uppercased()).tag($0) }
                }.labelsHidden().fixedSize()
            }
            if format != .tarGzip {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text("密码保护（可选）", "Password Protection (Optional)")).font(.system(size: 13, weight: .medium))
                    SecureField(L10n.text("不填则不加密", "Leave empty for no encryption"), text: $password)
                    SecureField(L10n.text("再次输入密码", "Confirm password"), text: $confirmation)
                    if let passwordIssue, !confirmation.isEmpty { Text(passwordIssue).font(.system(size: 12)).foregroundStyle(.red) }
                    Text(L10n.text("密码只用于本次压缩，不会保存。", "The password is used only for this archive and is not saved.")).font(.system(size: 12)).foregroundStyle(.secondary)
                }.textFieldStyle(.roundedBorder).padding(.vertical, 18)
            }
            Text(request.urls.prefix(5).map(\.lastPathComponent).joined(separator: "\n"))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
            if let first = request.urls.first {
                Text(L10n.text("保存到：\(first.deletingLastPathComponent().path)", "Save to: \(first.deletingLastPathComponent().path)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 10)
            }
        }.disabled(tasks.isBusy)
    }

    private var renameSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            PreferenceRow(title: L10n.text("方式", "Method"), icon: "pencil") {
                Picker(L10n.text("方式", "Method"), selection: $rule.mode) {
                    ForEach(BatchRenameRule.Mode.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize()
            }
            switch rule.mode {
            case .replace:
                LabeledContent(L10n.text("查找", "Find")) { TextField(L10n.text("要替换的文字", "Text to replace"), text: $rule.search) }
                LabeledContent(L10n.text("替换为", "Replace With")) { TextField(L10n.text("可以留空", "May be empty"), text: $rule.replacement) }
            case .affixes:
                LabeledContent(L10n.text("前缀", "Prefix")) { TextField(L10n.text("添加到名称前面", "Add before the name"), text: $rule.prefix) }
                LabeledContent(L10n.text("后缀", "Suffix")) { TextField(L10n.text("添加到名称后面", "Add after the name"), text: $rule.suffix) }
            case .sequence:
                LabeledContent(L10n.text("名称", "Name")) { TextField(L10n.text("留空保留原名", "Leave empty to keep names"), text: $rule.baseName) }
                LabeledContent(L10n.text("起始编号", "Start At")) { TextField("1", value: $rule.start, format: .number).frame(width: 100) }
                LabeledContent(L10n.text("编号位数", "Number Width")) { Stepper("\(rule.digits)", value: $rule.digits, in: 1...8).fixedSize() }
            default: EmptyView()
            }
            HStack {
                Text(L10n.text("原名称", "Original Name"))
                Spacer()
                Text(L10n.text("新名称", "New Name"))
            }.font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 8)
            Divider()
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(plan?.rows ?? []) { row in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .top, spacing: 12) {
                            Text(row.source.lastPathComponent).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "arrow.right").foregroundStyle(.tertiary).accessibilityHidden(true)
                            Text(row.destination.lastPathComponent).frame(maxWidth: .infinity, alignment: .leading)
                        }.font(.system(size: 12)).textSelection(.enabled)
                        if let issue = row.issue { Text(issue).font(.system(size: 11)).foregroundStyle(.red) }
                        Divider().padding(.top, 6)
                    }.padding(.vertical, 8)
                }
            }
        }.textFieldStyle(.roundedBorder).disabled(tasks.isBusy)
    }

    private func refreshPlan() {
        if !compressing { plan = BatchRenamePlan(urls: request.urls, rule: rule) }
    }

    private func execute() {
        guard !tasks.isBusy else { return }
        tasks.isBusy = true; error = nil
        let request = request, format = format, password = password, plan = plan
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<ScriptExecutionResult, ScriptError> in
                let id = UUID()
                return FileTaskContext.$executionID.withValue(id) {
                    do {
                        let urls: [URL]
                        if request.kind == .compress { urls = [try SevenZipArchive().compress(request.urls, format: format, password: password)] }
                        else { urls = try plan?.apply() ?? [] }
                        let summary = FileOperationJournal.shared.summary(for: id)
                        let title = request.kind == .compress ? "压缩文件" : "批量重命名"
                        return .success(.success(scriptName: title, output: urls.map(\.path).joined(separator: "\n"), outputPaths: urls.map(\.path), undoID: summary.undoID))
                    } catch { return .failure(.executionFailed(error.localizedDescription)) }
                }
            }.value
            tasks.isBusy = false
            switch result {
            case .success(let result):
                ActionUsage.record(request.kind == .compress ? "压缩…" : "批量重命名…")
                ActionResultPresentation.shared.present(result)
                tasks.request = nil
                self.password = ""; confirmation = ""
            case .failure(let failure): error = failure.localizedDescription
            }
        }
    }
}
