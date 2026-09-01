#!/usr/bin/env python3
"""Vendor the pinned Lucide icon set from a verified upstream checkout."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

VERSION = "1.27.0"
COMMIT = "4aec3f892fd6c23063bc2fead83c899b5d412b1c"
FEATURE_ID = "targetor"
EXPECTED_ICON_COUNT = 1756


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def checkout_commit(source: Path) -> str | None:
    if not (source / ".git").exists():
        return None
    try:
        return subprocess.check_output(
            ["git", "-C", str(source), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return None


def split_license(source: Path, destination: Path) -> None:
    text = (source / "LICENSE").read_text(encoding="utf-8")
    marker = "The MIT License (MIT) (for the icons listed above)"
    if marker not in text:
        raise SystemExit("upstream LICENSE does not contain the expected MIT notice")
    isc, mit = text.split(marker, maxsplit=1)
    (destination / "LICENSE-ISC.txt").write_text(isc.rstrip() + "\n", encoding="utf-8")
    (destination / "LICENSE-MIT.txt").write_text(marker + mit, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path, help="Lucide 1.27.0 checkout or extracted archive")
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("Resources/Targetor/Lucide"),
        help="destination resource directory",
    )
    args = parser.parse_args()
    source = args.source.resolve()
    icons_source = source / "icons"
    if not icons_source.is_dir():
        raise SystemExit(f"missing upstream icons directory: {icons_source}")
    commit = checkout_commit(source)
    if commit is not None and commit != COMMIT:
        raise SystemExit(f"expected Lucide commit {COMMIT}, got {commit}")

    svg_files = sorted(icons_source.glob("*.svg"), key=lambda path: path.stem)
    json_files = {path.stem: path for path in icons_source.glob("*.json")}
    if len(svg_files) != EXPECTED_ICON_COUNT or len(json_files) != EXPECTED_ICON_COUNT:
        raise SystemExit(
            f"expected {EXPECTED_ICON_COUNT} SVG/metadata pairs, "
            f"got {len(svg_files)} SVG and {len(json_files)} metadata files"
        )

    output = args.output.resolve()
    temporary = output.with_name(output.name + ".tmp")
    shutil.rmtree(temporary, ignore_errors=True)
    (temporary / "icons").mkdir(parents=True)

    entries: list[dict[str, object]] = []
    for svg in svg_files:
        metadata_path = json_files.get(svg.stem)
        if metadata_path is None:
            raise SystemExit(f"missing metadata for {svg.name}")
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        tags = metadata.get("tags")
        if not isinstance(tags, list) or not all(isinstance(tag, str) for tag in tags):
            raise SystemExit(f"invalid tags for {svg.name}")
        destination = temporary / "icons" / svg.name
        shutil.copyfile(svg, destination)
        entries.append(
            {
                "name": svg.stem,
                "file": f"icons/{svg.name}",
                "tags": tags,
                "sha256": sha256(destination),
            }
        )

    split_license(source, temporary)
    manifest = {
        "schemaVersion": 1,
        "featureID": FEATURE_ID,
        "version": VERSION,
        "upstreamCommit": COMMIT,
        "iconCount": len(entries),
        "icons": entries,
    }
    (temporary / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    shutil.rmtree(output, ignore_errors=True)
    temporary.rename(output)
    print(f"Vendored {len(entries)} Lucide {VERSION} icons into {output}")


if __name__ == "__main__":
    main()
