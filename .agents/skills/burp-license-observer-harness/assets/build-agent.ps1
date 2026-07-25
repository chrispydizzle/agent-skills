[CmdletBinding()]
param(
    [string]$AgentRoot,
    [string]$BurpJar = "C:\InfoSec\BurpSuite\App\burpsuite_pro.jar",
    [string]$ByteBuddyJar,
    [string]$ByteBuddyVersion = "1.14.18",
    [string]$JavaExe = "java",
    [string]$JavacExe = "javac",
    [string]$JarExe = "jar",
    [switch]$NoDownload,
    [switch]$NoSmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-Step {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[*] $Message" -ForegroundColor Cyan
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    Write-Step $Description
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $commandOutput = & $FilePath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    if ($exitCode -ne 0) {
        $text = ($commandOutput | Out-String).Trim()
        throw "$Description failed with exit code $exitCode.`n$text"
    }
    return $commandOutput
}

function Resolve-RequiredCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $resolved = Get-Command -Name $Command -ErrorAction SilentlyContinue
    if (-not $resolved) {
        throw "Required command not found: $Command. Install a JDK and ensure java, javac, and jar are on PATH, or pass -JavaExe/-JavacExe/-JarExe."
    }
    return $resolved.Source
}

function Resolve-PreferredJdkCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$ToolName
    )

    if ($Command -ne $ToolName) {
        return Resolve-RequiredCommand -Command $Command
    }

    $preferred = "C:\InfoSec\Tools\jdk-25.0.2\bin\$ToolName.exe"
    if (Test-Path -LiteralPath $preferred) {
        return (Resolve-Path -LiteralPath $preferred).Path
    }

    return Resolve-RequiredCommand -Command $Command
}

function New-RequiredDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Resolve-ByteBuddyJar {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$LibDir,
        [Parameter(Mandatory = $true)][string]$DistDir,
        [string]$ExplicitJar,
        [Parameter(Mandatory = $true)][string]$Version,
        [bool]$DisableDownload
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitJar)) {
        if (-not (Test-Path -LiteralPath $ExplicitJar)) {
            throw "The explicit -ByteBuddyJar path does not exist: $ExplicitJar"
        }
        return (Resolve-Path -LiteralPath $ExplicitJar).Path
    }

    $candidates = @(
        (Join-Path $Root "lib\byte-buddy.jar"),
        (Join-Path $Root "dist\byte-buddy.jar"),
        (Join-Path $LibDir "byte-buddy.jar"),
        (Join-Path $DistDir "byte-buddy.jar")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    if ($DisableDownload) {
        throw "byte-buddy.jar was not found and -NoDownload was set. Pass -ByteBuddyJar C:\path\to\byte-buddy.jar."
    }

    New-RequiredDirectory -Path $LibDir
    $downloadPath = Join-Path $LibDir "byte-buddy.jar"
    $uri = "https://repo1.maven.org/maven2/net/bytebuddy/byte-buddy/$Version/byte-buddy-$Version.jar"

    Write-Step "Downloading Byte Buddy $Version"
    Invoke-WebRequest -Uri $uri -OutFile $downloadPath -UseBasicParsing

    $downloaded = Get-Item -LiteralPath $downloadPath
    if ($downloaded.Length -lt 1MB) {
        throw "Downloaded Byte Buddy JAR is unexpectedly small: $($downloaded.Length) bytes at $downloadPath"
    }

    return $downloaded.FullName
}

$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    (Get-Location).Path
} else {
    $PSScriptRoot
}

if ([string]::IsNullOrWhiteSpace($AgentRoot)) {
    $AgentRoot = Join-Path $scriptRoot "files\agent"
}

$agentRootPath = if (Test-Path -LiteralPath $AgentRoot) {
    (Resolve-Path -LiteralPath $AgentRoot).Path
} else {
    $AgentRoot
}

