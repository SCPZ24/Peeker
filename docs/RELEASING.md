# Releasing Peeker

Peeker releases are Apple Silicon-only, require macOS 26 or later, and are
distributed through GitHub Releases and `SCPZ24/homebrew-peeker`. The app is
ad-hoc signed and is not notarized.

## Version contract

`Resources/Info.plist` is the source of truth. Before releasing, set
`CFBundleShortVersionString` to the intended three-component version. The tag,
archive name, GitHub Release, app bundle and Cask must all use that exact value.
Published release assets are immutable; ship a patch version instead of
replacing an existing ZIP.

## Local release gate

```bash
swift package describe
swift build --disable-sandbox --disable-automatic-resolution
swift test --disable-sandbox --disable-automatic-resolution
bash -n script/*.sh scripts/*.sh Tests/Shell/*.sh
./Tests/Shell/build_script_contract.sh
./Tests/Shell/release_script_contract.sh
./scripts/package-release.sh 1.0.2
./scripts/verify-bundle.sh
./scripts/verify-cask.sh 1.0.2
```

Inspect `dist/Peeker.app` in Finder and confirm that it uses `LOGO.png` as its
icon. Reuse the resulting `dist/Peeker-v1.0.2.zip` for every publication step;
do not rebuild it between computing the checksum and uploading it.

## GitHub and Homebrew

Create the annotated tag and GitHub Release only after the local gate passes.
Upload both the ZIP and its `.sha256` file. Render `Casks/peeker.rb` from the
same ZIP, commit it to `SCPZ24/homebrew-peeker`, then verify a public install:

```bash
brew install --cask SCPZ24/peeker/peeker
brew upgrade --cask peeker
```

## First launch / 首次启动

After macOS blocks the first launch, open **System Settings → Privacy &
Security**, choose **Open Anyway** for Peeker, then confirm **Open**.

首次启动被 macOS 拦截后，请打开**系统设置 → 隐私与安全**，为 Peeker 选择
**仍要打开**，再确认**打开**。不要关闭 Gatekeeper，也不要移除系统的 quarantine
保护。
