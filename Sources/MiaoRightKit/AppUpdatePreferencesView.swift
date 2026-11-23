import AppKit
import MiaoRightShared
import SwiftUI

struct AppUpdatePreferencesView: View {
    @State private var updates = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceRow(title: L10n.text("软件更新", "Software Update"), icon: "arrow.triangle.2.circlepath", detail: detail) {
                Button(updates.isChecking ? L10n.text("正在检查…", "Checking…") : L10n.text("检查更新", "Check for Updates")) {
                    Task { await updates.check() }
                }.disabled(updates.isChecking)
            }
            if case .available(let release) = updates.state {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n.text("发现新版本 \(release.tagName)", "Version \(release.tagName) is available"))
                        .font(.system(size: 13, weight: .medium))
                    if let notes = release.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(notes).font(.system(size: 12)).foregroundStyle(.secondary)
                            .lineLimit(8).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(L10n.text("查看版本并下载", "View Release and Download")) { NSWorkspace.shared.open(release.pageURL) }
                }.padding(.vertical, 16)
            }
            if case .failed = updates.state, let repository = updates.repository {
                Button(L10n.text("查看 GitHub 发行页面", "View GitHub Releases")) { NSWorkspace.shared.open(repository.releasesURL) }
                    .buttonStyle(.borderless).font(.system(size: 12)).padding(.top, 10)
            }
        }
    }

    private var detail: String {
        switch updates.state {
        case .idle: L10n.text("当前版本 \(AppUpdateService.currentVersion)，通过 GitHub 检查新版本", "Version \(AppUpdateService.currentVersion); check GitHub for updates")
        case .checking: L10n.text("正在连接 GitHub…", "Connecting to GitHub…")
        case .upToDate: L10n.text("当前已是最新版本 \(AppUpdateService.currentVersion)", "You’re up to date: \(AppUpdateService.currentVersion)")
        case .noRelease: L10n.text("暂未找到可用的公开发行版，请稍后再试。", "No public release is available yet. Please try again later.")
        case .available(let release): L10n.text("当前 \(AppUpdateService.currentVersion)，最新 \(release.tagName)", "Installed: \(AppUpdateService.currentVersion); latest: \(release.tagName)")
        case .failed(let error): error.message
        }
    }
}
