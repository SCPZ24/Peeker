---
name: releasing-peeker
description: Use when preparing, merging, or publishing a Peeker version, including version bumps, GitHub Releases, release ZIPs, and the SCPZ24/homebrew-peeker Cask.
---

# Releasing Peeker

Use one immutable ZIP: its version, SHA-256, GitHub Release asset, and Homebrew Cask must agree exactly.

## Release contract

- Target is an unreleased `X.Y.Z`; never replace a published ZIP, tag, or release.
- `Resources/Info.plist` is authoritative. Set `CFBundleShortVersionString` to `X.Y.Z`; keep `CFBundleVersion` unchanged unless a build-number change is explicitly requested.
- Replace the current public-version fallback literals in `Sources/PeekerApp/SettingsRootView.swift` and `Sources/PeekerApp/SettingsStore.swift`; update the defaults in `scripts/package-release.sh`, `scripts/render-cask.sh`, `scripts/verify-cask.sh`, and the next-release commands in `docs/RELEASING.md` and `docs/LOCAL_ACCEPTANCE.md`. Preserve historical fixtures and records.
- Commit the release metadata separately, for example `chore: release vX.Y.Z`, on the completed feature branch.

## Local gate

Run on the release branch before any remote mutation. On a fresh checkout, first run `./scripts/bootstrap-dependencies.sh`.

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
```

Also complete the applicable manual checks in `docs/LOCAL_ACCEPTANCE.md`, inspect `dist/Peeker.app` to confirm the `LOGO.png` icon, and verify that the sidecar hash equals `shasum -a 256 dist/Peeker-vX.Y.Z.zip`.

`verify-bundle.sh` expects an ad-hoc, unnotarized local bundle; its Gatekeeper rejection is expected. The repository Actions workflow currently emits a Developer ID/notarized artifact, so do not mix its artifact with this default process. Before using that workflow, first reconcile the signing policy, verifier, release docs, and Cask caveat; then validate the stapled ZIP as the sole final asset.

## Publish

1. Run `git fetch origin`; ensure the release branch fast-forwards `origin/main`, `vX.Y.Z` is absent, and the worktree is clean except for intended release files. If `main` advanced or a merge is needed, stop and report it.
2. `git switch main`, merge with `git merge --ff-only <release-branch>`, then push `main`. Tag that exact SHA with annotated `vX.Y.Z` and push the tag.
3. Create a public, non-draft, non-prerelease GitHub Release. Upload exactly `dist/Peeker-vX.Y.Z.zip` and `dist/Peeker-vX.Y.Z.zip.sha256`; after this point never rebuild, re-sign, or repackage them. Write release notes from the merged user-visible changes.
4. Render the Cask from that same ZIP:

```bash
./scripts/render-cask.sh X.Y.Z /absolute/path/Peeker-vX.Y.Z.zip \
  /absolute/path/homebrew-peeker/Casks/peeker.rb
```

Commit and push only the reviewed Cask update to `SCPZ24/homebrew-peeker` after Ruby syntax and `brew style --cask` pass.
5. Verify the public consumer path: use `brew install --cask SCPZ24/peeker/peeker` when absent, otherwise `brew upgrade --cask peeker`. Confirm `/Applications/Peeker.app` reports `X.Y.Z`.

## Final audit

Record and cross-check: merged `main` SHA, peeled tag SHA, public Release URL/state, ZIP SHA-256 and sidecar, Tap commit, Cask `version`/`sha256`, and installed app version. Any mismatch, failed gate, existing release asset, non-fast-forward merge, or failed public installation invalidates the release; stop and correct it before declaring success.
