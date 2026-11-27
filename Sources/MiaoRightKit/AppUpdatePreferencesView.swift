import AppKit
import MiaoRightShared
import SwiftUI

struct AppUpdatePreferencesView: View {
    @State private var updates = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceRow(title: L10n.text("软件更新", "Software Update"), icon: "arrow.triangle.2.circlepath", detail: detail) {
                Button(updates.isChecking ? L10n.text("正在检查…", "Checking…") : L10n.text("检查更新", "Check for Updates")) {
                    Task { await updates.checkAndPresentPrompt() }
                }.disabled(updates.isChecking)
            }
            PreferenceRow(title: L10n.text("自动检查更新", "Automatically Check for Updates"), icon: "clock.arrow.circlepath", detail: automaticCheckDetail) {
                Toggle(
                    L10n.text("自动检查更新", "Automatically Check for Updates"),
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
            if updates.isDebugSimulationAvailable {
                PreferenceRow(
                    title: L10n.text("调试：模拟发现新版本", "Debug: Simulate an Available Update"),
                    icon: "hammer",
                    detail: L10n.text(
                        "仅开发签名版本可用。开启后使用本地 v0.1.4 测试包，菜单和更新页显示 v0.1.4，并用模拟内容展示更新日志；如提示缺少调试包，先运行 scripts/build-debug-update.sh。",
                        "Available only in development-signed builds. Uses a local v0.1.4 test package, shows v0.1.4 in the menu and update page, and displays simulated release notes. If the package is missing, run scripts/build-debug-update.sh first."
                    )
                ) {
                    Toggle(
                        L10n.text("模拟发现新版本", "Simulate an Available Update"),
                        isOn: Binding(
                            get: { updates.simulatesAvailableUpdate },
                            set: { updates.setSimulatesAvailableUpdate($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(updates.isInstalling)
                }
            }
            if updates.simulatesAvailableUpdate {
                Text(L10n.text(
                    "调试模拟已开启：菜单显示更新到 v0.1.4，使用本地开发签名测试包直接安装，不会发布到 GitHub。",
                    "Debug simulation is on. The menu shows Update to v0.1.4, the local development-signed test package installs directly, and nothing is published to GitHub."
                ))
                .font(.system(size: 11))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            }
            if case .available(let release) = updates.state {
                availableRelease(release)
            }
            installStatus
            if showsRepositoryLink, let repository = updates.repository {
                Button(L10n.text("查看 GitHub 发行页面", "View GitHub Releases")) { NSWorkspace.shared.open(repository.releasesURL) }
                    .buttonStyle(.borderless).font(.system(size: 12)).padding(.top, 10)
            }
        }
    }

    @ViewBuilder
    private func availableRelease(_ release: GitHubRelease) -> some View {
        let title = updates.simulatesAvailableUpdate
            ? L10n.text("调试模拟：\(release.tagName) 可更新", "Debug simulation: \(release.tagName) is available")
            : (release.name.flatMap { $0.isEmpty ? nil : $0 }
                ?? L10n.text("发现新版本 \(release.tagName)", "Version \(release.tagName) is available"))
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                if release.name?.isEmpty == false {
                    Text(release.tagName).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if let date = release.publishedDate {
                Text(L10n.text("发布于 \(formatDate(date))", "Published \(formatDate(date))"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            let repository = updates.repository
            let currentInstaller = currentInstaller(for: release)

            if let installer = currentInstaller {
                if updates.canInstallInPlace {
                    HStack(spacing: 12) {
                        Button(L10n.text("下载、安装并重新启动", "Download, Install, and Relaunch")) {
                            Task { await updates.installUpdate(release) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updates.isInstalling)
                        Button(L10n.text("发行页面", "Release Page")) { NSWorkspace.shared.open(release.pageURL) }
                            .buttonStyle(.borderless)
                    }
                    Text(L10n.text(
                        "更新会先校验版本、架构和发布证书，然后等待妙右退出，原位替换 /Applications/MiaoRight.app 并重新启动。",
                        "The update verifies its version, architecture, and release certificate, then waits for MiaoRight to quit before replacing /Applications/MiaoRight.app in place and relaunching."
                    ))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    if !updates.isProductionInstallation {
                        if updates.simulatesAvailableUpdate {
                            Text(L10n.text(
                                "调试模拟使用本地开发签名的 v0.1.4 测试包，不会切换生产签名。",
                                "The debug simulation uses a local development-signed v0.1.4 package and does not switch to the production signature."
                            ))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text(L10n.text(
                                "当前是开发签名版本。安装发布包后会切换为生产签名，系统权限和登录项需要重新确认一次。",
                                "This is a development-signed build. Installing the release switches to the production signature and requires confirming system permissions and the login item once."
                            ))
                            .font(.system(size: 11)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        Button(downloadTitle(for: installer)) { NSWorkspace.shared.open(installer.downloadURL) }
                            .buttonStyle(.borderedProminent)
                        Button(L10n.text("打开发行页面", "Open Release Page")) { NSWorkspace.shared.open(release.pageURL) }
                            .buttonStyle(.borderless)
                        if let repository, let checksums = release.checksums(repository: repository) {
                            Button("SHA-256") { NSWorkspace.shared.open(checksums.downloadURL) }
                                .buttonStyle(.borderless)
                        }
                    }
                    Text(L10n.text(
                        "自动安装要求妙右位于 /Applications/MiaoRight.app。请先按安装引导把 App 移入“应用程序”。",
                        "Automatic installation requires MiaoRight at /Applications/MiaoRight.app. Move the app to Applications using the installation guide first."
                    ))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(L10n.text(
                    "这个版本没有提供与当前 \(ReleaseArchitecture.current.displayName) 匹配的安装包，请打开发行页面查看。",
                    "This release has no installer for \(ReleaseArchitecture.current.displayName). Open the release page to check available downloads."
                ))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                Button(L10n.text("打开发行页面", "Open Release Page")) { NSWorkspace.shared.open(release.pageURL) }
            }
        }.padding(.vertical, 16)
    }

    private func currentInstaller(for release: GitHubRelease) -> GitHubReleaseAsset? {
        if updates.simulatesAvailableUpdate, updates.isDebugSimulationAvailable {
            let name = "MiaoRight-\(release.tagName)-\(ReleaseArchitecture.current.rawValue).zip"
            return release.assets.first { $0.name == name }
        }
        guard let repository = updates.repository else { return nil }
        return release.installer(for: .current, repository: repository)
    }

    @ViewBuilder
    private var installStatus: some View {
        switch updates.installState {
        case .idle:
            EmptyView()
        case .downloading:
            installProgress(updates.simulatesAvailableUpdate
                ? L10n.text("正在准备调试更新包…", "Preparing the debug update package…")
                : L10n.text("正在下载更新…", "Downloading update…"))
        case .verifying:
            installProgress(L10n.text("正在校验更新包…", "Verifying update…"))
        case .installing:
            installProgress(L10n.text("正在准备原位安装并重新启动…", "Preparing the in-place install and relaunch…"))
        case .failed(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
    }

    private func installProgress(_ message: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.top, 10)
    }

    private var detail: String {
        switch updates.state {
        case .idle: return L10n.text("当前版本 \(AppUpdateService.currentVersion)，通过 GitHub 检查新版本", "Version \(AppUpdateService.currentVersion); check GitHub for updates")
        case .checking: return L10n.text("正在连接 GitHub…", "Connecting to GitHub…")
        case .upToDate: return L10n.text("当前已是最新版本 \(AppUpdateService.currentVersion)", "You’re up to date: \(AppUpdateService.currentVersion)")
        case .noRelease: return L10n.text(
            "暂未找到可匿名读取的稳定发行版。私有仓库请在浏览器中登录后查看发行页面。",
            "No stable release is publicly readable. For a private repository, sign in to GitHub and open the release page in your browser."
        )
        case .available(let release):
            if updates.simulatesAvailableUpdate {
                return L10n.text(
                    "调试模拟：当前 \(AppUpdateService.currentVersion)，把 \(release.tagName) 视为可更新",
                    "Debug simulation: \(AppUpdateService.currentVersion) treated as updatable to \(release.tagName)"
                )
            }
            return L10n.text("当前 \(AppUpdateService.currentVersion)，最新 \(release.tagName)", "Installed: \(AppUpdateService.currentVersion); latest: \(release.tagName)")
        case .failed(let error): return error.message
        }
    }

    private var automaticCheckDetail: String {
        if let date = updates.lastCheckedAt {
            let checked = L10n.text("上次检查 \(formatDate(date))", "Last checked \(formatDate(date))")
            return updates.automaticallyChecksForUpdates
                ? L10n.text("启动后每天检查一次，\(checked)", "Checks once a day after launch. \(checked)")
                : L10n.text("仅手动检查，\(checked)", "Manual checks only. \(checked)")
        }
        return updates.automaticallyChecksForUpdates
            ? L10n.text("启动后每天检查一次 GitHub 稳定发行版", "Checks GitHub for stable releases once a day after launch")
            : L10n.text("仅在你点击检查更新时联网", "Connects only when you choose Check for Updates")
    }

    private var showsRepositoryLink: Bool {
        switch updates.state {
        case .failed, .noRelease: true
        default: false
        }
    }

    private func downloadTitle(for asset: GitHubReleaseAsset) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(asset.size), countStyle: .file)
        return L10n.text(
            "下载 \(ReleaseArchitecture.current.displayName)版（\(size)）",
            "Download for \(ReleaseArchitecture.current.displayName) (\(size))"
        )
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "zh_CN")
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
