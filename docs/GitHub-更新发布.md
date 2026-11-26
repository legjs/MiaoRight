# GitHub 发布和更新检查

妙右通过 GitHub Releases 检查公开的稳定发行版，更新源在 `Packaging/Info-App.plist` 的 `MiaoRightUpdateRepository` 中配置，当前为 `legjs/MiaoRight`。不需要在 App 中放入 GitHub Token。

用户可在「通用 → 软件更新」或 App 菜单「检查更新…」中手动检查。App 默认每天最多自动检查一次，可在同一页关闭自动检查。发现高于当前安装版本的发行版后，显示版本号、发行名称、日期、发行说明和与当前 Mac 芯片匹配的安装包大小，并保留发行页面与 `SHA256SUMS`。新版本结果会跨启动保留，已追平后自动清除。菜单栏图标菜单也提供检查更新入口，有可用更新时可直接打开更新日志。更新页只下载与当前架构匹配的资产，不提供手动选择 ZIP。

生产更新要求 App 位于 `/Applications/MiaoRight.app`。App 可以下载公开 Release 中的 ZIP，也可以让用户选择已下载的 ZIP；校验 Bundle ID、发行版本、架构、主程序与嵌套扩展的固定证书指纹后，等待妙右退出，将旧包备份、用新包原位替换 `/Applications/MiaoRight.app`，最后重新打开并重启 Finder 以加载扩展。安装失败时恢复旧包。开发签名版本在 Applications 中也可使用该入口，首次切换为生产签名时会提示重新确认系统权限和登录项。

## 公开版本发布

1. 同步更新 `Packaging/Info-App.plist`、`Packaging/Info-FinderSync.plist` 和 `Packaging/Info-ArchivePreview.plist` 的 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。
2. 执行 `./scripts/build-app.sh release`，并用 `codesign --verify --deep --strict build/MiaoRight.app` 校验包内所有组件。默认使用本机架构，在本地也可以用 `MIAORIGHT_BUILD_ARCH=arm64` 或 `MIAORIGHT_BUILD_ARCH=x86_64` 指定目标。
3. 将版本提交推送到公开仓库，再创建并推送同版本的标签。下面以 `0.1.3` 为例。

   ```bash
   git tag -a v0.1.3 -m "Release MiaoRight 0.1.3"
   git push origin v0.1.3
   ```

[发布工作流](../.github/workflows/release.yml)在单个 Apple 芯片运行器上原生构建 arm64、交叉构建 x86_64，再统一执行测试、校验、DMG 打包和发布。每个架构发布一个用于首次安装的 DMG 和一个用于应用内更新的 ZIP，并附上 `SHA256SUMS`。例如 `MiaoRight-v0.1.3-arm64.dmg`、`MiaoRight-v0.1.3-arm64.zip`、`MiaoRight-v0.1.3-x86_64.dmg` 和 `MiaoRight-v0.1.3-x86_64.zip`。

DMG 由 `scripts/package-dmg.sh` 生成，包含 `MiaoRight.app`、指向 `/Applications` 的快捷方式和安装说明。构建时会校验 App 架构和深度签名，创建后再次挂载，检查 App、快捷方式和签名，再验证 DMG 校验和。ZIP 会重新解压并校验签名。发布包使用长期有效的 `MiaoRight Release` 身份签名，但尚未经过 Apple 公证。

## 发布签名

发布包使用独立的长期有效 `MiaoRight Release` 身份签名，本地开发继续使用 `MiaoRight dev`。发布工作流会从 Actions Secrets 中导入发布证书，在临时钥匙串中完成签名后删除钥匙串。以下两个 Secret 必需，当前 `legjs/MiaoRight` 已配置。

- `MIAORIGHT_SIGNING_P12`:证书和私钥导出的 `.p12` 文件，经 Base64 编码后的单行文本
- `MIAORIGHT_SIGNING_P12_PASSWORD`:导出 `.p12` 时设置的密码

密钥轮换时，在钥匙串访问中只选择 `MiaoRight Release` 的身份项目并导出 `.p12`。不要导出整个登录钥匙串。生成 Secret 值后立即删除临时 `.p12`，不要把私钥、密码或 Base64 内容写进仓库、日志或聊天记录。更换证书会让所有已安装版本重新要求系统授权，因此应尽量长期沿用同一张证书。

如果本机安装了 GitHub CLI，可以将编码结果通过标准输入写入 Secret，密码由交互提示输入。

```bash
base64 -i /path/to/MiaoRight-Release.p12 | gh secret set MIAORIGHT_SIGNING_P12
gh secret set MIAORIGHT_SIGNING_P12_PASSWORD
```

工作流会把证书导入临时钥匙串，并用无交互权限和默认钥匙串完成签名。自签身份不需要加入系统信任；查询身份时必须检查所有匹配项，不能只依赖 `find-identity -v`。缺少任一 Secret 或找不到证书时，构建直接失败。构建后的 App 和扩展必须显示 `Authority=MiaoRight Release`，签名要求应包含固定的 `certificate leaf` 指纹。这样同一 Bundle ID 的后续版本可以沿用首次获得的空间权限。自签证书仍无法通过 Apple 公证，首次安装时可能需要在系统中手动允许打开。

发布完成后同步更新 `website/download.html` 中的版本号、DMG 链接和 ZIP 链接，以及该页安装引导中的架构说明。下载页面向首次安装时使用 DMG；应用内更新继续使用版本化 ZIP。旧的 `v0.1.1` 只有 ZIP，后续版本才会同时提供两种格式。

每个稳定标签必须提供 `docs/release-notes/<tag>.md`，并同步更新累计式 [CHANGELOG.md](../CHANGELOG.md) 与 [CHANGELOG.zh-CN.md](../CHANGELOG.zh-CN.md)。发布工作流会把版本文件写为 GitHub Release 正文，并检查两个 changelog 是否包含当前版本；任一缺失时发布会失败。格式遵循 Keep a Changelog 与 [release notes 规范](release-notes/README.md)，分类使用 Added / Changed / Deprecated / Removed / Fixed / Security 及对应中文标题。App 更新页会按当前界面语言提取对应段落并显示分类和项目符号。

要手动运行某个已推送的版本，在 Actions 的 **Build and release MiaoRight** 工作流选择 **Run workflow**，分支选 `main`，输入版本标签。构建使用标签指向的代码。

发布任务使用 macOS 26 运行器及 Xcode 26.5，生成的可执行文件仍以 macOS 14 为最低版本。

## App 内更新检查

App 内检查使用 GitHub 的无凭据接口读取公开稳定版。仓库和 Release 均为公开，普通用户不需要 GitHub 登录即可检查版本、下载 ZIP 并原位安装。

版本按数值比较（`1.10.0` 高于 `1.9.0`），支持 `v` 前缀与语义版本预发布标识，忽略构建元数据。安装包名称必须严格匹配 `MiaoRight-<tag>-<arch>.zip`，页面和下载地址还必须属于 `MiaoRightUpdateRepository` 配置的仓库，否则响应会被拒绝。自动检查失败时保留上一次有效结果；手动检查会显示网络、GitHub 限流、响应异常等具体提示并允许重试。

自动检查在 App 启动后触发，记录最近一次成功请求时间，24 小时内不重复请求。关闭自动检查后只在用户点击时联网。发现新版本会把已验证的发行信息保存在本机，供下次启动继续显示；安装后的版本追上该发行版时会清除缓存。

若更换 GitHub 仓库，修改上述更新源配置并重新构建；旧版本仍会查询原地址，需要在原仓库保留迁移说明。
