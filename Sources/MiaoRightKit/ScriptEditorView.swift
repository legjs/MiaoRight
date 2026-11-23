import MiaoRightShared
import SwiftUI

struct ScriptEditorView: View {
    let existingScript: Script?
    let onSave: (Script) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var type: ScriptType
    @State private var content: String
    @State private var isEnabled: Bool
    @State private var icon: String
    @State private var appliesTo: AppliesTo
    @State private var fileExtensionsText: String
    @State private var extensionMatchMode: ExtensionMatchMode
    @State private var minSelection: Int
    @State private var maxSelection: Int
    @State private var limitSelection: Bool
    @State private var categoryId: UUID?
    @State private var outputMode: ScriptOutputMode
    @State private var confirmBeforeRun: Bool
    @State private var showingIconPicker = false
    @State private var showingTestOutput = false
    @State private var testOutput: String = ""
    @State private var testError: String?
    @State private var isRunningTest = false

    @Environment(ScriptStore.self) private var scriptStore

    init(script: Script?, onSave: @escaping (Script) -> Void) {
        existingScript = script
        self.onSave = onSave

        _name = State(initialValue: script?.name ?? "")
        _type = State(initialValue: script?.type ?? .bash)
        _content = State(initialValue: script?.content ?? "")
        _isEnabled = State(initialValue: script?.isEnabled ?? true)
        _icon = State(initialValue: script?.icon ?? "terminal")
        _appliesTo = State(initialValue: script?.appliesTo ?? .allItems)
        _fileExtensionsText = State(initialValue: script?.fileExtensions.joined(separator: ", ") ?? "")
        _extensionMatchMode = State(initialValue: script?.extensionMatchMode ?? .any)
        _minSelection = State(initialValue: script?.minSelection ?? 1)
        _maxSelection = State(initialValue: script?.maxSelection ?? 1)
        _limitSelection = State(initialValue: script?.maxSelection != nil)
        _categoryId = State(initialValue: script?.categoryId)
        _outputMode = State(initialValue: script?.outputMode ?? .standard)
        _confirmBeforeRun = State(initialValue: script?.confirmBeforeRun ?? false)
    }

