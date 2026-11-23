# GitHub 更新检查

妙右通过 GitHub Releases 检查公开的稳定发行版，更新源在 `Packaging/Info-App.plist` 的 `MiaoRightUpdateRepository` 中配置，当前为 `legjs/MiaoRight`。不需要在 App 中放入 GitHub Token。

用户可在「通用 → 软件更新」或 App 菜单「检查更新…」中手动检查。发现高于当前安装版本的发行版后，显示版本号、发行说明与 GitHub 下载页面入口；不会自行替换或执行下载的程序。

## 版本发布准备

1. 同步修改 `Packaging/Info-App.plist` 和 `Packaging/Info-FinderSync.plist` 的 `CFBundleShortVersionString`（例如 `1.0.1`），并递增 `CFBundleVersion`。
2. 执行 `./scripts/build-app.sh release` 构建和签名，验证最终 App。
3. 在具备发布权利和相应签名、分发条件后，为对应提交创建 GitHub Release，例如标签 `v1.0.1`，填写版本说明并附上可供下载的安装包。仅创建 Git 标签不会生成可检查的发行版。
4. 发行版须公开且不标记为 Draft 或 Pre-release；仓库尚未公开或还没有 Release 时，App 显示「暂未找到可用的公开发行版」，不会误报已经是最新版。

版本按数值比较（`1.10.0` 高于 `1.9.0`），支持 `v` 前缀与语义版本预发布标识，忽略构建元数据。网络故障、GitHub 限流、响应异常会分别显示失败提示并允许重试。首次启动不会自动联网检查。

若更换 GitHub 仓库，修改上述更新源配置并重新构建；旧版本仍会查询原地址，需要在原仓库保留迁移说明。
