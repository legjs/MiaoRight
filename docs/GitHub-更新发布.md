# GitHub 发布和更新检查

妙右通过 GitHub Releases 检查公开的稳定发行版，更新源在 `Packaging/Info-App.plist` 的 `MiaoRightUpdateRepository` 中配置，当前为 `legjs/MiaoRight`。不需要在 App 中放入 GitHub Token。

用户可在「通用 → 软件更新」或 App 菜单「检查更新…」中手动检查。发现高于当前安装版本的发行版后，显示版本号、发行说明与 GitHub 下载页面入口；不会自行替换或执行下载的程序。

## 私有版本发布

1. 同步更新 `Packaging/Info-App.plist`、`Packaging/Info-FinderSync.plist` 和 `Packaging/Info-ArchivePreview.plist` 的 `CFBundleShortVersionString`，并递增 `CFBundleVersion`。
2. 执行 `./scripts/build-app.sh release`，并用 `codesign --verify --deep --strict build/MiaoRight.app` 校验包内所有组件。默认使用本机架构，在本地也可以用 `MIAORIGHT_BUILD_ARCH=arm64` 或 `MIAORIGHT_BUILD_ARCH=x86_64` 指定目标。
3. 将版本提交推送到私有仓库，再创建并推送同版本的标签。下面以 `0.1.1` 为例。

   ```bash
   git tag -a v0.1.1 -m "Release MiaoRight 0.1.1"
   git push origin v0.1.1
   ```

[发布工作流](../.github/workflows/release.yml)会在 Apple 芯片和 Intel 运行器上分别构建及测试，两个任务都通过后才创建私有 GitHub Release。发行版包含 `MiaoRight-v0.1.1-arm64.zip`、`MiaoRight-v0.1.1-x86_64.zip` 和 `SHA256SUMS`。每个包都使用匹配架构的 7-Zip，打包后会重新解压并校验签名。GitHub 产物采用 ad-hoc 签名。它们尚未经过 Apple 公证。本机使用 `MiaoRight dev` 签名的构建可继续用于本地开发。

要手动运行某个已推送的版本，在 Actions 的 **Build and release MiaoRight** 工作流选择 **Run workflow**，分支选 `main`，输入版本标签。构建使用标签指向的代码。

## App 内更新检查

App 内检查使用 GitHub 的无凭据接口，只能读取公开稳定版。当前仓库的私有发行版可在已登录且有访问权限的 GitHub Releases 页面查看。

版本按数值比较（`1.10.0` 高于 `1.9.0`），支持 `v` 前缀与语义版本预发布标识，忽略构建元数据。网络故障、GitHub 限流、响应异常会分别显示失败提示并允许重试。首次启动不会自动联网检查。

若更换 GitHub 仓库，修改上述更新源配置并重新构建；旧版本仍会查询原地址，需要在原仓库保留迁移说明。
