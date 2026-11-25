import AppKit
import MiaoRightShared
import SwiftUI
import UniformTypeIdentifiers

struct AppUpdatePreferencesView: View {
    @State private var updates = AppUpdateService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PreferenceRow(title: L10n.text("软件更新", "Software Update"), icon: "arrow.triangle.2.circlepath", detail: detail) {
                Button(updates.isChecking ? L10n.text("正在检查…", "Checking…") : L10n.text("检查更新", "Check for Updates")) {
                    Task { await updates.check() }
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
            if updates.canInstallInPlace {
                PreferenceRow(
                    title: L10n.text("安装已下载的更新", "Install a Downloaded Update"),
                    icon: "shippingbox",
                    detail: L10n.text(
                        "选择发行页面下载的 ZIP，妙右会自动校验、替换 /Applications/MiaoRight.app 并重新启动",
                        "Choose a ZIP downloaded from the release page; MiaoRight verifies it, replaces /Applications/MiaoRight.app, and relaunches automatically"
                    )
                ) {
                    Button(L10n.text("选择 ZIP…", "Choose ZIP…")) { chooseArchive() }
                        .disabled(updates.isInstalling)
                }
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
        let title = release.name.flatMap { $0.isEmpty ? nil : $0 }
            ?? L10n.text("发现新版本 \(release.tagName)", "Version \(release.tagName) is available")
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
            ReleaseNotesView(markdown: release.notes)
            if let repository = updates.repository,
               let installer = release.installer(for: .current, repository: repository) {
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
                        Text(L10n.text(
                            "当前是开发签名版本。安装发布包后会切换为生产签名，系统权限和登录项需要重新确认一次。",
                            "This is a development-signed build. Installing the release switches to the production signature and requires confirming system permissions and the login item once."
                        ))
                        .font(.system(size: 11)).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 12) {
                        Button(downloadTitle(for: installer)) { NSWorkspace.shared.open(installer.downloadURL) }
                            .buttonStyle(.borderedProminent)
                        Button(L10n.text("打开发行页面", "Open Release Page")) { NSWorkspace.shared.open(release.pageURL) }
                            .buttonStyle(.borderless)
                        if let checksums = release.checksums(repository: repository) {
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

    @ViewBuilder
    private var installStatus: some View {
        switch updates.installState {
        case .idle:
            EmptyView()
        case .downloading:
            installProgress(L10n.text("正在下载更新…", "Downloading update…"))
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

    private func chooseArchive(for release: GitHubRelease? = nil) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("选择妙右更新包", "Choose a MiaoRight Update")
        panel.message = L10n.text(
            "选择从妙右发行页面下载的 ZIP。安装前会校验版本、架构和签名。",
            "Choose the ZIP downloaded from the MiaoRight release page. Its version, architecture, and signature will be verified."
        )
        panel.allowedContentTypes = [.zip]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            if let release {
                await updates.installUpdate(release, archiveURL: url)
            } else {
                await updates.installDownloadedUpdate(from: url)
            }
        }
    }

    private var detail: String {
        switch updates.state {
        case .idle: L10n.text("当前版本 \(AppUpdateService.currentVersion)，通过 GitHub 检查新版本", "Version \(AppUpdateService.currentVersion); check GitHub for updates")
        case .checking: L10n.text("正在连接 GitHub…", "Connecting to GitHub…")
        case .upToDate: L10n.text("当前已是最新版本 \(AppUpdateService.currentVersion)", "You’re up to date: \(AppUpdateService.currentVersion)")
        case .noRelease: L10n.text(
            "暂未找到可匿名读取的稳定发行版。私有仓库请在浏览器中登录后查看发行页面。",
            "No stable release is publicly readable. For a private repository, sign in to GitHub and open the release page in your browser."
        )
        case .available(let release): L10n.text("当前 \(AppUpdateService.currentVersion)，最新 \(release.tagName)", "Installed: \(AppUpdateService.currentVersion); latest: \(release.tagName)")
        case .failed(let error): error.message
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
