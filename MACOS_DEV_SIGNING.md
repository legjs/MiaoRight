# macOS 签名与系统权限(开发与生产)

> 目的:让 macOS 开发版应用拥有**稳定的代码签名身份**和**绑定应用自身的权限授权**(如完全磁盘访问、屏幕录制、辅助功能),避免"每次重新编译就要重新授权"或"权限跟启动者走"的问题。
> 适用:所有在 macOS 上做本地开发、且需要 TCC 保护权限(磁盘/屏幕/辅助功能/摄像头等)的项目。

妙右的 `./scripts/build-app.sh release` 使用本机的 `MiaoRight dev` 身份签名，缺少证书时使用 ad-hoc 签名。内置 7-Zip、Finder Sync 和 Quick Look 扩展先分别签名，再签名主程序。用 `codesign --verify --deep --strict build/MiaoRight.app` 验证整个 App，然后通过 `open build/MiaoRight.app` 启动。

本地开发继续使用 `MiaoRight dev`。GitHub 发布使用独立的 `MiaoRight Release` 证书，通过 Actions Secrets 导入临时钥匙串。两张证书都长期保留，本地开发权限和已安装生产版本的权限互不影响。Secret 配置与发布校验见 [GitHub 发布和更新检查](docs/GitHub-更新发布.md)。

## 妙右当前使用的两张证书

| 用途 | 证书 | 存放位置 | 当前身份指纹 |
| --- | --- | --- | --- |
| 本地开发 | `MiaoRight dev` | 本机登录钥匙串 | `F38251E212E005FF095FD8D822AB08B898F78FC9` |
| GitHub 发布 | `MiaoRight Release` | 本机登录钥匙串，以及 `legjs/MiaoRight` Actions Secrets | `CAA0C3B678A217E14206AF09EE216B57D4DDDA16` |

两张证书均为 10 年期自签代码签名证书，不依赖 Apple Developer Program。`MiaoRight dev` 证书 SHA-256 指纹为 `7E10E3418538C6EB64E4E60458078F0E2F8B48EB7AB187DD523BEF42BFF34887`，有效至 2036-09-20。`MiaoRight Release` 证书 SHA-256 指纹为 `3F06205D8D13F8C954124468053523DFEB45635267D81D8DF7987632E3027704`，有效至 2036-11-21。

证书指纹属于公开信息，可以记录和比对。证书私钥不可导出到仓库、日志、聊天或普通备份目录。`MiaoRight Release` 的私钥必须保留在登录钥匙串，并另存一份加密离线备份到密码管理器。GitHub Secret 无法重新读出，不能代替私钥备份。

## 为什么这张自签证书能让授权沿用

系统隐私授权记录的是 App 的代码要求，而不是简单按文件名判断。由稳定证书签名后，代码要求形如：

```text
identifier "com.miaoright.app" and certificate leaf = H"固定证书指纹"
```

同一证书、同一 Bundle ID、同一签名组件构建出的新版本满足相同代码要求，因此更新后可以继续使用辅助功能、输入监控、Finder 扩展等已有授权。

ad-hoc 签名没有稳定证书。重新构建会改变内容签名，代码要求可能变成 `cdhash`，系统会把它当成新 App，导致重新授权。因此 ad-hoc 只适合不涉及隐私授权的临时测试，不应作为发布方式。

这套机制不需要 Apple 开发者账号。它限制的是系统授权连续性，和 Gatekeeper 公证是两个独立问题。

| 问题 | 稳定自签证书 | Apple Developer ID + 公证 |
| --- | --- | --- |
| 更新后沿用 TCC 授权 | 可以，保持同一证书和 Bundle ID | 可以 |
| 首次安装绕过 Gatekeeper 提示 | 不可以，需要用户手动允许打开 | 可以 |
| 需要 Apple 付费账号 | 不需要 | 需要 |
| 适合公开分发 | 可用，但首次安装体验较差 | 推荐 |

每台 Mac、每个用户账号第一次使用受保护功能时仍需授权。未来版本新增新的受保护能力时，新权限仍会询问一次。更换证书、修改 Bundle ID、删除系统权限或证书到期都会使已有授权失效。

## 开发环境操作

本机开发使用 `MiaoRight dev`。编译后正常退出旧实例并加载新版本：

```bash
./scripts/dev.sh release
```

脚本会把开发签名包更新到 `/Applications/MiaoRight.app` 后启动。macOS 26 曾出现 Finder Sync 扩展在 `build/` 路径中显示已启用、但 Finder 不启动扩展进程的问题；把同一个签名包放入 `/Applications` 并重新注册后，扩展正常加载。因此本地验证 Finder 右键菜单时应使用脚本安装后的路径，不要直接用构建目录中的副本。

