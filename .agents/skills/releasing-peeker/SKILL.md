---
name: releasing-peeker
description: Use when preparing, merging, or publishing a Peeker version, including version bumps, GitHub Releases, immutable ZIP assets, and the SCPZ24/homebrew-peeker Cask.
---

# 发布 Peeker

发布的核心约束：**只发布一份不可变 ZIP**。其 `X.Y.Z`、SHA-256、GitHub Release、Homebrew Cask 和已安装 App 版本必须一致。

## 先确认发行形态

读取 `docs/RELEASING.md`、相关脚本和 Git 状态；不要依赖旧日志或猜测。

| 候选所在位置 | 正确操作 |
| --- | --- |
| 功能分支可对 `origin/main` 快进 | 在该分支提交发行元数据、跑门禁，然后 `git merge --ff-only` 到 `main`。 |
| 已审核的候选提交已经在 `main` | 直接在 `main` 提交发行元数据、跑门禁并推送；不要为制造合并而重写历史。 |
| `origin/main` 已推进、分支分叉、工作区有未审查变更 | 停止；报告需要整合的提交，不要自动 rebase、普通 merge 或发布。 |

每次在任何远端写操作前执行：

```bash
git fetch origin --prune
git status --short --branch
git log --oneline origin/main..HEAD
git diff --check
git ls-remote --tags origin "refs/tags/vX.Y.Z" "refs/tags/vX.Y.Z^{}"
gh release view "vX.Y.Z" --repo SCPZ24/Peeker
```

目标 tag 或 Release/同名资产已存在时，绝不覆盖；改用新的 patch 版本。最后一条命令的失败必须确认是“release not found”，不能把网络或认证错误当作不存在。

## 同步版本并单独提交

`Resources/Info.plist` 是公开版本的权威来源：将 `CFBundleShortVersionString` 设为纯数字 `X.Y.Z`。除非用户明确要求，否则保持 `CFBundleVersion` 不变。

同步更新以下当前版本值；保留历史 fixture、历史验证记录和既有 Release 资产：

- `Sources/PeekerApp/SettingsRootView.swift`：设置 → 关于页须显示 `vX.Y.Z`，但读取 Bundle 的原始值仍是 `X.Y.Z`。
- `Sources/PeekerApp/SettingsStore.swift`：更新比较使用原始 `X.Y.Z`，不加 `v` 前缀。
- `scripts/package-release.sh`、`scripts/render-cask.sh`、`scripts/verify-cask.sh`：默认版本。
- `docs/RELEASING.md`、`docs/LOCAL_ACCEPTANCE.md`：下一次发行命令与 ZIP 名称。

以独立提交保存这些变更，例如 `chore: release vX.Y.Z`。发行流程 skill 本身如有变更，使用另一个提交，避免与产品版本混在一起。

## 本地正式门禁

在会被 tag 的提交上运行。新 checkout 缺少依赖时，先运行一次 `./scripts/bootstrap-dependencies.sh`。

```bash
swift package describe
swift build --disable-sandbox --disable-automatic-resolution
swift test --disable-sandbox --disable-automatic-resolution
bash -n script/*.sh scripts/*.sh Tests/Shell/*.sh
./Tests/Shell/build_script_contract.sh
./Tests/Shell/release_script_contract.sh
./scripts/package-release.sh X.Y.Z
./scripts/verify-bundle.sh dist/Peeker.app X.Y.Z
./scripts/verify-cask.sh X.Y.Z
shasum -a 256 dist/Peeker-vX.Y.Z.zip
cat dist/Peeker-vX.Y.Z.zip.sha256
```

确认 Bundle 版本是 `X.Y.Z`、`Peeker.icns` 存在且由 `LOGO.png` 生成、ZIP 与 sidecar 的第一个 SHA-256 字段相同。`verify-bundle.sh` 对本地 ad-hoc、未公证包的 Gatekeeper 拒绝是预期结果，不是失败。

这是 SwiftPM 项目的正式发布门禁。`docs/LOCAL_ACCEPTANCE.md` 内的 `xcodebuild` 和硬件检查可作为额外人工验收。若 `xcodebuild` 在加载项目**之前**以 `IDESimulatorFoundation` / `DVTDownloads.framework` 插件错误退出，并与 `docs/VERIFICATION.md` 的已记录主机错误一致，则记录 `SKIPPED-XCODE`；不要因此重装 Xcode，也不要用它阻断已通过的 SwiftPM 正式门禁。其他 Xcode 错误必须如实报告，不能声称 Xcode 构建通过。若用户或发布政策明确要求硬件验收，则如实完成或报告未完成，不能伪造结果。

默认流程使用本地 ad-hoc ZIP。`.github/workflows/release.yml` 的 Developer ID/公证产物与此流程不同；在统一签名策略、`verify-bundle.sh`、文档和 Cask caveat 前，不得混用两类资产。

## 发布不可变资产

1. 若需要整合，执行 `git merge --ff-only <release-branch>`；确认 `HEAD` 是待发行提交，推送 `main`。
2. 在同一 SHA 创建注释 tag：

   ```bash
   git tag -a vX.Y.Z -m "Peeker X.Y.Z"
   git push origin main vX.Y.Z
   ```

3. 使用本地门禁生成的**同一** ZIP 和 sidecar 创建公开、非草稿、非预发布 Release：

   ```bash
   gh release create vX.Y.Z \
     dist/Peeker-vX.Y.Z.zip dist/Peeker-vX.Y.Z.zip.sha256 \
     --repo SCPZ24/Peeker --title "Peeker vX.Y.Z" --notes "<仅列用户可见变更>"
   ```

上传后不得重新打包、重新签名、替换 ZIP 或改写 sidecar；若必须改变资产，停止并选择新的 patch 版本。

## 更新 Homebrew 并验证消费者路径

从已发布 ZIP 渲染 Cask，绝不从另一个本地包或 Actions artifact 计算 hash：

```bash
./scripts/render-cask.sh X.Y.Z /absolute/path/Peeker-vX.Y.Z.zip \
  /absolute/path/homebrew-peeker/Casks/peeker.rb
ruby -c /absolute/path/homebrew-peeker/Casks/peeker.rb
brew style --cask /absolute/path/homebrew-peeker/Casks/peeker.rb
```

在 `SCPZ24/homebrew-peeker` 审核 diff：正常情况下只改变 `version` 和 `sha256`。提交并推送后，真实验证：

```bash
brew list --cask peeker >/dev/null 2>&1 \
  && brew upgrade --cask peeker \
  || brew install --cask SCPZ24/peeker/peeker
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  /Applications/Peeker.app/Contents/Info.plist
```

## 最终审计与交付

只在以下全部成立时宣布发行完成：

- `main` SHA 与 `vX.Y.Z^{}` 相同，远端已可见。
- GitHub Release 为 public、non-draft、non-prerelease，含精确 ZIP 与 `.sha256`。
- Release 的 ZIP digest、sidecar、本地 ZIP 和 Cask `sha256` 完全相同。
- Cask `version` 与安装后 `/Applications/Peeker.app` 都是 `X.Y.Z`。
- 工作区干净；报告 `main` SHA、tag SHA、Release URL、ZIP SHA-256、Tap commit 和实际安装结果。

任何门禁失败、网络/认证错误、签名策略冲突、版本/哈希不一致、非快进条件或消费者安装失败都必须停止并报告；不要以“应该没问题”继续发布。
