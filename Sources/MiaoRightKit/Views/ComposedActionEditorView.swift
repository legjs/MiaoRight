import MiaoRightShared
import SwiftUI

/// 组合动作编辑器(无代码):步骤卡片列表 + 原子选择器 + 参数表单。
/// 保存为 Script(type: .composed),启停/菜单匹配/统计全部继承现有体系。
struct ComposedActionEditorView: View {
    @Environment(ScriptStore.self) private var scriptStore

    /// 编辑已有动作时传入其 Script;新建为 nil
    let editing: Script?
    let onDone: () -> Void

    @State private var name: String
    @State private var appliesTo: AppliesTo
    @State private var steps: [ComposedAction.ComposedStep]
    @State private var showingAtomPicker = false
    @State private var editingStepIndex: Int?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var expandedStepIndex: Int?

    init(editing: Script?, onDone: @escaping () -> Void) {
        self.editing = editing
        self.onDone = onDone
        let composed = editing.flatMap { ComposedAction.decode($0.content) }
        _name = State(initialValue: editing?.name ?? "")
        _appliesTo = State(initialValue: editing?.appliesTo ?? .allItems)
        _steps = State(initialValue: composed?.steps ?? [])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                basicsCard
                stepsCard
                actionsBar
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            // Esc/⌘S 快捷键占位
            Button(L10n.text("保存", "Save")) { save() }
                .keyboardShortcut("s", modifiers: .command)
                .opacity(0)
        }
        .sheet(isPresented: $showingAtomPicker) { atomPicker }
        .sheet(item: testResultBinding) { result in
            testOutputSheet(result.wrappedValue)
        }
    }

    private var testResultBinding: Binding<TestResultBox?> {
        Binding(get: { testResult.map { TestResultBox(wrappedValue: $0) } },
                set: { testResult = $0?.wrappedValue })
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 12) {
            Button(L10n.text("← 返回", "← Back")) { onDone() }
                .buttonStyle(.miaoSecondary)
                .fixedSize()
            Text(editing == nil
                ? L10n.text("新建菜单", "New Action")
                : L10n.text("编辑菜单", "Edit Action"))
                .font(.title2.weight(.bold))
            Spacer()
            if !destructiveTitles.isEmpty {
                StatusPill(color: .orange, icon: "exclamationmark.shield.fill", text: L10n.text("含破坏性步骤·执行前确认", "Destructive · asks first"))
            }
        }
    }

    private var destructiveTitles: [String] {
        steps.compactMap { AtomRegistry.operation($0.op)?.isDestructive == true ? AtomRegistry.operation($0.op)?.title : nil }
    }

    // MARK: - 基本信息

    private var basicsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text(L10n.text("名称", "Name"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    TextField(L10n.text("例如:照片归档", "e.g. Archive photos"), text: $name)
                        .textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 12) {
                    Text(L10n.text("出现条件", "Appears"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    Picker("", selection: $appliesTo) {
                        Text(L10n.text("选中文件或文件夹", "Files & Folders")).tag(AppliesTo.allItems)
                        Text(L10n.text("仅选中文件", "Files Only")).tag(AppliesTo.filesOnly)
                        Text(L10n.text("仅选中文件夹", "Folders Only")).tag(AppliesTo.foldersOnly)
                        Text(L10n.text("文件夹空白处", "Inside Folder")).tag(AppliesTo.container)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    Spacer()
                }
            }
        }
    }

    // MARK: - 步骤卡片

    private var stepsCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                StudioSectionHeader(icon: "🧩", title: L10n.text("步骤", "Steps"), subtitle: L10n.text("从上到下依次执行,产物自动传递", "Runs top to bottom"))
                if steps.isEmpty {
                    Text(L10n.text("还没有步骤 — 点下方「添加步骤」开始搭建。", "No steps yet — tap \"Add Step\"."))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                } else {
                    ForEach(steps.indices, id: \.self) { index in
                        stepRow(index)
                    }
                }
                Button {
                    showingAtomPicker = true
                } label: {
                    Label(L10n.text("添加步骤", "Add Step"), systemImage: "plus")
                }
                .buttonStyle(.miaoSecondary)
                .fixedSize()
            }
        }
    }

    private func stepRow(_ index: Int) -> some View {
        let step = steps[index]
        let op = AtomRegistry.operation(step.op)
        let expanded = expandedStepIndex == index
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                // 序号 + 拼积木行
                Text("\(index + 1)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 18)
                Text(op?.emoji ?? "❓")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MiaoTheme.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(op?.title ?? step.op)
                        .font(.system(size: 13, weight: .semibold))
                    Text(paramSummary(step))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if op?.isDestructive == true {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .help(L10n.text("破坏性步骤", "Destructive step"))
                }
                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        expandedStepIndex = expanded ? nil : index
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                moveButtons(index)
                Button {
                    withAnimation { _ = steps.remove(at: index); expandedStepIndex = nil }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    expandedStepIndex = expanded ? nil : index
                }
            }

            if expanded {
                Divider().opacity(0.4)
                ParamFormView(step: binding(for: index), op: op)
                    .padding(.vertical, 8)
            }
            if index < steps.count - 1 {
                Divider().opacity(0.3)
            }
        }
    }

    private func binding(for index: Int) -> Binding<ComposedAction.ComposedStep> {
        Binding(
            get: { steps[index] },
            set: { steps[index] = $0 }
        )
    }

    private func moveButtons(_ index: Int) -> some View {
        HStack(spacing: 2) {
            Button {
                guard index > 0 else { return }
                steps.swapAt(index, index - 1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(index > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(index == 0)
            Button {
                guard index < steps.count - 1 else { return }
                steps.swapAt(index, index + 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(index < steps.count - 1 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .disabled(index == steps.count - 1)
        }
    }

    private func paramSummary(_ step: ComposedAction.ComposedStep) -> String {
        guard let op = AtomRegistry.operation(step.op) else { return "未知" }
        // builtin.run 直接显示菜单名,避免「调用内置菜单: XX」的啰嗦
        if op.id == "builtin.run", let name = step.params["name"], !name.isEmpty {
            return name
        }
        let parts = op.params.compactMap { spec -> String? in
            let raw = step.params[spec.key] ?? spec.defaultValue ?? ""
            switch spec.kind {
            case .choice(let options):
                return options.first(where: { $0.value == raw })?.title
            default:
                guard !raw.isEmpty else { return nil }
                return "\(spec.title): \(raw)"
            }
        }
        return parts.isEmpty ? L10n.text("点开配置参数", "Tap to configure") : parts.joined(separator: " · ")
    }

    // MARK: - 原子选择器

    private var atomPicker: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.text("添加步骤", "Add Step"))
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button(L10n.text("完成", "Done")) { showingAtomPicker = false }
                    .buttonStyle(.miaoSecondary)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(AtomicCategory.allCases, id: \.self) { category in
                        let ops = AtomRegistry.all.filter { $0.category == category }
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.emoji + " " + category.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.tertiary)
                            ForEach(ops, id: \.id) { op in
                                atomPickerRow(op)
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 460, height: 520)
    }

    private func atomPickerRow(_ op: AtomicOperation) -> some View {
        Button {
            var step = ComposedAction.ComposedStep(op: op.id)
            // 填入默认参数,编辑器里直接可见可改
            for spec in op.params {
                step.params[spec.key] = spec.defaultValue ?? ""
            }
            withAnimation { steps.append(step) }
            expandedStepIndex = steps.count - 1
        } label: {
            HStack(spacing: 10) {
                Text(op.emoji)
                    .font(.system(size: 15))
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(MiaoTheme.accent.opacity(0.10)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(op.title).font(.system(size: 13, weight: .semibold))
                        Text(slotText(op)).font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Text(op.params.isEmpty ? L10n.text("无需配置", "No parameters") : op.params.map(\.title).joined(separator: " · "))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if op.isDestructive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(MiaoTheme.accent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func slotText(_ op: AtomicOperation) -> String {
        let inName = op.input == .any ? L10n.text("任意", "any") : op.input.displayName
        let outName = op.output == .none ? L10n.text("无输出", "—") : op.output.displayName
        return "\(inName) → \(outName)"
    }

    // MARK: - 底部操作

    private var actionsBar: some View {
        HStack {
            if let editing {
                Button(role: .destructive) {
                    scriptStore.deleteScript(editing)
                    onDone()
                } label: {
                    Label(L10n.text("删除菜单", "Delete"), systemImage: "trash")
                }
                .buttonStyle(.miaoSecondary)
                .fixedSize()
            }
            Spacer()
            Button {
                runTest()
            } label: {
                if isTesting {
                    ProgressView().controlSize(.small)
                } else {
                    Label(L10n.text("试运行…", "Test…"), systemImage: "play.fill")
                }
            }
            .buttonStyle(.miaoSecondary)
            .disabled(steps.isEmpty || name.isEmpty || isTesting)
            .fixedSize()
            Button {
                save()
            } label: {
                Label(L10n.text("保存", "Save"), systemImage: "checkmark")
            }
            .buttonStyle(.miaoProminent)
            .disabled(name.isEmpty || steps.isEmpty)
            .fixedSize()
        }
    }

    // MARK: - 行为

    private func save() {
        let action = ComposedAction(steps: steps)
        if var existing = editing {
            existing.name = name
            existing.appliesTo = appliesTo
            existing.content = action.encoded()
            scriptStore.updateScript(existing)
        } else {
            let script = Script(
                name: name,
                type: .composed,
                content: action.encoded(),
                isEnabled: true,
                icon: "square.stack.3d.up",
                appliesTo: appliesTo,
                libraryCategory: ScriptStore.topCategoryKey // 自建动作默认放顶层
            )
            scriptStore.addScript(script)
        }
        onDone()
    }

    private func runTest() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = appliesTo != .filesOnly
        panel.allowsMultipleSelection = true
        panel.message = L10n.text("选择文件试运行这个菜单", "Pick files to test this action")
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        isTesting = true
        let content = ComposedAction(steps: steps).encoded()
        guard PipelineEngine.presentConfirm(content: content, itemCount: panel.urls.count) else {
            isTesting = false
            return
        }
        Task {
            let result = await PipelineEngine.execute(content: content, paths: panel.urls.map(\.path))
            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let output): testResult = "✅ " + output
                case .failure(let error): testResult = "❌ " + error.localizedDescription
                }
            }
        }
    }

    private func testOutputSheet(_ text: String) -> some View {
        VStack(spacing: 14) {
            Text(text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            Button(L10n.text("好", "OK")) { testResult = nil }
                .buttonStyle(.miaoProminent)
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - 参数表单(按原子声明的 schema 渲染控件)

struct ParamFormView: View {
    @Binding var step: ComposedAction.ComposedStep
    let op: AtomicOperation?

    var body: some View {
        VStack(spacing: 10) {
            if let op {
                ForEach(op.params, id: \.key) { spec in
                    paramRow(spec)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func paramRow(_ spec: AtomicParamSpec) -> some View {
        HStack(spacing: 10) {
            Text(spec.title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            control(spec)
        }
    }

    @ViewBuilder
    private func control(_ spec: AtomicParamSpec) -> some View {
        let value = Binding(
            get: { step.params[spec.key] ?? spec.defaultValue ?? "" },
            set: { step.params[spec.key] = $0 }
        )
        switch spec.kind {
        case .text:
            TextField("", text: value, prompt: Text(spec.kind.placeholderText ?? ""))
                .textFieldStyle(.roundedBorder)
        case .number:
            TextField("", text: value)
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)
        case .toggle:
            Toggle("", isOn: Binding(
                get: { (step.params[spec.key] ?? "false") == "true" },
                set: { step.params[spec.key] = $0 ? "true" : "false" }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(MiaoTheme.accent)
        case .choice(let options):
            Picker("", selection: value) {
                ForEach(options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        case .folderPick:
            HStack {
                Text((step.params[spec.key] ?? "").isEmpty ? L10n.text("未选择", "Not set") : (step.params[spec.key] ?? ""))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("选择…", "Choose…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    if panel.runModal() == .OK, let url = panel.url {
                        step.params[spec.key] = url.path
                    }
                }
                .buttonStyle(.miaoSecondary)
                .fixedSize()
            }
        case .appPick:
            HStack {
                Text(displayAppName(step.params[spec.key]))
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.text("选择…", "Choose…")) {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.application]
                    if panel.runModal() == .OK, let url = panel.url {
                        step.params[spec.key] = url.path
                    }
                }
                .buttonStyle(.miaoSecondary)
                .fixedSize()
            }
        }
    }

    private func displayAppName(_ path: String?) -> String {
        guard let path, !path.isEmpty else { return L10n.text("未选择", "Not set") }
        return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

extension AtomicParamSpec.Kind {
    /// text 占位提示(case 关联值取用糖)
    var placeholderText: String? {
        if case .text(let hint) = self { return hint }
        return nil
    }
}

/// sheet(item:) 需要的 Identifiable 包装
struct TestResultBox: Identifiable {
    let id = UUID()
    let wrappedValue: String
}
