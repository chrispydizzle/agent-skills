<#
.SYNOPSIS
  Decompile one or more obfuscated Burp classes with multiple Java decompilers
  (CFR, Procyon, Vineflower) and present the results side by side.

  Authorised, educational static analysis only. This script observes and
  documents bytecode; it does not patch, bypass, or modify the target. See
  files\how-to.md for scope.

.DESCRIPTION
  Obfuscated bytecode frequently makes any single decompiler emit wrong or
  unreconstructable output. Running several decompilers over the same class
  and diffing them separates real logic from per-decompiler artifacts.

.PARAMETER Class
  One or more class identifiers. Accepts short obfuscated names (Zpq0),
  fully-qualified names (burp.Zpq0, net.portswigger.Ztb), or a full path to a
  .class file. Short names are resolved against the classes tree.

.PARAMETER Tools
  Which decompilers to run. Default: all available (cfr, procyon, vineflower).

.PARAMETER ShowDiff
  Print a line diff between the first tool and each other tool.

.PARAMETER Open
  Open the generated .java files. If VS Code (code) is available and exactly
  two tools ran, opens them in diff view; otherwise opens each file.

.EXAMPLE
  .\decompile-compare.ps1 -Class Zpq0
.EXAMPLE
  .\decompile-compare.ps1 -Class Zpq0,Zj25,Zwfq -ShowDiff
.EXAMPLE
  .\decompile-compare.ps1 -Class net.portswigger.Ztb -Tools cfr,procyon -Open
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string[]] $Class,

  [ValidateSet('cfr', 'procyon', 'vineflower')]
  [string[]] $Tools = @('cfr', 'procyon', 'vineflower'),

  [switch] $ShowDiff,
  [switch] $Open
)

$ErrorActionPreference = 'Stop'

# --- Layout ---------------------------------------------------------------
$root        = Split-Path -Parent $MyInvocation.MyCommand.Path
$classesRoot = Join-Path $root 'classes'
$burpDir     = Join-Path $classesRoot 'burp'
$psDir       = Join-Path $classesRoot 'net\portswigger'
$toolsDir    = Join-Path $root 'files\tools'
$outRoot     = Join-Path $root 'files\src\compare'

$jars = @{
  cfr        = Join-Path $toolsDir 'cfr.jar'
  procyon    = Join-Path $toolsDir 'procyon.jar'
  vineflower = Join-Path $toolsDir 'vineflower.jar'
}

# Extra classpath so decompilers can resolve obfuscated cross-references.
$cp = @($burpDir, $psDir, $classesRoot) | Where-Object { Test-Path $_ }
$cpJoined = ($cp -join ';')

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  throw "java not found on PATH."
}

# Drop tools whose jar is missing.
$Tools = $Tools | Where-Object {
  if (Test-Path $jars[$_]) { $true }
  else { Write-Warning "Skipping '$_': jar not found at $($jars[$_])"; $false }
}
if (-not $Tools) { throw "No decompiler jars available in $toolsDir." }

