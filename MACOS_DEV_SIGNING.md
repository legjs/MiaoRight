# macOS 开发期签名与权限(给 AI 的操作规则)

> 目的:让 macOS 开发版应用拥有**稳定的代码签名身份**和**绑定应用自身的权限授权**(如完全磁盘访问、屏幕录制、辅助功能),避免"每次重新编译就要重新授权"或"权限跟启动者走"的问题。
> 适用:所有在 macOS 上做本地开发、且需要 TCC 保护权限(磁盘/屏幕/辅助功能/摄像头等)的项目。

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
