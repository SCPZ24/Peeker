#!/usr/bin/env python3
"""Validate or refresh the checked-in curated Lucide manifest without network access."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

VERSION = "1.27.0"
COMMIT = "4aec3f892fd6c23063bc2fead83c899b5d412b1c"
FEATURE_ID = "targetor"
EXPECTED_ICON_COUNT = 209


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def refreshed_manifest(resource_root: Path) -> dict[str, object]:
    manifest_path = resource_root / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if (
        manifest.get("schemaVersion") != 1
        or manifest.get("featureID") != FEATURE_ID
        or manifest.get("version") != VERSION
        or manifest.get("upstreamCommit") != COMMIT
    ):
        raise SystemExit("manifest metadata does not match the pinned curated Lucide set")

    entries = manifest.get("icons")
    if not isinstance(entries, list) or len(entries) != EXPECTED_ICON_COUNT:
        raise SystemExit(f"expected {EXPECTED_ICON_COUNT} curated manifest entries")

    icon_files = sorted((resource_root / "icons").glob("*.svg"))
    if len(icon_files) != EXPECTED_ICON_COUNT:
        raise SystemExit(f"expected {EXPECTED_ICON_COUNT} checked-in curated SVG files")
    actual_paths = {f"icons/{path.name}" for path in icon_files}

    names: set[str] = set()
    manifest_paths: set[str] = set()
    refreshed_entries: list[dict[str, object]] = []
    for raw_entry in entries:
        if not isinstance(raw_entry, dict):
            raise SystemExit("invalid curated manifest entry")
        name = raw_entry.get("name")
        relative_path = raw_entry.get("file")
        tags = raw_entry.get("tags")
        if (
            not isinstance(name, str)
            or not isinstance(relative_path, str)
            or relative_path != f"icons/{name}.svg"
            or not isinstance(tags, list)
            or not all(isinstance(tag, str) for tag in tags)
        ):
            raise SystemExit(f"invalid curated manifest entry: {raw_entry!r}")
        if name in names or relative_path in manifest_paths:
            raise SystemExit(f"duplicate curated Lucide entry: {name}")
        names.add(name)
        manifest_paths.add(relative_path)
        icon_path = resource_root / relative_path
        if not icon_path.is_file():
            raise SystemExit(f"missing curated Lucide SVG: {relative_path}")
        refreshed_entries.append(
            {
                "name": name,
                "file": relative_path,
                "tags": tags,
                "sha256": sha256(icon_path),
            }
        )

    if manifest_paths != actual_paths:
        extra = sorted(actual_paths - manifest_paths)
        missing = sorted(manifest_paths - actual_paths)
        raise SystemExit(f"curated SVG/manifest mismatch: extra={extra}, missing={missing}")

    return {
        "schemaVersion": 1,
        "featureID": FEATURE_ID,
        "version": VERSION,
        "upstreamCommit": COMMIT,
        "iconCount": EXPECTED_ICON_COUNT,
        "icons": refreshed_entries,
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate or refresh the checked-in curated Lucide resources; never downloads icons."
    )
    parser.add_argument(
        "--resource-root",
        type=Path,
        default=Path("Resources/Targetor/Lucide"),
        help="checked-in curated Lucide resource directory",
    )
    parser.add_argument("--check", action="store_true", help="fail instead of rewriting a stale manifest")
    args = parser.parse_args()

    resource_root = args.resource_root.resolve()
    manifest_path = resource_root / "manifest.json"
    refreshed = refreshed_manifest(resource_root)
    rendered = json.dumps(refreshed, ensure_ascii=False, indent=2) + "\n"
    current = manifest_path.read_text(encoding="utf-8")
    if args.check:
        if current != rendered:
            raise SystemExit("curated Lucide manifest hashes are stale")
        print(f"Validated {EXPECTED_ICON_COUNT} curated Lucide icons without network access")
        return
    manifest_path.write_text(rendered, encoding="utf-8")
    print(f"Refreshed {EXPECTED_ICON_COUNT} curated Lucide manifest entries")


if __name__ == "__main__":
    main()