# --- Resolve a class identifier to a .class file path ---------------------
function Resolve-ClassFile([string] $id) {
  if ($id -match '\.class$' -and (Test-Path $id)) { return (Resolve-Path $id).Path }

  $name = $id -replace '\.class$', ''
  # Fully-qualified -> path under classesRoot.
  if ($name -match '[./]') {
    $rel = ($name -replace '\.', '\') + '.class'
    $p = Join-Path $classesRoot $rel
    if (Test-Path $p) { return $p }
  }
  # Short name: try burp\, then net\portswigger\, then anywhere in the tree.
  foreach ($d in @($burpDir, $psDir)) {
    $p = Join-Path $d "$name.class"
    if (Test-Path $p) { return $p }
  }
  $hit = Get-ChildItem $classesRoot -Recurse -Filter "$name.class" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

# --- Per-tool invocation; returns decompiled source as a string -----------
function Invoke-Decompiler([string] $tool, [string] $classFile, [string] $workDir) {
  switch ($tool) {
    'cfr' {
      return (java -jar $jars.cfr --extraclasspath $cpJoined $classFile 2>$null) -join "`n"
    }
    'procyon' {
      return (java -jar $jars.procyon $classFile 2>$null) -join "`n"
    }
    'vineflower' {
      # Vineflower writes a .java into an output dir; capture and return it.
      $vfOut = Join-Path $workDir '_vf'
      Remove-Item $vfOut -Recurse -Force -ErrorAction SilentlyContinue
      New-Item -ItemType Directory -Force -Path $vfOut | Out-Null
      java -jar $jars.vineflower "-e=$classesRoot" $classFile $vfOut 2>$null | Out-Null
      $jf = Get-ChildItem $vfOut -Filter *.java -ErrorAction SilentlyContinue | Select-Object -First 1
      $text = if ($jf) { Get-Content $jf.FullName -Raw } else { '' }
      Remove-Item $vfOut -Recurse -Force -ErrorAction SilentlyContinue
      return $text
    }
  }
}

# Heuristic warning scan so the summary flags low-confidence output.
function Get-DecompileWarnings([string] $text) {
  $pat = 'Could not load|Could not be decompiled|couldn''t be decompiled|\$FF:|\$VF:|parsing failure|Unable to'
  $hits = [regex]::Matches($text, $pat)
  return $hits.Count
}

# --- Main loop ------------------------------------------------------------
$generated = @()

foreach ($id in $Class) {
  $classFile = Resolve-ClassFile $id
  if (-not $classFile) { Write-Warning "Class not found: $id"; continue }

  $clsName = [IO.Path]::GetFileNameWithoutExtension($classFile)
  $outDir  = Join-Path $outRoot $clsName
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null

  Write-Host ""
  Write-Host "==== $clsName ====" -ForegroundColor Cyan
  Write-Host "source: $classFile"

  $rows = @()
  foreach ($t in $Tools) {
    $src = Invoke-Decompiler -tool $t -classFile $classFile -workDir $outDir
    $outFile = Join-Path $outDir "$t.java"
    Set-Content -Path $outFile -Value $src -Encoding utf8
    $lines = ($src -split "`n").Count
    $warn  = Get-DecompileWarnings $src
    $rows += [pscustomobject]@{
      Tool     = $t
      Lines    = $lines
      Warnings = $warn
      Output   = $outFile
    }
    $generated += $outFile
  }

  $rows | Format-Table Tool, Lines, Warnings, Output -AutoSize | Out-String | Write-Host

  if ($ShowDiff -and $rows.Count -gt 1) {
    $base = $rows[0]
    $baseLines = Get-Content $base.Output
    foreach ($r in $rows[1..($rows.Count - 1)]) {
      Write-Host "---- diff: $($base.Tool) vs $($r.Tool) ($clsName) ----" -ForegroundColor Yellow
      $cmp = Compare-Object $baseLines (Get-Content $r.Output) -SyncWindow 50
      if (-not $cmp) {
        Write-Host "  (identical line set)"
      } else {
        $cmp | ForEach-Object {
          $sigil = if ($_.SideIndicator -eq '<=') { "-[$($base.Tool)]" } else { "+[$($r.Tool)]" }
          "  $sigil $($_.InputObject)"
        } | Select-Object -First 60 | Write-Host
        if ($cmp.Count -gt 60) { Write-Host "  ... ($($cmp.Count - 60) more differing lines)" }
      }
    }
  }

  if ($Open) {
    $code = Get-Command code -ErrorAction SilentlyContinue
    $files = $rows.Output
    if ($code -and $files.Count -eq 2) {
      & code --diff $files[0] $files[1]
    } elseif ($code) {
      & code @files
    } else {
      $files | ForEach-Object { Start-Process $_ }
    }
  }
}

Write-Host ""
Write-Host "Done. Outputs under: $outRoot" -ForegroundColor Green
$generated | ForEach-Object { Write-Host "  $_" }
