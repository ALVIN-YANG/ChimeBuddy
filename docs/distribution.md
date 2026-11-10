# Developer ID 签名与 Apple 公证

GitHub 的 v0.2.2 安装包使用 Developer ID Application 证书签名，启用 Hardened Runtime 和安全时间戳，通过 Apple 公证后装订票据。默认源码构建仍使用 ad-hoc 签名，便于没有分发证书的开发者本机运行。

## 本机发布

先准备有效的 Developer ID Application 证书，以及已由 `notarytool store-credentials` 登记的钥匙串配置。凭据只在本机登记，不写进仓库、命令示例或公开日志。

```sh
python3 scripts/check-public-data.py
python3 scripts/check-public-data.py --history
bash scripts/test.sh
python3 Tests/PublicationChecksTests.py

export CHIMEBUDDY_SIGNING_IDENTITY='YOUR_CERTIFICATE_SHA1'
export CHIMEBUDDY_APP_PATH='.build/developer-id/ChimeBuddy.app'
bash scripts/build.sh

export CHIMEBUDDY_NOTARY_PROFILE='YOUR_EXISTING_KEYCHAIN_PROFILE'
python3 scripts/notarize-release.py "$CHIMEBUDDY_APP_PATH"
```

脚本确认签名类型、Hardened Runtime、安全时间戳和发布权限后才上传。原始 Apple 回执只保存在 `.build/notary-receipts/` 的私有版本目录。上传后先记录提交，再查询同一提交；等待超时不能当作失败后重新上传。重新运行会核对同一候选包并继续查询；候选代码变化时拒绝复用旧公证结果。

只有收到 Apple `Accepted`、装订票据、验证 Gatekeeper 和脱敏检查通过，才生成 `.build/releases/vVERSION/` 中的最终 ZIP、SHA256SUMS.txt 和脱敏验证摘要。发布前还需解压最终 ZIP，重新检查签名、票据、版本、校验和及 Gatekeeper。

## 用户安装与核验

从 GitHub Release 下载 ZIP 和 SHA256SUMS.txt，核验后解压，将 ChimeBuddy.app 放入应用程序目录并打开。

```sh
shasum -a 256 -c SHA256SUMS.txt
codesign --verify --deep --strict /Applications/ChimeBuddy.app
xcrun stapler validate /Applications/ChimeBuddy.app
spctl --assess --type execute --verbose=2 /Applications/ChimeBuddy.app
```

Gatekeeper 结果应包含 `Notarized Developer ID`。不要修改包内文件；这会破坏签名。Apple 公证代表分发包通过公证检查，不等于 App Store 审核，也不代替不同设备、Codex 版本和网络环境的功能验收。

Developer ID 证书必须公开携带开发者名称、团队标识和公钥证书，才能供 macOS 验证；这些信息无法从有效签名中去除。私钥、账号邮箱、密码、API Key、钥匙串配置名称及原始认证回执不随源码或安装包分发。

参考：[Apple 公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[Developer ID](https://developer.apple.com/developer-id/)。
