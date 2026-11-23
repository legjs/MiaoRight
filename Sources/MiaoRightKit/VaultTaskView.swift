import MiaoRightShared
import SwiftUI

/// 「加入保险箱」内嵌流程:未创建先建,锁定先解锁,解锁后确认移入。
struct VaultTaskView: View {
    let request: VaultTaskPresentation.Request
    @State private var tasks = VaultTaskPresentation.shared
    @State private var vault = VaultStore.shared
    @State private var password = ""
    @State private var confirmation = ""
    @State private var sizeGB = 32
    @State private var error: String?

    private var passwordIssue: String? {
        guard !password.isEmpty, !confirmation.isEmpty, password != confirmation else { return nil }
        return L10n.text("请再次输入相同的密码。", "Enter the same password again.")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { tasks.request = nil } label: { Label(L10n.text("返回设置", "Back to Settings"), systemImage: "chevron.left") }
                    .buttonStyle(.borderless).disabled(tasks.isBusy || vault.isBusy).padding(.bottom, 18)
                PreferenceHeader(title: L10n.text("加入保险箱", "Add to Vault"),
                                 subtitle: L10n.text("已选择 \(request.urls.count) 项。移入后原位置不再保留,完成后可撤销。", "\(request.urls.count) items selected. Items leave their original location; you can undo afterward."))
                stage
                if let error { Text(error).foregroundStyle(.red).font(.system(size: 12)).textSelection(.enabled).padding(.vertical, 12) }
            }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
        .onAppear { vault.refreshState() }
    }

    @ViewBuilder private var stage: some View {
        switch vault.state {
        case .missing: creationStage
        case .locked: unlockStage
        case .unlocked: confirmStage
        }
    }

    // MARK: - 未创建

    private var creationStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("先创建一个加密保险箱。密码丢失将无法找回其中的内容。", "Create an encrypted vault first. Its contents cannot be recovered without the password."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 10) {
                SecureField(L10n.text("设置保险箱密码", "Set the vault password"), text: $password)
                SecureField(L10n.text("再次输入密码", "Confirm password"), text: $confirmation)
                if let passwordIssue { Text(passwordIssue).font(.system(size: 12)).foregroundStyle(.red) }
                PreferenceRow(title: L10n.text("容量上限", "Capacity"), icon: "internaldrive") {
                    Picker(L10n.text("容量上限", "Capacity"), selection: $sizeGB) {
                        ForEach([8, 16, 32, 64], id: \.self) { Text("\($0) GB").tag($0) }
                    }.labelsHidden().fixedSize()
                }
                Text(L10n.text("容量为上限,实际按存放内容占用。位置:\(VaultStore.defaultBundleURL().deletingLastPathComponent().path)", "Capacity is a cap; storage grows with content. Location: \(VaultStore.defaultBundleURL().deletingLastPathComponent().path)"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            }.textFieldStyle(.roundedBorder).padding(.bottom, 18)
            confirmButton(title: L10n.text("创建并继续", "Create and Continue"), action: createVault)
        }
    }

    // MARK: - 已锁定

    private var unlockStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("保险箱已锁定,解锁后继续加入。", "The vault is locked. Unlock it to continue."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 14)
            VStack(alignment: .leading, spacing: 10) {
                SecureField(L10n.text("保险箱密码", "Vault password"), text: $password)
                    .onAppear { if password.isEmpty, vault.rememberPassword { password = VaultKeychain.load() ?? "" } }
            }.textFieldStyle(.roundedBorder).padding(.bottom, 18)
            confirmButton(title: L10n.text("解锁并继续", "Unlock and Continue"), action: unlockVault)
        }
    }

    // MARK: - 已解锁

    private var confirmStage: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text("移入保险箱", "Move into the Vault")).font(.system(size: 13, weight: .medium))
                Text(request.urls.prefix(6).map(\.lastPathComponent).joined(separator: "\n") + (request.urls.count > 6 ? "\n…" : ""))
                    .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
            }.padding(.bottom, 14)
            confirmButton(title: L10n.text("加入保险箱", "Add to Vault"), action: addToVault)
            Text(L10n.text("同名文件自动改名,不会覆盖。", "Same-name items are renamed automatically; nothing is overwritten."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 14)
        }
    }

    private func confirmButton(title: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Button(title) { action() }
                .buttonStyle(.borderedProminent)
                .disabled(tasks.isBusy || vault.isBusy || !canSubmit)
            if tasks.isBusy || vault.isBusy {
                ProgressView().controlSize(.small)
                Text(vault.busyText ?? L10n.text("正在处理…", "Working…")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var canSubmit: Bool {
        switch vault.state {
        case .missing: !password.isEmpty && passwordIssue == nil
        case .locked: !password.isEmpty
        case .unlocked: true
        }
    }

    // MARK: - 动作

    private func createVault() {
        error = nil
        Task { await vault.createVault(password: password, sizeGB: sizeGB); if let message = vault.lastError { error = message } }
    }

    private func unlockVault() {
        error = nil
        Task { await vault.unlock(password: password); if let message = vault.lastError { error = message } }
    }

    private func addToVault() {
        guard !tasks.isBusy else { return }
        error = nil
        let id = UUID(), request = request
        Task { @MainActor in
            tasks.isBusy = true
            do {
                let moved = try await FileTaskContext.$executionID.withValue(id) {
                    try await VaultStore.shared.addItems(request.urls)
                }
                let summary = FileOperationJournal.shared.summary(for: id)
                VaultStore.shared.refreshContents()
                ActionUsage.record("加入保险箱")
                tasks.isBusy = false
                tasks.request = nil
                ActionResultPresentation.shared.present(.success(
                    scriptName: "加入保险箱",
                    output: moved.map(\.path).joined(separator: "\n"),
                    outputPaths: moved.map(\.path),
                    undoID: summary.undoID
                ))
            } catch {
                tasks.isBusy = false
                self.error = error.localizedDescription
            }
        }
    }
}
