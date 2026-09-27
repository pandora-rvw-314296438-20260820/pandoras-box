param(
  [string]$Endpoint = "https://mcpmaster.vercel.app/api/operations-rdp-worker",
  [string]$TokenFile = "C:\ProgramData\Pandora\OperationsRdpWorker\token.txt",
  [int]$PollSeconds = 20
)

$ErrorActionPreference = "Stop"
$WorkerRoot = Split-Path -Parent $TokenFile
$LogFile = Join-Path $WorkerRoot "worker.log"

function Write-WorkerLog([string]$Message) {
  $line = "{0:o} {1}" -f (Get-Date).ToUniversalTime(), $Message
  Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

function Get-Sha256Hex([string]$Text) {
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    return (($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally { $sha.Dispose() }
}

function Invoke-RdpApi([hashtable]$Payload) {
  $token = (Get-Content -Path $TokenFile -Raw).Trim()
  if ([string]::IsNullOrWhiteSpace($token)) { throw "RDP worker token missing" }
  $body = $Payload | ConvertTo-Json -Depth 12 -Compress
  $issuedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $nonce = [guid]::NewGuid().ToString()
  $bodySha = Get-Sha256Hex $body
  $basis = "{0}`n{1}`n{2}" -f $issuedAt,$nonce,$bodySha
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  try {
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($token)
    $sig = (($hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($basis)) |
      ForEach-Object { $_.ToString("x2") }) -join "")
  } finally { $hmac.Dispose() }
  $headers = @{
    Authorization = "Bearer $token"
    "x-pandora-issued-at" = [string]$issuedAt
    "x-pandora-nonce" = $nonce
    "x-pandora-signature" = $sig
  }
  return Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $headers `
    -ContentType "application/json" -Body $body -TimeoutSec 45
}

function Command-Text([scriptblock]$Command) {
  $priorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    $output = & $Command 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "Native command failed with exit code $exitCode" }
    return ($output | Out-String).Trim()
  } finally {
    $ErrorActionPreference = $priorPreference
  }
}

function Invoke-LoggedNative([string]$Name,[scriptblock]$Command,[string]$LogPath) {
  $priorPreference = $ErrorActionPreference
  try {
    $ErrorActionPreference = "Continue"
    & $Command *> $LogPath
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) { throw "$Name failed with exit code $exitCode" }
    if (!(Test-Path $LogPath)) { throw "$Name evidence log missing" }
    return (Get-FileHash -Algorithm SHA256 $LogPath).Hash.ToLower()
  } finally {
    $ErrorActionPreference = $priorPreference
  }
}

function Run-Profile([string]$Profile,[string]$SourceSha,[string]$Repository,[string]$TaskId) {
  $parts = New-Object System.Collections.Generic.List[string]
  $tests = New-Object System.Collections.Generic.List[string]
  $exitCode = 0
  try {
    if ($Profile -in @("canary_v1","toolchain_verify")) {
      $node = Command-Text { node --version }
      $python = Command-Text { python --version }
      $java = Command-Text { java -version }
      $flutter = Command-Text { flutter --version }
      $adb = Command-Text { adb version }
      foreach ($pair in @(
        @{Name="Node";Value=$node}, @{Name="Python";Value=$python},
        @{Name="Java";Value=$java}, @{Name="Flutter";Value=$flutter}, @{Name="ADB";Value=$adb}
      )) {
        if ([string]::IsNullOrWhiteSpace([string]$pair.Value)) { throw "$($pair.Name) unavailable" }
        $parts.Add("$($pair.Name)=$($pair.Value)")
        $tests.Add("$($pair.Name) toolchain executable PASS")
      }
    }

    if ($Profile -in @("canary_v1","github_runner_verify")) {
      $task = Get-ScheduledTask -TaskName "Pandora GitHub Runner" -ErrorAction Stop
      $runner = Get-Content "C:\Pandora\actions-runner\.runner" -Raw | ConvertFrom-Json
      if ($runner.gitHubUrl -ne "https://github.com/pandora-rvw-314296438-20260820/pandoras-box") {
        throw "GitHub runner repository mismatch"
      }
      $parts.Add("RunnerState=$($task.State);RunnerName=$($runner.agentName)")
      $tests.Add("Canonical GitHub self-hosted runner binding PASS")
    }

    if ($Profile -eq "android_verify") {
      $adbVersion = Command-Text { adb version }
      $devices = Command-Text { adb devices -l }
      $parts.Add("ADB=$adbVersion`nDEVICES=$devices")
      $tests.Add("Android platform tools execution PASS")
    }

    if ($Profile -eq "flutter_verify") {
      $version = Command-Text { flutter --version }
      $doctor = Command-Text { flutter doctor -v }
      $parts.Add("FLUTTER=$version`nDOCTOR=$doctor")
      $tests.Add("Flutter toolchain execution PASS")
    }

    if ($Profile -in @("repo_test","repo_build")) {
      if ($Repository -ne "pandora-rvw-314296438-20260820/pandoras-box") { throw "Repository authority mismatch" }
      if ($SourceSha -notmatch '^[a-f0-9]{40}$') { throw "Source SHA invalid" }
      if ([string]::IsNullOrWhiteSpace($TaskId)) { throw "Task identity missing" }
      $jobKey = (Get-Sha256Hex $TaskId).Substring(0,24)
      $jobRoot = Join-Path $WorkerRoot ("jobs\" + $jobKey)
      Remove-Item $jobRoot -Recurse -Force -ErrorAction SilentlyContinue
      New-Item -ItemType Directory -Path $jobRoot -Force | Out-Null

      Command-Text { git -C $jobRoot init }
      Command-Text { git -C $jobRoot remote add origin "https://github.com/pandora-rvw-314296438-20260820/pandoras-box.git" }
      $fetchLog = Join-Path $jobRoot "fetch.log"
      $fetchHash = Invoke-LoggedNative "git fetch" { git -C $jobRoot fetch --no-tags origin main } $fetchLog
      Command-Text { git -C $jobRoot cat-file -e ($SourceSha + "^{commit}") }
      & git -C $jobRoot merge-base --is-ancestor $SourceSha FETCH_HEAD
      if ($LASTEXITCODE -ne 0) { throw "Source SHA is not an ancestor of canonical main" }
      Command-Text { git -C $jobRoot checkout --detach $SourceSha }
      $actual = (Command-Text { git -C $jobRoot rev-parse HEAD }).Trim()
      if ($actual -ne $SourceSha) { throw "Exact source checkout mismatch" }
      $parts.Add("SOURCE=$actual;FETCH_SHA256=$fetchHash")
      $tests.Add("Exact source SHA is an ancestor of canonical main PASS")

      $installLog = Join-Path $jobRoot "npm-ci.log"
      $installHash = Invoke-LoggedNative "npm ci" { npm.cmd --prefix $jobRoot ci --ignore-scripts --no-audit --no-fund } $installLog
      $parts.Add("NPM_CI_SHA256=$installHash")

      if ($Profile -eq "repo_test") {
        $runLog = Join-Path $jobRoot "npm-test.log"
        $runHash = Invoke-LoggedNative "npm test" { npm.cmd --prefix $jobRoot test } $runLog
        $parts.Add("NPM_TEST_SHA256=$runHash")
        $tests.Add("Canonical repository test suite execution PASS")
      } else {
        $runLog = Join-Path $jobRoot "npm-build.log"
        $runHash = Invoke-LoggedNative "npm build" { npm.cmd --prefix $jobRoot run build } $runLog
        $parts.Add("NPM_BUILD_SHA256=$runHash")
        $tests.Add("Canonical repository build execution PASS")
      }
      $tests.Add("Repository execution remained detached and non-publishing PASS")
    }

    if ($tests.Count -eq 0) { throw "Unsupported RDP profile" }
  } catch {
    $exitCode = 1
    $parts.Add("ERROR=$($_.Exception.GetType().Name)")
    $tests.Add("RDP profile execution FAIL")
  }

  $stdout = $parts -join "`n---`n"
  return @{ exitCode=$exitCode; stdoutSha256=(Get-Sha256Hex $stdout); tests=@($tests) }
}

New-Item -ItemType Directory -Path $WorkerRoot -Force | Out-Null
Write-WorkerLog "worker_loop_started"

while ($true) {
  try {
    $poll = Invoke-RdpApi @{ action = "poll" }
    if ($poll.state -eq "offered" -and $poll.offer) {
      $offer = $poll.offer
      $accepted = Invoke-RdpApi @{
        action = "accept"; taskId = [string]$offer.taskId; leaseId = [string]$offer.leaseId;
        dispatchId = [string]$offer.dispatchId; generation = [int]$offer.generation
      }
      $profile = [string]$accepted.profile
      Write-WorkerLog ("task_started " + [string]$offer.taskId + " profile=" + $profile)
      $sourceSha = [string]$offer.sourceSha
      $repository = [string]$offer.repository
      $result = Run-Profile $profile $sourceSha $repository ([string]$offer.taskId)
      if ([int]$result.exitCode -ne 0) {
        Invoke-RdpApi @{
          action="fail"; taskId=[string]$offer.taskId; leaseId=[string]$offer.leaseId;
          dispatchId=[string]$offer.dispatchId; generation=[int]$offer.generation
        } | Out-Null
        Write-WorkerLog ("task_failed " + [string]$offer.taskId)
      } else {
        $proofBasis = "{0}:{1}:{2}:{3}:{4}:{5}" -f `
          $offer.dispatchId,$offer.taskId,$offer.generation,$profile,$result.exitCode,$result.stdoutSha256
        $proof = Get-Sha256Hex $proofBasis
        Invoke-RdpApi @{
          action="complete"; taskId=[string]$offer.taskId; leaseId=[string]$offer.leaseId;
          dispatchId=[string]$offer.dispatchId; generation=[int]$offer.generation;
          evidence=@{ profile=$profile; exitCode=[int]$result.exitCode;
            stdoutSha256=[string]$result.stdoutSha256; proofSha256=$proof; tests=@($result.tests) }
        } | Out-Null
        Write-WorkerLog ("task_handed_off " + [string]$offer.taskId)
      }
    }
  } catch {
    Write-WorkerLog ("loop_error " + $_.Exception.GetType().Name)
  }
  Start-Sleep -Seconds ([Math]::Max(10,$PollSeconds))
}
