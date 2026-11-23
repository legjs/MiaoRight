import AppKit
import MiaoRightShared
import SwiftUI

/// 保险箱独立导航页(与剪贴板并列):创建、解锁、内容管理都在这一页完成。
struct VaultPageView: View {
    @State private var vault = VaultStore.shared
    @State private var password = ""
    @State private var confirmation = ""
    @State private var sizeGB = 32

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PreferenceHeader(title: L10n.text("保险箱", "Vault"),
                                 subtitle: L10n.text("敏感文件加密存放，锁定后不可访问。", "Sensitive files stay encrypted; locked means inaccessible."))
                if vault.isBusy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(vault.busyText ?? L10n.text("正在处理…", "Working…")).font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.bottom, 14)
                }
                switch vault.state {
                case .missing: missingContent
                case .locked: lockedContent
                case .unlocked: unlockedContent
                }
                if let error = vault.lastError { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled).padding(.top, 14) }
            }.frame(maxWidth: 640, alignment: .leading).padding(28).frame(maxWidth: .infinity)
        }
        .disabled(vault.isBusy)
        .onAppear { vault.refreshState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in vault.refreshState() }
    }

    // MARK: - 未创建

    private var missingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("创建一个加密保险箱存放敏感文件。在 Finder 右键「加入保险箱」即可移入；密码丢失将无法找回内容。", "Create an encrypted vault for sensitive items. Right-click “Add to Vault” in Finder to move items in. Contents cannot be recovered without the password."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 10) {
                SecureField(L10n.text("设置保险箱密码", "Set the vault password"), text: $password)
                SecureField(L10n.text("再次输入密码", "Confirm password"), text: $confirmation)
                if !password.isEmpty, !confirmation.isEmpty, password != confirmation {
                    Text(L10n.text("请再次输入相同的密码。", "Enter the same password again.")).font(.system(size: 12)).foregroundStyle(.red)
                }
            }.textFieldStyle(.roundedBorder).padding(.bottom, 12)
            PreferenceRow(title: L10n.text("容量上限", "Capacity"), icon: "internaldrive", detail: L10n.text("上限只是保护，实际按存放内容占用", "A safety cap; storage grows with content")) {
                Picker(L10n.text("容量上限", "Capacity"), selection: $sizeGB) {
                    ForEach([8, 16, 32, 64], id: \.self) { Text("\($0) GB").tag($0) }
                }.labelsHidden().fixedSize()
            }
            HStack(spacing: 12) {
                Button(L10n.text("创建保险箱", "Create Vault")) {
                    Task { await vault.createVault(password: password, sizeGB: sizeGB); password = ""; confirmation = "" }
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty || password != confirmation)
            }.padding(.top, 20)
            Text(L10n.text("位置:\(VaultStore.defaultBundleURL().deletingLastPathComponent().path)", "Location: \(VaultStore.defaultBundleURL().deletingLastPathComponent().path)"))
                .font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled).padding(.top, 12)
        }
    }

    // MARK: - 已锁定

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SecureField(L10n.text("保险箱密码", "Vault password"), text: $password)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onAppear { if password.isEmpty, vault.rememberPassword { password = VaultKeychain.load() ?? "" } }
                Button(L10n.text("解锁", "Unlock")) { Task { await vault.unlock(password: password) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty)
            }
            Text(L10n.text("解锁后即可查看、取出与加入内容。忘记密码将无法找回。", "Unlock to view, extract, and add items. Forgotten passwords cannot be recovered."))
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
            removeRow.padding(.top, 8)
        }
    }

    // MARK: - 已解锁

    private var unlockedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("已解锁", "Unlocked")).font(.system(size: 13, weight: .medium))
                    Text(autoLockSummary).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.text("锁定", "Lock")) { vault.lock() }.buttonStyle(.bordered)
            }.padding(.bottom, 14)

            HStack(spacing: 12) {
                Button { addFiles() } label: { Label(L10n.text("添加文件…", "Add Files…"), systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
                Text(L10n.text("也可以在 Finder 右键「加入保险箱」。", "Or right-click “Add to Vault” in Finder."))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.bottom, 14)

            ForEach(vault.contents) { entry in
                HStack(spacing: 10) {
                    Image(systemName: entry.isDirectory ? "folder" : "doc").font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.url.lastPathComponent).font(.system(size: 12)).lineLimit(1)
                        Text(subtitle(entry)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 12)
                    Button(L10n.text("取出…", "Extract…")) { extractEntry(entry) }.buttonStyle(.borderless).font(.system(size: 12))
                    Button(L10n.text("删除", "Delete"), role: .destructive) { confirmDelete(entry) }.buttonStyle(.borderless).font(.system(size: 12))
                }.padding(.vertical, 8)
                Divider()
            }
            if vault.contents.isEmpty {
                Text(L10n.text("保险箱是空的。", "The vault is empty."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 10)
            }

            PreferenceRow(title: L10n.text("自动锁定", "Auto Lock"), icon: "timer", detail: L10n.text("空闲、睡眠或退出妙右时自动锁定", "Locks when idle, sleeping, or quitting MiaoRight")) {
                Picker(L10n.text("自动锁定", "Auto Lock"), selection: Binding(
                    get: { vault.autoLockMinutes }, set: { vault.autoLockMinutes = $0 }
                )) {
                    Text(L10n.text("5 分钟", "5 minutes")).tag(5)
                    Text(L10n.text("15 分钟", "15 minutes")).tag(15)
                    Text(L10n.text("30 分钟", "30 minutes")).tag(30)
                    Text(L10n.text("60 分钟", "60 minutes")).tag(60)
                    Text(L10n.text("不自动锁定", "Never")).tag(0)
                }.labelsHidden().fixedSize()
            }
            PreferenceRow(title: L10n.text("记住密码", "Remember Password"), icon: "key",
                          detail: L10n.text("存入登录钥匙串，解锁时自动填写。", "Stored in the login keychain and filled in when unlocking.")) {
                Toggle(L10n.text("记住密码", "Remember Password"), isOn: Binding(
                    get: { vault.rememberPassword }, set: { vault.rememberPassword = $0 }
                )).labelsHidden().toggleStyle(.switch)
            }
            PreferenceRow(title: L10n.text("镜像位置", "Image Location"), icon: "externaldrive") { EmptyView() }
                .padding(.bottom, -12)
            Text(vault.config?.bundlePath ?? VaultStore.defaultBundleURL().path)
                .font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled).padding(.vertical, 10)
            removeRow
        }
    }

    private var removeRow: some View {
        PreferenceRow(title: L10n.text("移除保险箱", "Remove Vault"), icon: "trash",
                      detail: L10n.text("镜像与其中全部内容永久删除，密码无法恢复", "Deletes the image and everything inside; the password cannot recover them")) {
            Button(L10n.text("移除…", "Remove…"), role: .destructive) { confirmDestroy() }
        }
    }

    private func subtitle(_ entry: VaultStore.Entry) -> String {
        var parts: [String] = []
        if let size = entry.sizeText { parts.append(size) }
        if let modified = entry.modified { parts.append(modified.formatted(date: .abbreviated, time: .shortened)) }
        return parts.joined(separator: " · ")
    }

    private var autoLockSummary: String {
        guard vault.autoLockMinutes > 0 else { return L10n.text("解锁期间保持打开，不自动锁定。", "Stays unlocked; no automatic locking.") }
        return L10n.text("无操作 \(vault.autoLockMinutes) 分钟、睡眠或退出妙右时自动锁定。", "Locks automatically after \(vault.autoLockMinutes) minutes idle, sleep, or quitting MiaoRight.")
    }

    // MARK: - 动作

    private func addFiles() {
        guard !AppGroup.isIsolated else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        panel.prompt = L10n.text("加入", "Add")
        guard panel.runModal() == .OK else { return }
        Task {
            do {
                _ = try await vault.addItems(panel.urls)
                vault.refreshContents()
            } catch { vault.lastError = error.localizedDescription }
        }
    }

    private func extractEntry(_ entry: VaultStore.Entry) {
        guard !AppGroup.isIsolated else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = L10n.text("取出到这里", "Extract Here")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task {
            do {
                _ = try await vault.extractItems([entry.url], to: destination)
                vault.refreshContents()
            } catch { vault.lastError = error.localizedDescription }
        }
    }

    private func confirmDelete(_ entry: VaultStore.Entry) {
        guard !AppGroup.isIsolated else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("删除「\(entry.url.lastPathComponent)」?", "Delete “\(entry.url.lastPathComponent)”?")
        alert.informativeText = L10n.text("此项目会从保险箱中永久移除，不可撤销。", "The item is removed from the vault permanently; this cannot be undone.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("删除", "Delete"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                _ = try await vault.deleteItems([entry.url])
                vault.refreshContents()
            } catch { vault.lastError = error.localizedDescription }
        }
    }

    private func confirmDestroy() {
        guard !AppGroup.isIsolated else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("移除保险箱?", "Remove the vault?")
        alert.informativeText = L10n.text("保险箱镜像与其中的全部内容会被永久删除，密码也无法恢复。", "The vault image and everything inside it are deleted permanently; the password cannot recover them.")
        alert.alertStyle = .critical
        alert.addButton(withTitle: L10n.text("移除", "Remove"))
        alert.addButton(withTitle: L10n.text("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await vault.destroyVault() }
    }
}
