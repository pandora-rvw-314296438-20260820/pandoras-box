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

function Run-Profile([string]$Profile) {
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
      $result = Run-Profile $profile
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
