param(
  [Parameter(Mandatory=$true)][string]$Worktree,
  [Parameter(Mandatory=$true)][string]$BaseSha,
  [Parameter(Mandatory=$true)][string]$HeadSha,
  [Parameter(Mandatory=$true)][int]$PullRequest,
  [Parameter(Mandatory=$true)][string[]]$Tests,
  [Parameter(Mandatory=$true)][string]$ReceiptPath
)

$ErrorActionPreference = "Stop"
$MachineIdentity = "EC2AMAZ-SPAE2VG"

function Invoke-Native([string]$File,[string[]]$CommandArgs) {
  $output = & $File @CommandArgs 2>&1 | Out-String
  $code = $LASTEXITCODE
  [pscustomobject]@{ Output=$output.Trim(); ExitCode=$code }
}

function Get-Sha256([string]$Text) {
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes=[System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes)|ForEach-Object{$_.ToString("x2")}) -join "")
  } finally { $sha.Dispose() }
}

$results=[System.Collections.Generic.List[object]]::new()
$head=Invoke-Native "git" @("-C",$Worktree,"rev-parse","HEAD")
if ($head.ExitCode -ne 0 -or $head.Output -ne $HeadSha) { throw "ARTEMIS_HEAD_MISMATCH" }
$results.Add([pscustomobject]@{name="exact_head";pass=$true;detail=$HeadSha})

$status=Invoke-Native "git" @("-C",$Worktree,"status","--porcelain=v1")
if ($status.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($status.Output)) { throw "ARTEMIS_WORKTREE_NOT_CLEAN" }
$results.Add([pscustomobject]@{name="clean_worktree";pass=$true;detail="clean"})

$ancestor=Invoke-Native "git" @("-C",$Worktree,"merge-base","--is-ancestor",$BaseSha,$HeadSha)
if ($ancestor.ExitCode -ne 0) { throw "ARTEMIS_BASE_NOT_ANCESTOR" }
$results.Add([pscustomobject]@{name="base_ancestry";pass=$true;detail=$BaseSha})

$diffCheck=Invoke-Native "git" @("-C",$Worktree,"diff","--check","$BaseSha..$HeadSha")
if ($diffCheck.ExitCode -ne 0) { throw "ARTEMIS_DIFF_CHECK_FAILED" }
$results.Add([pscustomobject]@{name="git_diff_check";pass=$true;detail="pass"})

$diff=Invoke-Native "git" @("-C",$Worktree,"diff","--binary","$BaseSha..$HeadSha")
if ($diff.ExitCode -ne 0) { throw "ARTEMIS_DIFF_READ_FAILED" }
$diffSha=Get-Sha256 $diff.Output

$changed=Invoke-Native "git" @("-C",$Worktree,"diff","--name-only","$BaseSha..$HeadSha")
if ($changed.ExitCode -ne 0) { throw "ARTEMIS_CHANGED_FILES_FAILED" }
$changedFiles=@($changed.Output -split "\r?\n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$allOutput=[System.Text.StringBuilder]::new()
Push-Location $Worktree
try {
  foreach ($testPath in $Tests) {
    if (!(Test-Path $testPath -PathType Leaf)) { throw "ARTEMIS_TEST_PATH_MISSING:$testPath" }
    $run=Invoke-Native "node" @("--test",$testPath)
    [void]$allOutput.AppendLine("TEST=$testPath")
    [void]$allOutput.AppendLine($run.Output)
    if ($run.ExitCode -ne 0) { throw "ARTEMIS_TEST_FAILED:$testPath" }
    $results.Add([pscustomobject]@{name="node_test";pass=$true;detail=$testPath})
  }

  $changedJs=@($changedFiles | Where-Object { $_ -match '\.js$' -and $_ -notmatch '^test/' })
  foreach ($relative in $changedJs) {
    $syntax=Invoke-Native "node" @("--check",$relative)
    [void]$allOutput.AppendLine("SYNTAX=$relative")
    [void]$allOutput.AppendLine($syntax.Output)
    if ($syntax.ExitCode -ne 0) { throw "ARTEMIS_SYNTAX_FAILED:$relative" }
    $results.Add([pscustomobject]@{name="node_syntax";pass=$true;detail=$relative})
  }
} finally {
  Pop-Location
}

$deviceName = if ([string]::IsNullOrWhiteSpace($env:COMPUTERNAME)) { $MachineIdentity } else { $env:COMPUTERNAME }
$receipt=[ordered]@{
  schemaVersion=1
  reviewKind="artemis_rdp_machine"
  reviewer="ARTEMIS-RDP"
  deviceName=$deviceName
  machineIdentity=$MachineIdentity
  pullRequest=$PullRequest
  baseSha=$BaseSha
  headSha=$HeadSha
  decision="PASS"
  reviewedAt=[DateTime]::UtcNow.ToString("o")
  diffSha256=$diffSha
  stdoutSha256=Get-Sha256 $allOutput.ToString()
  changedFiles=$changedFiles
  tests=$results
  sourceMutationPerformed=$false
  releaseMutationPerformed=$false
}
$json=$receipt | ConvertTo-Json -Depth 10
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ReceiptPath) | Out-Null
Set-Content -Path $ReceiptPath -Value $json -Encoding UTF8
Write-Output $json