需要确认签名是否正确时运行：

```bash
security find-identity -v -p codesigning | rg 'MiaoRight dev'
codesign --verify --deep --strict build/MiaoRight.app
codesign -d --verbose=4 build/MiaoRight.app 2>&1 | rg 'Authority='
codesign -d -r- build/MiaoRight.app 2>&1
```

`Authority` 必须显示 `MiaoRight dev`，代码要求必须包含 `certificate leaf`。出现 `cdhash` 或 ad-hoc 警告说明开发证书没有生效。

## 生产环境操作

生产版本使用 `MiaoRight Release`。GitHub Actions 从 `MIAORIGHT_SIGNING_P12` 和 `MIAORIGHT_SIGNING_P12_PASSWORD` 导入证书，并在临时钥匙串中完成签名。缺失 Secret、找不到证书或最终产物不是稳定签名时，流水线必须失败。

本机临时构建生产签名版本时运行：

```bash
MIAORIGHT_SIGNING_IDENTITY='MiaoRight Release' \
MIAORIGHT_REQUIRE_STABLE_SIGNING=1 \
./scripts/build-app.sh release
```

发布后检查：

```bash
codesign --verify --deep --strict build/MiaoRight.app
codesign -d --verbose=4 build/MiaoRight.app 2>&1 | rg 'Authority='
codesign -d -r- build/MiaoRight.app 2>&1
```

当前 Release 代码要求中的证书 leaf 指纹应为 `caa0c3b678a217e14206af09ee216b57d4ddda16`。如果这个值变化，已安装版本的授权会重新询问。

生产更新只在当前 App 位于 `/Applications/MiaoRight.app` 且代码要求包含 `MiaoRight Release` 证书指纹时可用。安装器会依次校验候选包的 Bundle ID `com.miaoright.app`、发行标签对应的版本、当前 Mac 架构、主程序及所有 `.appex` 的固定证书指纹。校验通过后，后台助手等待主程序退出，把旧 App 移到 `.previous`，用 `ditto` 原位复制新包，清除下载隔离标记，重新注册 LaunchServices、重启 Finder 并打开新版本。复制失败会恢复旧包。开发签名版本和从其他路径运行的副本不能自动覆盖生产安装。

手动从浏览器下载未公证的新版本时，Gatekeeper 仍可能提示“无法验证开发者”。这不代表 TCC 授权失效。应用内原地更新可以减少每次下载产生的 Gatekeeper 提示，但不会改变稳定签名的授权规则。

## 证书轮换与恢复

- 优先恢复原证书。证书还在钥匙串且未过期时，不要重新生成同名证书，否则指纹变化会让所有授权失效。
- 证书丢失或私钥泄露时才轮换。轮换后发布新版本，并明确预期所有用户重新授权一次。
- 轮换前保留旧证书一段时间，确保旧版本仍能验证。
- 备份只保存加密 `.p12`，放在密码管理器或加密离线介质，不放在仓库、普通云盘或聊天记录中。
- 不要在 CI 日志中打印 `.p12` 内容、Base64、Secret 密码或完整钥匙串导出结果。

## 背景规则(AI 必须知道的 macOS 行为)

1. **TCC 责任进程归因**:对"裸可执行文件"(非 .app 包),macOS 把权限判定主体归给**启动它的应用**(终端/IDE 等),而不是二进制本身。用户给二进制授权是无效的。
2. **ad-hoc 签名不稳定**:cargo/rustc 链接器默认打 ad-hoc 签名,标识符含内容哈希,**每次重编译都变**,系统视为新程序,旧授权失效。
3. **.app 包拥有自己的身份**:从标准 .app 包(经 LaunchServices 启动)运行时,判定主体 = 包自身的代码签名要求(DR),与启动者无关。
4. **稳定的 DR = 永久授权**:DR 形如 `identifier "固定ID" and certificate leaf = 证书哈希` 时,重编译不改变 DR,授权一次永久有效。

## 标准做法(新项目照此搭建,已有项目照此修复)

### 1. 创建项目专用自签证书(每台开发机一次)