$srcDir = Join-Path $agentRootPath "src"
$buildDir = Join-Path $agentRootPath "build"
$libDir = Join-Path $agentRootPath "lib"
$distDir = Join-Path $agentRootPath "dist"
$srcFile = Join-Path $srcDir "BurpLicenseObserverAgent.java"
$manifest = Join-Path $agentRootPath "MANIFEST.MF"
$agentJar = Join-Path $distDir "burp-license-observer-agent.jar"
$distByteBuddy = Join-Path $distDir "byte-buddy.jar"
$testLog = Join-Path (Split-Path -Parent $agentRootPath) "burp-license-observer-test.log"

if (-not (Test-Path -LiteralPath $srcFile)) {
    throw "Agent source not found: $srcFile"
}
if (-not (Test-Path -LiteralPath $manifest)) {
    throw "Agent manifest not found: $manifest"
}
if (-not (Test-Path -LiteralPath $BurpJar)) {
    throw "Burp JAR not found: $BurpJar. Pass -BurpJar C:\path\to\burpsuite_pro.jar."
}

New-RequiredDirectory -Path $buildDir
New-RequiredDirectory -Path $libDir
New-RequiredDirectory -Path $distDir

$java = Resolve-PreferredJdkCommand -Command $JavaExe -ToolName "java"
$javac = Resolve-PreferredJdkCommand -Command $JavacExe -ToolName "javac"
$jar = Resolve-PreferredJdkCommand -Command $JarExe -ToolName "jar"
$burpJarPath = (Resolve-Path -LiteralPath $BurpJar).Path
$byteBuddy = Resolve-ByteBuddyJar -Root $agentRootPath -LibDir $libDir -DistDir $distDir -ExplicitJar $ByteBuddyJar -Version $ByteBuddyVersion -DisableDownload ([bool]$NoDownload)
$compileClassPath = [string]::Join([System.IO.Path]::PathSeparator, @($byteBuddy, $burpJarPath))

Write-Step "Using Java: $java"
Write-Step "Using javac: $javac"
Write-Step "Using jar: $jar"
Write-Step "Using Burp JAR for compile-time symbols: $burpJarPath"
Write-Step "Using Byte Buddy: $byteBuddy"

Remove-Item -Path (Join-Path $buildDir "*") -Recurse -Force -ErrorAction SilentlyContinue

Invoke-Checked -Description "Compiling BurpLicenseObserverAgent" -FilePath $javac -Arguments @(
    "-cp", $compileClassPath,
    "-d", $buildDir,
    $srcFile
) | Out-Null

Copy-Item -LiteralPath $byteBuddy -Destination $distByteBuddy -Force

Invoke-Checked -Description "Packaging observer Java agent" -FilePath $jar -Arguments @(
    "cfm",
    $agentJar,
    $manifest,
    "-C",
    $buildDir,
    "."
) | Out-Null

$builtAgent = Get-Item -LiteralPath $agentJar
if ($builtAgent.Length -lt 1KB) {
    throw "Built agent JAR is unexpectedly small: $($builtAgent.Length) bytes at $agentJar"
}

if (-not $NoSmokeTest) {
    Remove-Item -LiteralPath $testLog -Force -ErrorAction SilentlyContinue
    Invoke-Checked -Description "Smoke testing observer premain" -FilePath $java -Arguments @(
        "-Dnet.bytebuddy.experimental=true",
        "-Dburp.observer.log=$testLog",
        "-javaagent:$agentJar",
        "-version"
    ) | Out-Null

    if (-not (Test-Path -LiteralPath $testLog)) {
        throw "Smoke test did not create the observer log: $testLog"
    }

    $smokeLog = Get-Content -LiteralPath $testLog -Raw
    if ($smokeLog -notmatch "agent\.premain") {
        throw "Smoke test log did not contain agent.premain: $testLog"
    }
}

Write-Host ""
Write-Host "Built observer agent:" -ForegroundColor Green
Get-ChildItem -LiteralPath $distDir | Select-Object Name, Length, LastWriteTime

if (-not $NoSmokeTest) {
    Write-Host ""
    Write-Host "Smoke-test log:" -ForegroundColor Green
    Get-Content -LiteralPath $testLog
}