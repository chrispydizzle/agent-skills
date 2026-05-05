#!/usr/bin/env python3
"""Validate Agent Skills in this repository."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


ALLOWED_FRONTMATTER_KEYS = {
    "name",
    "description",
    "license",
    "compatibility",
    "metadata",
    "allowed-tools",
    "when_to_use",
    "argument-hint",
    "arguments",
    "disable-model-invocation",
    "user-invocable",
    "model",
    "effort",
    "context",
    "agent",
    "hooks",
    "paths",
    "shell",
}

NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")


class ValidationResult:
    def __init__(self, skill_dir: Path) -> None:
        self.skill_dir = skill_dir
        self.errors: list[str] = []
        self.warnings: list[str] = []

    @property
    def ok(self) -> bool:
        return not self.errors

    def error(self, message: str) -> None:
        self.errors.append(message)

    def warning(self, message: str) -> None:
        self.warnings.append(message)


def _frontmatter_lines(skill_md: Path) -> tuple[list[str] | None, str | None]:
    content = skill_md.read_text(encoding="utf-8")
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return None, "SKILL.md must start with YAML frontmatter marker '---'"

    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return lines[1:index], None

    return None, "SKILL.md frontmatter is missing closing marker '---'"


def parse_frontmatter(skill_md: Path) -> tuple[dict[str, str], str | None]:
    lines, error = _frontmatter_lines(skill_md)
    if error:
        return {}, error
    assert lines is not None

    fields: dict[str, list[str]] = {}
    current_key: str | None = None

    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue

        top_level = not line.startswith((" ", "\t"))
        if top_level and ":" in line:
            key, value = line.split(":", 1)
            key = key.strip()
            fields[key] = [value.strip()]
            current_key = key
            continue

        if current_key is not None:
            fields[current_key].append(line.strip())
            continue

        return {}, f"Could not parse frontmatter line: {line!r}"

    normalized: dict[str, str] = {}
    for key, raw_values in fields.items():
        first = raw_values[0]
        continuation = raw_values[1:]
        if first in {">", "|", ">-", "|-"}:
            value = " ".join(part.strip() for part in continuation if part.strip())
        elif continuation:
            value = " ".join([first, *continuation]).strip()
        else:
            value = first
        normalized[key] = value.strip().strip("\"'")

    return normalized, None


def validate_skill(skill_dir: Path) -> ValidationResult:
    result = ValidationResult(skill_dir)
    skill_md = skill_dir / "SKILL.md"

    if not skill_md.exists():
        result.error("missing SKILL.md")
        return result

    frontmatter, parse_error = parse_frontmatter(skill_md)
    if parse_error:
        result.error(parse_error)
        return result

    unexpected = sorted(set(frontmatter) - ALLOWED_FRONTMATTER_KEYS)
    if unexpected:
        result.error(f"unexpected frontmatter key(s): {', '.join(unexpected)}")

    name = frontmatter.get("name", "").strip()
    if not name:
        result.error("missing required frontmatter field: name")
    elif not NAME_RE.match(name):
        result.error("name must use kebab-case lowercase letters, digits, and hyphens")
    elif len(name) > 64:
        result.error("name is longer than 64 characters")
    elif name != skill_dir.name:
        result.error(f"name '{name}' must match folder name '{skill_dir.name}'")

    description = frontmatter.get("description", "").strip()
    if not description:
        result.error("missing required frontmatter field: description")
    elif len(description) > 1024:
        result.error("description is longer than 1024 characters")
    elif "<" in description or ">" in description:
        result.error("description must not contain angle brackets")

    compatibility = frontmatter.get("compatibility", "").strip()
    if compatibility and len(compatibility) > 500:
        result.error("compatibility is longer than 500 characters")

    evals_file = skill_dir / "evals" / "evals.json"
    if evals_file.exists():
        try:
            evals = json.loads(evals_file.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            result.error(f"evals/evals.json is invalid JSON: {exc}")
        else:
            if evals.get("skill_name") != name:
                result.error("evals/evals.json skill_name must match frontmatter name")
            if not isinstance(evals.get("evals"), list):
                result.error("evals/evals.json must contain an evals array")

    return result


def iter_skill_dirs(skills_root: Path) -> list[Path]:
    if not skills_root.exists():
        raise FileNotFoundError(f"skills root not found: {skills_root}")
    return sorted(path for path in skills_root.iterdir() if path.is_dir())


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Agent Skills.")
    parser.add_argument(
        "--skills-root",
        default=Path(".agents") / "skills",
        type=Path,
        help="Directory containing skill folders.",
    )
    parser.add_argument("skills", nargs="*", help="Optional skill names to validate.")
    args = parser.parse_args()

    skills_root = args.skills_root
    if args.skills:
        skill_dirs = [skills_root / skill for skill in args.skills]
    else:
        skill_dirs = iter_skill_dirs(skills_root)

    results = [validate_skill(skill_dir) for skill_dir in skill_dirs]

    for result in results:
        status = "OK" if result.ok else "FAIL"
        print(f"[{status}] {result.skill_dir.name}")
        for warning in result.warnings:
            print(f"  warning: {warning}")
        for error in result.errors:
            print(f"  error: {error}")

    failures = sum(1 for result in results if not result.ok)
    print(f"\nValidated {len(results)} skill(s), {failures} failure(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
