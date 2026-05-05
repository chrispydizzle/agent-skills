param(
    [string[]]$Skill = @(),
    [switch]$All,
    [string]$Target = "$env:USERPROFILE\.copilot\skills",
    [string]$SkillsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) ".agents\skills"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($All -eq ($Skill.Count -gt 0)) {
    throw "Pass either -All or -Skill <name>[,<name>]."
}

if (-not (Test-Path -LiteralPath $SkillsRoot)) {
    throw "Skills root not found: $SkillsRoot"
}

if ($All) {
    $Skill = Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
}

New-Item -ItemType Directory -Force -Path $Target | Out-Null

foreach ($name in $Skill) {
    $source = Join-Path $SkillsRoot $name
    $skillFile = Join-Path $source "SKILL.md"
    if (-not (Test-Path -LiteralPath $skillFile)) {
        throw "Skill '$name' does not exist at $source or is missing SKILL.md."
    }

    $destination = Join-Path $Target $name
    if (Test-Path -LiteralPath $destination) {
        if (-not $Force) {
            Write-Warning "Skipping existing skill '$name'. Pass -Force to replace it."
            continue
        }
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    Copy-Item -LiteralPath $source -Destination $destination -Recurse
    Write-Host "Installed $name -> $destination"
}
