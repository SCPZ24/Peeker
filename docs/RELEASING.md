# Releasing Peeker

Peeker is Apple Silicon-only, requires macOS 26 or later, and is distributed through GitHub Releases and `SCPZ24/homebrew-peeker`. Local builds are ad-hoc signed and unnotarized unless a Developer ID identity is explicitly supplied.

## Version contract

`Resources/Info.plist` is the Bundle source of truth. The App Bundle, embedded CLI, tag, archive name, GitHub Release, and Cask must use the same three-component version. v2 protocol and JSON schema are both version `1`.

## v2 local gate

```bash
swift package describe
swift build --disable-sandbox --disable-automatic-resolution
swift build --disable-sandbox --disable-automatic-resolution -c release
swift test --disable-sandbox --disable-automatic-resolution
bash -n script/*.sh scripts/*.sh Tests/Shell/*.sh
./Tests/Shell/build_script_contract.sh
./Tests/Shell/feature_boundary_contract.sh
./Tests/Shell/release_script_contract.sh
plutil -lint Resources/Info.plist Resources/Peeker.entitlements
./scripts/build-app.sh release
./scripts/verify-bundle.sh dist/Peeker.app 2.0.0
```

For local implementation acceptance, create a temporary archive under `.build/verification/` and run `verify-cask.sh` against it. Do not create `dist/Peeker-v2.0.0.zip` unless a formal release is explicitly authorized.

The Bundle gate verifies:

- main executable `Contents/MacOS/Peeker`;
- physically distinct `Contents/MacOS/peeker-cli`;
- arm64-only binaries;
- CLI schema `1`, version `2.0.0`, protocol `1`;
- valid whole-Bundle signature.

The Cask must map the embedded physical executable to user command `peeker`:

```ruby
binary "#{appdir}/Peeker.app/Contents/MacOS/peeker-cli", target: "peeker"
```

Before App launch, verify `status` returns `running:false` and feature commands return `app_not_running` without creating SQLite. After launch, verify status and the three feature config routes.

## Publication

Only after local and manual acceptance are complete:

1. Run `./scripts/package-release.sh 2.0.0` once to create the immutable formal archive.
2. Verify Bundle, checksum, Cask syntax/style, and public command mapping.
3. Create the annotated tag and GitHub Release.
4. Upload the exact ZIP and `.sha256`.
5. Update the external Homebrew Tap from the same ZIP checksum.
6. Verify public install and upgrade.

## First launch / 首次启动

After macOS blocks the first launch, open **System Settings → Privacy & Security**, choose **Open Anyway**, then confirm **Open**. Do not disable Gatekeeper.

首次启动被拦截后，请打开**系统设置 → 隐私与安全**，选择**仍要打开**并确认。不要关闭 Gatekeeper。