    var body: some View {
        Form {
            generalSection
            fileFilterSection
            selectionFilterSection
            behaviorSection
            scriptSection
            previewSection
        }
        .formStyle(.grouped)
        .frame(minWidth: 400, minHeight: 400)
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingIconPicker) {
            IconPickerView(selectedIcon: $icon)
        }
        .sheet(isPresented: $showingTestOutput) {
            TestOutputView(
                scriptName: name.isEmpty ? L10n.text("未命名菜单", "Untitled Script") : name,
                output: testOutput,
                error: testError
            )
        }
    }

    // MARK: - 显示名(双语;数据模型 rawValue 为英文,仅作数据键)

    private func typeDisplay(_ t: ScriptType) -> String {
        switch t {
        case .bash: L10n.text("Shell 命令", "Shell Command")
        case .applescript: L10n.text("Mac 自动化", "Mac Automation")
        case .automator: L10n.text("Automator 工作流", "Automator Workflow")
        case .composed: L10n.text("组合菜单", "Composed Action")
        }
    }

    private func appliesDisplay(_ a: AppliesTo) -> String {
        switch a {
        case .allItems: L10n.text("文件与文件夹", "Files & Folders")
        case .filesOnly: L10n.text("仅文件", "Files Only")
        case .foldersOnly: L10n.text("仅文件夹", "Folders Only")
        case .container: L10n.text("文件夹内", "Inside Folder")
        }
    }

    private func matchModeDisplay(_ m: ExtensionMatchMode) -> String {
        m == .any
            ? L10n.text("任一文件匹配即显示", "Show if any matches")
            : L10n.text("全部文件匹配才显示", "Show only if all match")
    }

    // MARK: - General Section

    private var generalSection: some View {
        Section(L10n.text("基本信息", "Basic Info")) {
            HStack {
                TextField(L10n.text("名称", "Name"), text: $name, prompt: Text(L10n.text("菜单名称", "Action name")))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("scriptNameField")

                Button {
                    showingIconPicker = true
                } label: {
                    Image(systemName: icon)
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("iconPickerButton")
            }

            Picker(L10n.text("类型", "Type"), selection: $type) {
                ForEach(ScriptType.allCases, id: \.self) { scriptType in
                    Label(typeDisplay(scriptType), systemImage: scriptType.icon)
                        .tag(scriptType)
                }
            }
            .accessibilityIdentifier("scriptTypeSelector")
            .help(L10n.text("Shell 命令运行终端命令,Mac 自动化使用 AppleScript", "Shell Command runs terminal commands, Mac Automation uses AppleScript"))

            Picker(L10n.text("显示场景", "Show for"), selection: $appliesTo) {
                ForEach(AppliesTo.allCases, id: \.self) { target in
                    Label(appliesDisplay(target), systemImage: target.icon)
                        .tag(target)
                }
            }
            .accessibilityIdentifier("appliesToSelector")
            .help(L10n.text("该菜单在右键中的出现条件", "When this action appears in your right-click menu"))

            if !scriptStore.categories.isEmpty {
                Picker(L10n.text("分组", "Group"), selection: $categoryId) {
                    Text(L10n.text("无", "None")).tag(nil as UUID?)
                    ForEach(scriptStore.categories) { category in
                        Label(category.name, systemImage: category.icon)
                            .tag(category.id as UUID?)
                    }
                }
                .accessibilityIdentifier("categorySelector")
            }

            Toggle(L10n.text("启用", "Active"), isOn: $isEnabled)
                .accessibilityIdentifier("enabledToggle")
                .help(L10n.text("启用后,该菜单会出现在右键中", "When active, this action appears in your right-click menu"))
        }
    }

    // MARK: - File Filter Section

    private var fileFilterSection: some View {
        Section(L10n.text("限定文件类型(可选)", "Limit to File Types (Optional)")) {
            TextField(L10n.text("文件类型", "File types"), text: $fileExtensionsText, prompt: Text(L10n.text("jpg、png、pdf — 留空则对所有文件生效", "jpg, png, pdf — leave blank for all files")))
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("fileExtensionsField")

            if !fileExtensionsText.isEmpty {
                Picker(L10n.text("匹配方式", "When to show"), selection: $extensionMatchMode) {
                    ForEach(ExtensionMatchMode.allCases, id: \.self) { mode in
                        Text(matchModeDisplay(mode)).tag(mode)
                    }
                }
                .accessibilityIdentifier("extensionMatchModeSelector")
            }

            Text(L10n.text(
                "留空则对所有文件显示;也可输入以逗号分隔的扩展名。",
                "Leave blank to show for all files. Or enter file types separated by commas."
            ))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selection Filter Section

    private var selectionFilterSection: some View {
        Section(L10n.text("选中数量(可选)", "Selection Count (Optional)")) {
            Stepper(value: $minSelection, in: 0 ... 99) {
                HStack {
                    Text(L10n.text("最少选中", "Minimum selected"))
                    Spacer()
                    Text("\(minSelection)")
                }
            }

            Toggle(L10n.text("限制最大数量", "Limit maximum"), isOn: $limitSelection)

            if limitSelection {
                Stepper(value: $maxSelection, in: minSelection ... 99) {
                    HStack {
                        Text(L10n.text("最多选中", "Maximum selected"))
                        Spacer()
                    Text("\(maxSelection)")
                    }
                }
            }

            Text(L10n.text(
                "用于只在选中单个文件或多个文件时显示动作。",
                "Use this to show actions only for single files or larger selections."
            ))
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
        }
        .onChange(of: minSelection) { _, newValue in
            if limitSelection, maxSelection < newValue {
                maxSelection = newValue
            }
        }
        .onChange(of: limitSelection) { _, enabled in
            if enabled, maxSelection < minSelection {
                maxSelection = minSelection
            }
        }
    }

    // MARK: - Behavior Section

    private var behaviorSection: some View {
        Section(L10n.text("行为", "Behavior")) {
            Picker(SettingsCopy.outputModeLabel, selection: $outputMode) {
                Text(SettingsCopy.outputModeStandardOption).tag(ScriptOutputMode.standard)
                Text(SettingsCopy.outputModeShowOption).tag(ScriptOutputMode.showResult)
                Text(SettingsCopy.outputModeCopyOption).tag(ScriptOutputMode.copyResult)
                Text(SettingsCopy.outputModeNotifyOption).tag(ScriptOutputMode.notifyResult)
            }
            .accessibilityIdentifier("outputModeSelector")
            .help(SettingsCopy.outputModeHelp)

            Toggle(SettingsCopy.confirmBeforeRunLabel, isOn: $confirmBeforeRun)
                .accessibilityIdentifier("confirmBeforeRunToggle")
                .help(SettingsCopy.confirmBeforeRunHelp)
        }
    }

    // MARK: - Script Section

    private var scriptSection: some View {
        Section(L10n.text("脚本内容", "Code")) {
            if type == .automator {
                HStack {
                    TextField(L10n.text("Automator 文件", "Automator file"), text: $content, prompt: Text(L10n.text("选择一个 .workflow 文件", "Select a .workflow file")))
                        .textFieldStyle(.roundedBorder)

                    Button(L10n.text("浏览…", "Browse…")) {
                        browseForWorkflow()
                    }
                }
            } else {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 150)
                    .accessibilityIdentifier("scriptContentEditor")

                Text(helpText)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var helpText: String {
        switch type {
        case .bash:
            L10n.text("选中的文件会以 $1、$2… 传入;用 $@ 表示全部文件。", "The selected files are passed as $1, $2, etc. Use $@ for all files.")
        case .applescript:
            L10n.text("文件以 argv 传入,用「item 1 of argv」访问。", "Files are passed as argv. Access with 'item 1 of argv'.")
        case .automator:
            L10n.text("文件作为输入传给工作流。", "Files are passed as input to the workflow.")
        case .composed:
            L10n.text("组合菜单由原子步骤构成,在此查看 JSON 定义。", "Composed actions are built from atomic steps.")
        }
    }

    // MARK: - Preview Section

    private var previewSection: some View {
        Section(L10n.text("预览", "Preview")) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(MiaoTheme.accent)
                    .frame(width: 20)

                Text(name.isEmpty ? L10n.text("未命名菜单", "Untitled Script") : name)

                Spacer()

                Text(typeDisplay(type))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(L10n.text("取消", "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .accessibilityIdentifier("cancelButton")
        }

        ToolbarItem(placement: .automatic) {
            Button {
                testScript()
            } label: {
                if isRunningTest {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label(L10n.text("试运行", "Test"), systemImage: "play.fill")
                }
            }
            .disabled(content.isEmpty || isRunningTest || type == .automator)
            .help(type == .automator
                ? L10n.text("Automator 工作流不支持从编辑器试运行", "Testing is not available for Automator workflows")
                : L10n.text("选择文件实际运行一次脚本", "Test script with selected files"))
            .accessibilityIdentifier("testScriptButton")
        }

        ToolbarItem(placement: .confirmationAction) {
            Button(L10n.text("保存", "Save")) {
                save()
            }
            .disabled(name.isEmpty || content.isEmpty)
            .accessibilityIdentifier("saveButton")
        }
    }

    // MARK: - Actions

    private func save() {
        // Parse file extensions from comma-separated string
        let extensions = fileExtensionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }

        let script = Script(
            id: existingScript?.id ?? UUID(),
            name: name,
            type: type,
            content: content,
            isEnabled: isEnabled,
            icon: icon,
            appliesTo: appliesTo,
            fileExtensions: extensions,
            extensionMatchMode: extensionMatchMode,
            minSelection: minSelection,
            maxSelection: limitSelection ? maxSelection : nil,
            categoryId: categoryId,
            outputMode: outputMode,
            confirmBeforeRun: confirmBeforeRun
        )
        onSave(script)

        dismiss()
    }

    func testScript() {
        // Open file picker to select test files
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = L10n.text("选择用于试运行脚本的文件", "Select files to test the script with")
        panel.prompt = L10n.text("试运行", "Test")

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        isRunningTest = true
        testOutput = ""
        testError = nil

        let paths = panel.urls.map(\.path)

        Task {
            do {
                let result = try await runTestScript(paths: paths)
                await MainActor.run {
                    testOutput = result
                    testError = nil
                    isRunningTest = false
                    showingTestOutput = true
                }
            } catch {
                await MainActor.run {
                    testOutput = ""
                    testError = error.localizedDescription
                    isRunningTest = false
                    showingTestOutput = true
                }
            }
        }
    }

    private func runTestScript(paths: [String]) async throws -> String {
        switch type {
        case .bash:
            return try await runBashTest(paths: paths)
        case .applescript:
            return try await runAppleScriptTest(paths: paths)
        case .automator:
            throw NSError(domain: "MiaoRight", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L10n.text("Automator 工作流无法从编辑器试运行", "Automator workflows cannot be tested from the editor")
            ])
        case .composed:
            let result = await PipelineEngine.execute(content: content, paths: paths)
            switch result {
            case .success(let output): return output
            case .failure(let error): throw error
            }
        }
    }

    private func runBashTest(paths: [String]) async throws -> String {
        let output = try await ScriptExecutor.executeBash(content: content, paths: paths).get()
        return output.isEmpty ? L10n.text("(无输出)", "(No output)") : output
    }

    private func runAppleScriptTest(paths: [String]) async throws -> String {
        let output = try await ScriptExecutor.executeAppleScript(content: content, paths: paths).get()
        return output.isEmpty ? L10n.text("(无输出)", "(No output)") : output
    }

    private func browseForWorkflow() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "workflow")!]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            content = url.path
        }
    }
}

