# Agent Skills

This repository contains authored Agent Skills in the open `SKILL.md` folder
format. The canonical skill folders live under `.agents\skills\`, which matches
the VS Code/GitHub Copilot project skill discovery layout and can be copied into
other skill-compatible clients.

Each skill is a directory with a required `SKILL.md` file and optional
supporting files such as `references\`, `scripts\`, `assets\`, and `evals\`.

## Skills

| Skill | Brief description |
| --- | --- |
| `android-privesc-sherlock` | Android privilege-escalation triage for manifests, dumpsys output, SELinux policy, bugreports, logcat, tombstones, firmware, and kernel exposure. |
| `android-redteam` | Android red-team and reverse-engineering guidance, with emphasis on Samsung tablet attack surface, kernel drivers, SELinux, Knox, binder, and carrier locks. |
| `autonomous-research-loop` | A disciplined loop for long-running research that preserves findings, dead ends, provenance, confidence, and handoff state across iterations. |
| `browser-protocol-automation` | Helps choose the right web automation layer: visible UI, DOM automation, CDP inspection, WebSocket/API replay, or hybrid workflows. |
| `discord-first-class` | Upgrades a squad workflow so Discord becomes the configured primary communication surface, including bot polling, state files, and outbox queuing. |
| `dotnet-test-hygiene` | Keeps .NET build/test validation from polluting the working tree, especially with isolated `OutDir`, project references, and generated artifacts. |
| `human-assist` | Produces a prioritized list of concrete actions a human operator can take when an agent is blocked by missing access, hardware, installs, or physical-world constraints. |
| `log-analysis-sherlock` | Forensic log analysis across application, platform, security, infrastructure, Android, kernel, and vendor diagnostics. |

## Install

### GitHub Copilot / VS Code project skills

Use this repository directly in a project by copying selected skill folders into
that project's `.agents\skills\` directory:

```powershell
New-Item -ItemType Directory -Force -Path C:\path\to\project\.agents\skills
Copy-Item -Recurse .\.agents\skills\log-analysis-sherlock C:\path\to\project\.agents\skills\
```

To install all skills into another project:

```powershell
Copy-Item -Recurse .\.agents\skills\* C:\path\to\project\.agents\skills\
```

### Personal GitHub Copilot CLI skills

Install all skills into your personal Copilot skills directory:

```powershell
.\scripts\install.ps1 -All -Force
```

On macOS/Linux or any shell with POSIX `sh`:

```sh
scripts/install.sh --all --force
```

### Claude Code personal skills

Install all skills into Claude Code's personal skills directory on Windows:

```powershell
.\scripts\install.ps1 -All -Force -Target "$env:USERPROFILE\.claude\skills"
```

On macOS/Linux:

```sh
scripts/install.sh --all --force --target "$HOME/.claude/skills"
```

For project-scoped Claude Code skills, copy selected folders into the target
repository's `.claude\skills\` directory instead.

### Other Agent Skills-compatible clients

Most Agent Skills-compatible clients need the same folder shape:

```text
<client-skill-root>\<skill-name>\SKILL.md
```

Use the installer with the client's configured skills directory:

```powershell
.\scripts\install.ps1 -All -Force -Target C:\path\to\client\skills
```

```sh
scripts/install.sh --all --force --target /path/to/client/skills
```

### Install selected skills

```powershell
.\scripts\install.ps1 -Skill log-analysis-sherlock,android-privesc-sherlock -Force
```

```sh
scripts/install.sh --skill log-analysis-sherlock --skill android-privesc-sherlock --force
```

## Package

Create installable `.skill` archives in `dist\`:

```powershell
python .\scripts\package_skills.py --all --out .\dist
```

Package a subset:

```powershell
python .\scripts\package_skills.py log-analysis-sherlock android-privesc-sherlock --out .\dist
```

The packager validates each skill first and excludes root-level `evals\`
directories by default so evaluation fixtures do not ship in install artifacts.
Use `--include-evals` when you intentionally want to package evals.

If your client supports `.skill` archive imports, import the generated files
from `dist\` using that client's installer, import command, or UI.

## Validate

Run the local Agent Skills format checks:

```powershell
python .\scripts\validate_skills.py
```

The validator checks that each skill has valid frontmatter, a kebab-case `name`
matching its folder, a non-empty `description`, and parseable `evals\evals.json`
when evals are present.

## Update this repo from local skills

When your personal skill directory has newer copies, sync the skills already
tracked by this repo:

```powershell
.\scripts\sync-from-local.ps1
```

By default this reads from `$env:USERPROFILE\.copilot\skills` and updates only
skills that already exist under `.agents\skills\`. Skills authored directly in
this repository are skipped if no matching personal copy exists.

## Licensing and publishing note

There is no repository-wide open-source license yet. Treat each skill's
frontmatter or bundled license as the authority for that skill. Before making
this repository public, review each skill for proprietary or client-specific
details and add explicit license files where needed.
