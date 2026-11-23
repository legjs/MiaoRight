import AppKit
import MiaoRightShared
import SwiftUI

struct QuickFilePreferencesView: View {
    @Environment(ScriptStore.self) private var store
    @State private var error: String?
    @State private var foldersExpanded: Bool
    @State private var templatesExpanded: Bool

    init(initiallyExpanded: Bool = false) {
        _foldersExpanded = State(initialValue: initiallyExpanded)
        _templatesExpanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureGroup(L10n.text("常用文件夹", "Favorite Folders"), isExpanded: $foldersExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("在右键菜单中快速打开，或把文件复制、移动到这里。", "Open these folders or copy and move files to them from the context menu."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 8)
                    ForEach(QuickFilePreferences.folders(in: store)) { folder in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(folder.title).font(.system(size: 13, weight: .medium))
                                    Text(folder.url.path).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                                }
                                Spacer()
                                Button(L10n.text("移除", "Remove")) { QuickFilePreferences.removeFolder(folder, store: store) }.buttonStyle(.borderless)
                            }
                            HStack(spacing: 16) {
                                folderToggle(folder, kind: .openFolder, title: L10n.text("打开", "Open"))
                                folderToggle(folder, kind: .copy, title: L10n.text("复制到", "Copy To"))
                                folderToggle(folder, kind: .move, title: L10n.text("移动到", "Move To"))
                            }.font(.system(size: 12)).toggleStyle(.checkbox)
                            if !folder.isAvailable { Text(L10n.text("文件夹已不可用，请重新添加。", "This folder is unavailable. Add it again.")).font(.system(size: 12)).foregroundStyle(.orange) }
                            Divider().padding(.top, 5)
                        }.padding(.vertical, 10)
                    }
                    Button(L10n.text("添加文件夹…", "Add Folder…")) { chooseFolders() }.padding(.vertical, 12)
                }
            }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "folder.badge.plus", summary: L10n.text("右键直达，复制与移动到固定位置", "Quick access and fixed copy/move destinations")))

            DisclosureGroup(L10n.text("文件模板", "File Templates"), isExpanded: $templatesExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(L10n.text("添加一份现成文件，例如报价单或日报。右键新建副本，原模板保持不变。", "Add an existing file, such as a quote or daily report. Create copies from the context menu while keeping the template intact."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding(.bottom, 8)
                    ForEach(QuickFilePreferences.templates(in: store)) { script in
                        if let shortcut = QuickFileShortcut(content: script.content) {
                            PreferenceRow(title: shortcut.title, icon: "doc", detail: shortcut.isAvailable ? URL(fileURLWithPath: shortcut.targetPath).lastPathComponent : L10n.text("模板已丢失，请重新添加", "Template missing; add it again")) {
                                Toggle(L10n.text("在菜单显示", "Show in Menu"), isOn: Binding(get: { script.isEnabled }, set: { enabled in var item = script; item.isEnabled = enabled; store.updateScript(item) }))
                                    .labelsHidden().toggleStyle(.switch).accessibilityLabel(shortcut.title)
                                Button(L10n.text("移除", "Remove")) { QuickFilePreferences.removeTemplate(script, store: store) }.buttonStyle(.borderless)
                            }
                        }
                    }
                    Button(L10n.text("添加模板…", "Add Template…")) { chooseTemplates() }.padding(.vertical, 12)
                }
            }.disclosureGroupStyle(PreferenceDisclosureStyle(icon: "doc.badge.plus", summary: L10n.text("用现有文档快速创建新副本", "Create new copies from your existing documents")))
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).textSelection(.enabled).padding(.vertical, 10) }
        }.padding(.top, 12)
    }

    private func folderToggle(_ folder: QuickFilePreferences.Folder, kind: QuickFileShortcut.Kind, title: String) -> some View {
        Toggle(title, isOn: Binding(get: { folder.actions[kind]?.isEnabled == true }, set: { enabled in
            guard var script = folder.actions[kind] else { return }
            script.isEnabled = enabled; store.updateScript(script)
        })).accessibilityLabel(folder.title + " — " + title)
    }

    private func chooseFolders() {
        guard !AppGroup.isIsolated else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = true
        panel.prompt = L10n.text("添加", "Add")
        guard panel.runModal() == .OK else { return }
        error = nil
        do { for url in panel.urls { try QuickFilePreferences.addFolder(url, store: store) } }
        catch { self.error = error.localizedDescription }
    }

    private func chooseTemplates() {
        guard !AppGroup.isIsolated else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        panel.prompt = L10n.text("添加模板", "Add Template")
        guard panel.runModal() == .OK else { return }
        error = nil
        do { for url in panel.urls { try QuickFilePreferences.addTemplate(url, store: store) } }
        catch { self.error = error.localizedDescription }
    }
}