```bash
# 生成 10 年期代码签名证书并导入登录钥匙串
cd /tmp
cat > dev-cert.cnf << 'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = <项目名> dev
[v3]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -keyout dev.key -out dev.crt -days 3650 -config dev-cert.cnf
# 注意:macOS 的 security 只认传统加密的 p12,必须指定 3DES 参数,否则报 MAC verification failed
openssl pkcs12 -export -inkey dev.key -in dev.crt -out dev.p12 \
  -passout pass:<临时密码> -name "<项目名> dev" \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1
security import dev.p12 -k "$HOME/Library/Keychains/login.keychain-db" -P <临时密码> -T /usr/bin/codesign
rm -f dev.key dev.p12 dev-cert.cnf   # 立即清理私钥材料
security find-identity -v -p codesigning   # 确认身份在列
```

也可以用钥匙串访问 → 证书助理手动创建(代码签名类型),名字用 `<项目名> dev`。

### 2. 系统级信任(TCC 相关权限必需;需要 sudo,用户执行)

```bash
security find-certificate -c "<项目名> dev" -p "$HOME/Library/Keychains/login.keychain-db" > ~/dev-cert.pem
sudo security add-trusted-cert -d -p codeSign -k /Library/Keychains/System.keychain ~/dev-cert.pem
rm ~/dev-cert.pem
```

仅做"链接后重签"、不涉及 TCC 权限时,用户级信任(`security add-trusted-cert -p codeSign`,无 -d)即可。

### 3. 编译后自动重签(Rust 项目:linker 包装)

`scripts/codesign-linker.sh`(仓库根,可执行):

```bash
#!/bin/sh
set -e
/usr/bin/cc "$@"
out=; prev=
for arg in "$@"; do
  [ "$prev" = "-o" ] && out=$arg
  prev=$arg
done
if [ -n "$out" ] && [ -f "$out" ]; then
  # --identifier 固定 DR 中的 ID 部分(缺省 ID 含内容哈希,会随重编变化)
  /usr/bin/codesign --force --identifier "<项目>.dev" --sign "<项目名> dev" "$out" >/dev/null 2>&1 || true
fi
```

`.cargo/config.toml`(仓库根及各 crate 子目录中 cargo 实际运行处,注意相对路径):

```toml
[target.aarch64-apple-darwin]
linker = "scripts/codesign-linker.sh"   # 子目录按层级写 ../
```

证书缺失时静默回退(`|| true`),CI/其他平台不受影响。其他语言(J尼/Go/Node 原生模块)同理:在"链接/产出二进制后"调 codesign 重签。

### 4. 需要 TCC 权限的功能:以 .app 包运行(关键)

裸二进制授权无效(见背景 1),必须包成 .app。写一个组装脚本:创建 `Contents/{MacOS,Resources}`,拷入二进制/Info.plist/图标/资源,**数据文件放 `Contents/Resources`(codesign 拒绝 MacOS 下的数据文件),资源解析路径要同时覆盖包内与平铺两种布局**,然后:

```bash
codesign --force --identifier "<项目>.dev" --sign "<项目名> dev" <App>.app
open <App>.app
```

Info.plist 要点:`CFBundleIdentifier` 与 codesign --identifier 一致;开发辅助类应用加 `LSUIElement=true`。

### 5. 用户侧一次性授权(每个项目一次)

系统设置 → 隐私与安全性 → 对应权限面板 → **+** → 选择项目下的 `<App>.app` → 打开。
此后**永远不需要**删除重加、重装或重新授权;权限面板里的条目时间显示旧日期是正常的(文件修改时间 ≠ 授权失效)。

## 排障(权限突然失效时,按此顺序,不要先改签名配置)

1. `codesign -dvv <二进制或包>` → Authority 应为证书名;`codesign -d -r-` → DR 应为 `identifier "<固定ID>" and certificate leaf = ...` 且两次构建对比一致。
2. `codesign -v --strict` → 通过才有效。
3. 判定主体是谁:
   ```bash
   log show --last 5m --predicate 'process == "tccd"' --style compact | grep -E "AUTHREQ_SUBJECT|AUTHREQ_ATTRIBUTION"
   ```
   主体若是启动器(终端/IDE)而非项目 → 应用没以 .app 包运行,走第 4 节。
4. 系统信任缺失:`security dump-trust-settings -d | grep <项目名> dev`。
5. 用户曾给"旧身份"加过授权 → 删掉条目重新加一次(仅在签名体系变更后会发生)。

## 禁止事项(防止把问题搞乱)

- ❌ 不要在未验证 DR 稳定的情况下反复让用户"删除重加授权"。
- ❌ 不要把权限问题归因于"重编译破坏授权"——先用排障第 3 步看判定主体。
- ❌ 不要让用户给终端/IDE 授权来"绕过"——那是把坑留给下一个启动方式。
- ❌ 私钥材料(.p12/.key)用完立即删除,不要提交进仓库。
