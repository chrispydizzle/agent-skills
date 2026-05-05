#!/usr/bin/env sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  scripts/install.sh --all [--force] [--target DIR]
  scripts/install.sh --skill NAME [--skill NAME ...] [--force] [--target DIR]

Defaults:
  --target defaults to $HOME/.copilot/skills.

Examples:
  scripts/install.sh --all --force
  scripts/install.sh --all --force --target "$HOME/.claude/skills"
  scripts/install.sh --skill log-analysis-sherlock --skill android-privesc-sherlock --force
EOF
}

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
skills_root="$repo_root/.agents/skills"
target="${HOME:-}/.copilot/skills"
force=0
all=0
skills=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      all=1
      ;;
    --force)
      force=1
      ;;
    --target)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --target" >&2; exit 2; }
      target=$1
      ;;
    --skill)
      shift
      [ "$#" -gt 0 ] || { echo "missing value for --skill" >&2; exit 2; }
      skills="${skills}${skills:+
}$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[ -d "$skills_root" ] || { echo "skills root not found: $skills_root" >&2; exit 1; }

if [ "$all" -eq 1 ] && [ -n "$skills" ]; then
  echo "pass either --all or one or more --skill entries, not both" >&2
  exit 2
fi

if [ "$all" -eq 0 ] && [ -z "$skills" ]; then
  echo "pass --all or at least one --skill entry" >&2
  exit 2
fi

if [ "$all" -eq 1 ]; then
  skills=$(find "$skills_root" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
fi

mkdir -p "$target"

printf '%s\n' "$skills" | while IFS= read -r skill; do
  [ -n "$skill" ] || continue
  source_dir="$skills_root/$skill"
  destination="$target/$skill"

  if [ ! -f "$source_dir/SKILL.md" ]; then
    echo "skill '$skill' is missing SKILL.md at $source_dir" >&2
    exit 1
  fi

  if [ -e "$destination" ]; then
    if [ "$force" -ne 1 ]; then
      echo "skipping existing skill '$skill' (pass --force to replace it)" >&2
      continue
    fi
    rm -rf "$destination"
  fi

  cp -R "$source_dir" "$destination"
  echo "installed $skill -> $destination"
done
