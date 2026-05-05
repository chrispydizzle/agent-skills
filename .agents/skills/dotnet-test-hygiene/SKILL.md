---
name: dotnet-test-hygiene
description: >
  Keep .NET validation runs from polluting the working tree. Use this skill
  whenever running dotnet test, dotnet build, MSBuild, isolated OutDir or
  OutputPath validation, project-reference builds, CI reproduction, or final
  status checks in .NET repositories. It helps choose output directories,
  detect project-local generated artifacts, clean safely, and report validation
  without leaving untracked build output behind.
---

# Dotnet Test Hygiene

Open-source candidate skill for .NET validation output hygiene.

## Core principle

Validation should isolate outputs without hiding source changes. Some MSBuild
properties, especially relative `OutDir` or `OutputPath` values, are interpreted
per project and can create untracked artifact directories under referenced
projects. Treat output cleanup as part of the validation contract.

## Before running validation

1. Inspect the repository ignore rules for existing build-output locations.
2. Prefer the repository's established artifacts directory if one exists.
3. If using a custom output directory, choose a repo-level ignored path with an
   absolute or clearly rooted value.
4. Avoid relative `OutDir` values that can be interpreted separately for each
   project reference.

## Safer command patterns

Prefer one of these approaches:

- Use the repository's normal `dotnet test` command when output isolation is not
  needed.
- Use a clearly ignored repo-level artifact path when isolation is needed.
- Use temporary directories outside the repository when the output does not need
  to survive.

After using custom output properties, run a working-tree check and look for
unexpected directories under project folders.

## Cleanup checklist

Before final status:

1. Check for untracked `artifacts`, `bin`, `obj`, test result, or custom output
   directories under source projects.
2. Remove only generated output directories that came from validation.
3. Do not remove source files, checked-in fixtures, or user-created artifacts.
4. Rerun a targeted status check after cleanup.

## Completion summary

Report:

```markdown
**Validation command:** ...
**Output isolation:** ...
**Generated artifacts cleaned:** ...
**Working tree status:** ...
```

## Anti-patterns

- Assuming `OutDir=artifacts` writes to one central directory.
- Leaving generated project-local artifacts for the user to discover.
- Cleaning broad directories without first confirming they are generated output.
