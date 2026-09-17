[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$Manifest,
    [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{40}$')][string]$ExpectedSourceSha,
    [string]$Serial = 'emulator-5554',
    [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path,
    [string]$AndroidSdkRoot = 'C:\Android\Sdk',
    [string]$PythonLauncher = 'py'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$head = (git -C $RepoRoot rev-parse HEAD).Trim()
if ($head -ne $ExpectedSourceSha) {
    throw "Worktree HEAD $head does not match expected source $ExpectedSourceSha"
}

git -C $RepoRoot diff --quiet --
if ($LASTEXITCODE -ne 0) {
    throw 'Tracked worktree content is dirty; emulator acceptance requires exact committed source.'
}
git -C $RepoRoot diff --cached --quiet --
if ($LASTEXITCODE -ne 0) {
    throw 'Index is dirty; emulator acceptance requires exact committed source.'
}

$sourceTree = (git -C $RepoRoot rev-parse 'HEAD^{tree}').Trim()
$adb = Join-Path $AndroidSdkRoot 'platform-tools\adb.exe'
if (-not (Test-Path $adb)) {
    throw "adb.exe not found under $AndroidSdkRoot"
}

$buildTools = Get-ChildItem (Join-Path $AndroidSdkRoot 'build-tools') -Directory |
    Where-Object {
        (Test-Path (Join-Path $_.FullName 'aapt.exe')) -and
        (Test-Path (Join-Path $_.FullName 'apksigner.bat'))
    } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
if ($null -eq $buildTools) {
    throw "No Android build-tools containing aapt.exe and apksigner.bat were found under $AndroidSdkRoot"
}

$aapt = Join-Path $buildTools.FullName 'aapt.exe'
$apksigner = Join-Path $buildTools.FullName 'apksigner.bat'
$tool = Join-Path $PSScriptRoot 'verify_android_emulator_candidate.py'
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$outDir = Join-Path $RepoRoot ".pandora-mobile-emulator-evidence\$($ExpectedSourceSha.Substring(0, 12))\$stamp"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
$events = Join-Path $outDir 'events.jsonl'
$evidence = Join-Path $outDir 'acceptance.json'
$arguments = @(
    $tool,
    '--apk', (Resolve-Path $Apk).Path,
    '--manifest', (Resolve-Path $Manifest).Path,
    '--expected-source-sha', $ExpectedSourceSha,
    '--expected-source-tree', $sourceTree,
    '--serial', $Serial,
    '--aapt', $aapt,
    '--apksigner', $apksigner,
    '--adb', $adb,
    '--events-output', $events,
    '--evidence-output', $evidence
)

if ($PythonLauncher -eq 'py') {
    & py -3 @arguments
} else {
    & $PythonLauncher @arguments
}
if ($LASTEXITCODE -ne 0) {
    throw "Pandora Android emulator acceptance failed with exit code $LASTEXITCODE"
}

Write-Output "PANDORA_EMULATOR_ACCEPTANCE_EVIDENCE=$evidence"
Write-Output "PANDORA_EMULATOR_ACCEPTANCE_EVENTS=$events"
Get-Content -LiteralPath $evidence -Raw
