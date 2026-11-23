import AppKit
import MiaoRightShared
import SwiftUI

/// 内嵌通用设置；只管理 Finder Sync 扩展，不改变系统服务。
public struct ExtensionsManagementView: View {
    @State private var extensions: [FinderExtensionInfo] = []
    @State private var loading = true
    @State private var changingID: String?
    @State private var error: String?
    @State private var needsFinderRefresh = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text(
                "关闭后，会隐藏该 Finder 扩展添加的一整组菜单项。系统的“快速操作”和“服务”请在系统设置中管理。",
                "Turning off a Finder extension hides all its menu items. Manage system Quick Actions and Services in System Settings."
            ))
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)

            if loading && extensions.isEmpty {
                ProgressView().controlSize(.small).padding(.vertical, 12)
            } else if extensions.isEmpty {
                Text(L10n.text("未检测到 Finder 扩展。", "No Finder extensions detected."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
            }
            ForEach(extensions) { ext in
                PreferenceRow(title: ext.isSelf ? L10n.text("妙右", "MiaoRight") : ext.name,
                              icon: "puzzlepiece.extension",
                              detail: ext.isSelf ? L10n.text("妙右自身的右键菜单", "MiaoRight’s own context menu") : nil) {
                    Toggle(ext.name, isOn: Binding(get: {
                        extensions.first(where: { $0.bundleID == ext.bundleID })?.isEnabled ?? false
                    }, set: { enabled in
                        Task { await setEnabled(ext, enabled: enabled) }
                    }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(ext.isSelf || changingID != nil || loading)
                }
            }
            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(.red).padding(.top, 12)
            }
            if needsFinderRefresh {
                Text(L10n.text("已保存。若菜单尚未更新，请重新打开 Finder 窗口，或在文件操作完成后重启 Finder。", "Saved. If the menu has not updated, reopen the Finder window or restart Finder after file operations finish."))
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 12)
            }
            HStack {
                Button(L10n.text("刷新列表", "Refresh List")) { Task { await refresh() } }
                    .disabled(loading || changingID != nil)
                Button(L10n.text("系统设置…", "System Settings…")) { openExtensionsSettings() }
                Spacer(minLength: 8)
                if needsFinderRefresh {
                    Button(L10n.text("重启 Finder", "Restart Finder")) { FinderControl.restartFinder() }
                }
            }.controlSize(.small).padding(.vertical, 14)
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard changingID == nil else { return }
            Task { await refresh() }
        }
    }

    @MainActor private func refresh() async {
        loading = true
        extensions = await Task.detached(priority: .utility) { FinderExtensionManager.list() }.value
        loading = false
    }

    @MainActor private func setEnabled(_ ext: FinderExtensionInfo, enabled: Bool) async {
        changingID = ext.bundleID
        error = nil
        let succeeded = await Task.detached(priority: .utility) {
            FinderExtensionManager.setEnabled(bundleID: ext.bundleID, enabled: enabled)
        }.value
        await refresh()
        if succeeded, extensions.first(where: { $0.bundleID == ext.bundleID })?.isEnabled == enabled {
            needsFinderRefresh = true
        } else {
            error = L10n.text("未能更改此扩展。请在系统设置中调整，然后刷新列表。", "Could not change this extension. Adjust it in System Settings, then refresh the list.")
        }
        changingID = nil
    }

    private func openExtensionsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }
}
