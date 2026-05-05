param(
    [string]$Source = "$env:USERPROFILE\.copilot\skills",
    [string]$SkillsRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) ".agents\skills"),
    [string[]]$Skill = @()
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $Source)) {
    throw "Source skills directory not found: $Source"
}

if (-not (Test-Path -LiteralPath $SkillsRoot)) {
    throw "Repository skills root not found: $SkillsRoot"
}

if ($Skill.Count -eq 0) {
    $Skill = Get-ChildItem -LiteralPath $SkillsRoot -Directory | Sort-Object Name | Select-Object -ExpandProperty Name
}

foreach ($name in $Skill) {
    $sourceSkill = Join-Path $Source $name
    $sourceSkillFile = Join-Path $sourceSkill "SKILL.md"
    if (-not (Test-Path -LiteralPath $sourceSkillFile)) {
        Write-Warning "Skipping '$name'; source skill is missing SKILL.md at $sourceSkill."
        continue
    }

    $destination = Join-Path $SkillsRoot $name
    if (Test-Path -LiteralPath $destination) {
        Remove-Item -LiteralPath $destination -Recurse -Force
    }

    Copy-Item -LiteralPath $sourceSkill -Destination $destination -Recurse
    Write-Host "Synced $name"
}
