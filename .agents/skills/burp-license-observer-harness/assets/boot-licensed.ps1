<#
.SYNOPSIS
  Boot Burp Suite Professional with the license observer agent attached and the
  synthetic-license injection enabled, so startup completes under instrumentation.

  Authorised, educational, defensive reverse-engineering only. See files\how-to.md
  and licensing-flow.md for scope. With -Observe the synthetic injection is OFF
  and the agent behaves as a pure observer.

.DESCRIPTION
  Equivalent one-liner (synthetic license ON):

    & "C:\InfoSec\BurpSuite\App\jre\bin\java.exe" `
      -Xmx2g -Dnet.bytebuddy.experimental=true `
      -Dburp.observer.log="<repo>\files\burp-license-observer.log" `
      -Dburp.observer.synthlicense=true `
      --enable-native-access=ALL-UNNAMED `
      --add-opens=java.base/java.lang=ALL-UNNAMED `
      --add-opens=java.desktop/javax.swing=ALL-UNNAMED `
      --add-opens=java.desktop/java.awt=ALL-UNNAMED `
      --add-opens=java.desktop/java.awt.color=ALL-UNNAMED `
      --add-opens=java.base/javax.crypto=ALL-UNNAMED `
      --add-opens=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED `
      -javaagent:"<repo>\files\agent\dist\burp-license-observer-agent.jar" `
      -jar "C:\InfoSec\BurpSuite\App\burpsuite_pro.jar"

.PARAMETER Observe
  Disable synthetic-license injection (pure observation). Boot will hit the
  Zvoa hard-stop, as in the baseline.

.PARAMETER Tail
  After launch, wait briefly and print the tail of the observer log.

.EXAMPLE
  .\boot-licensed.ps1
  .\boot-licensed.ps1 -Tail
  .\boot-licensed.ps1 -Observe -Tail
#>
[CmdletBinding()]
param(
    [string]$Java = "C:\InfoSec\BurpSuite\App\jre\bin\java.exe",
    [string]$BurpJar = "C:\InfoSec\BurpSuite\App\burpsuite_pro.jar",
    [switch]$Observe,
    [switch]$Tail
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    (Get-Location).Path
} else {
    $PSScriptRoot
}

$filesRoot = Join-Path $scriptRoot "files"
$agent  = Join-Path $filesRoot "agent\dist\burp-license-observer-agent.jar"
$log    = Join-Path $filesRoot "burp-license-observer.log"
$stdout = Join-Path $filesRoot "burp-license-observer.stdout.log"
$stderr = Join-Path $filesRoot "burp-license-observer.stderr.log"

foreach ($required in @($Java, $BurpJar, $agent)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Required file not found: $required. Build the agent first with .\build-agent.ps1."
    }
}

Remove-Item $log, $stdout, $stderr -Force -ErrorAction SilentlyContinue

$synth = if ($Observe) { "false" } else { "true" }

$javaArgs = @(
    "-Xmx2g",
    "-Dnet.bytebuddy.experimental=true",
    "-Dburp.observer.log=$log",
    "-Dburp.observer.synthlicense=$synth",
    "--enable-native-access=ALL-UNNAMED",
    "--add-opens=java.base/java.lang=ALL-UNNAMED",
    "--add-opens=java.desktop/javax.swing=ALL-UNNAMED",
    "--add-opens=java.desktop/java.awt=ALL-UNNAMED",
    "--add-opens=java.desktop/java.awt.color=ALL-UNNAMED",
    "--add-opens=java.base/javax.crypto=ALL-UNNAMED",
    "--add-opens=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED",
    "-javaagent:$agent",
    "-jar", $BurpJar
)

Write-Host "[*] synthetic-license injection: $synth" -ForegroundColor Cyan
Write-Host "[*] observer log: $log" -ForegroundColor Cyan

$proc = Start-Process -FilePath $Java -ArgumentList $javaArgs `
    -WorkingDirectory "C:\InfoSec\BurpSuite\App" `
    -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru

Write-Host "[*] Started Burp PID: $($proc.Id)" -ForegroundColor Green
Write-Host "    Stop later with:  Stop-Process -Id $($proc.Id)" -ForegroundColor DarkGray

if ($Tail) {
    Start-Sleep -Seconds 12
    Write-Host "`n[*] observer log tail:" -ForegroundColor Cyan
    Get-Content $log -Tail 40 -ErrorAction SilentlyContinue
}
