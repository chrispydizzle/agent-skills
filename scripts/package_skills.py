#!/usr/bin/env python3
"""Package Agent Skills as .skill zip archives."""

from __future__ import annotations

import argparse
import fnmatch
import sys
import zipfile
from pathlib import Path

from validate_skills import iter_skill_dirs, validate_skill


EXCLUDE_DIRS = {"__pycache__", "node_modules"}
EXCLUDE_FILES = {".DS_Store"}
EXCLUDE_GLOBS = {"*.pyc"}
ROOT_EXCLUDE_DIRS = {"evals"}


def should_exclude(rel_path: Path, include_evals: bool) -> bool:
    parts = rel_path.parts
    if any(part in EXCLUDE_DIRS for part in parts):
        return True
    if not include_evals and len(parts) > 1 and parts[1] in ROOT_EXCLUDE_DIRS:
        return True
    if rel_path.name in EXCLUDE_FILES:
        return True
    return any(fnmatch.fnmatch(rel_path.name, pattern) for pattern in EXCLUDE_GLOBS)


def package_skill(skill_dir: Path, output_dir: Path, include_evals: bool) -> Path:
    result = validate_skill(skill_dir)
    if not result.ok:
        messages = "; ".join(result.errors)
        raise ValueError(f"{skill_dir.name} failed validation: {messages}")

    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"{skill_dir.name}.skill"

    with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
        for file_path in sorted(skill_dir.rglob("*")):
            if not file_path.is_file():
                continue
            archive_name = file_path.relative_to(skill_dir.parent)
            if should_exclude(archive_name, include_evals):
                continue
            archive.write(file_path, archive_name)

    return archive_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Package Agent Skills.")
    parser.add_argument("skills", nargs="*", help="Skill names to package.")
    parser.add_argument("--all", action="store_true", help="Package all skills.")
    parser.add_argument(
        "--skills-root",
        default=Path(".agents") / "skills",
        type=Path,
        help="Directory containing skill folders.",
    )
    parser.add_argument(
        "--out",
        default=Path("dist"),
        type=Path,
        help="Output directory for .skill files.",
    )
    parser.add_argument(
        "--include-evals",
        action="store_true",
        help="Include root-level evals directories in packages.",
    )
    args = parser.parse_args()

    if args.all == bool(args.skills):
        parser.error("pass either --all or one or more skill names")

    if args.all:
        skill_dirs = iter_skill_dirs(args.skills_root)
    else:
        skill_dirs = [args.skills_root / name for name in args.skills]

    created: list[Path] = []
    for skill_dir in skill_dirs:
        archive_path = package_skill(skill_dir, args.out, args.include_evals)
        created.append(archive_path)
        print(f"created {archive_path}")

    print(f"\nPackaged {len(created)} skill(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