// MARK: - Icon Picker

struct IconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedIcon: String

    private let icons = [
        "terminal", "applescript", "gearshape.2",
        "doc", "folder", "doc.on.clipboard",
        "arrow.right.circle", "trash", "pencil",
        "magnifyingglass", "square.and.arrow.up", "square.and.arrow.down",
        "link", "photo", "film",
        "music.note", "archivebox", "tray"
    ]

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.text("选择图标", "Choose Icon"))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(44)), count: 6), spacing: 12) {
                ForEach(icons, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                        dismiss()
                    } label: {
                        Image(systemName: icon)
                            .font(.title2)
                            .frame(width: 40, height: 40)
                            .background(selectedIcon == icon ? MiaoTheme.accent.opacity(0.2) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button(L10n.text("取消", "Cancel")) {
                dismiss()
            }
            .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 320)
    }
}

// MARK: - Test Output View

public struct TestOutputView: View {
    @Environment(\.dismiss) private var dismiss
    public let scriptName: String
    public let output: String
    public let error: String?
    /// When hosted in a hand-built `NSWindow` (the result-window presenter),
    /// `@Environment(\.dismiss)` is inert, so the presenter passes a real closer.
    /// The editor sheet leaves this nil and keeps using `dismiss()`.
    public var onClose: (() -> Void)?
    public var completedTitle = L10n.text("测试完成", "Test Completed")
    public var failedTitle = L10n.text("测试失败", "Test Failed")

    public init(
        scriptName: String,
        output: String,
        error: String?,
        onClose: (() -> Void)? = nil,
        completedTitle: String? = nil,
        failedTitle: String? = nil
    ) {
        self.scriptName = scriptName
        self.output = output
        self.error = error
        self.onClose = onClose
        self.completedTitle = completedTitle ?? L10n.text("测试完成", "Test Completed")
        self.failedTitle = failedTitle ?? L10n.text("测试失败", "Test Failed")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(error == nil ? .green : .red)
                    .font(.title2)

                Text(error == nil ? completedTitle : failedTitle)
                    .font(.headline)

                Spacer()
            }

            Divider()

            if let error {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("错误", "Error"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.text("输出", "Output"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ScrollView {
                        Text(output)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }

            HStack {
                Spacer()
                Button(L10n.text("关闭", "Close")) {
                    (onClose ?? { dismiss() })()
                }
                .keyboardShortcut(.escape)
                .accessibilityIdentifier("closeTestOutputButton")
            }
        }
        .padding()
        .frame(width: 500, height: 350)
    }
}

