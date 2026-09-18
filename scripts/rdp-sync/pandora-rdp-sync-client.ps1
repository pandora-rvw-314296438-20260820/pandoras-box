param(
  [ValidateSet('probe','start','publish-head')][string]$Action = 'probe',
  [string]$Repo = 'C:\Pandora\pandoras-box',
  [string]$Branch = 'main',
  [string]$BaseSha = ''
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$Endpoint = 'https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-github-uiux-convergence-20260828'
$ProofPath = 'C:\Pandora\security\rdp-sync-machine-proof.dpapi'
$AllowedBranch = '^(chatgpt|recovery|repair|fix)/[A-Za-z0-9._/-]{1,220}$|^enterprise-ui(?:[-/][A-Za-z0-9._/-]{1,200})?$'

function Invoke-Git([string[]]$GitArgs) {
  $output = & git -C $Repo @GitArgs 2>&1
  if($LASTEXITCODE -ne 0){ throw "git failed: $($GitArgs -join ' ') :: $($output -join ' ')" }
  return $output
}

function Get-MachineProof {
  $encrypted = [IO.File]::ReadAllBytes($ProofPath)
  $raw = [Security.Cryptography.ProtectedData]::Unprotect($encrypted,$null,[Security.Cryptography.DataProtectionScope]::CurrentUser)
  try { return [Convert]::ToBase64String($raw) }
  finally { [Array]::Clear($raw,0,$raw.Length) }
}

function Invoke-PandoraSync([hashtable]$Payload) {
  $Payload.version = 1
  $Payload.timestamp = (Get-Date).ToUniversalTime().ToString('o')
  $Payload.nonce = [guid]::NewGuid().ToString()
  $proof = Get-MachineProof
  try {
    return Invoke-RestMethod -Method Post -Uri $Endpoint -Headers @{'x-pandora-machine-proof'=$proof} -ContentType 'application/json' -Body ($Payload | ConvertTo-Json -Compress -Depth 12)
  }
  finally { $proof = $null }
}

function Read-BlobBytes([string]$BlobSha) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'git.exe'
  $psi.Arguments = "-C `"$Repo`" cat-file blob $BlobSha"
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $ms = New-Object IO.MemoryStream
  $p.StandardOutput.BaseStream.CopyTo($ms)
  $err = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if($p.ExitCode -ne 0){ throw "git cat-file failed: $err" }
  try { return $ms.ToArray() } finally { $ms.Dispose(); $p.Dispose() }
}

function Get-TreeEntry([string]$Commit,[string]$Path) {
  $line = (& git -C $Repo ls-tree $Commit -- $Path 2>$null | Select-Object -First 1)
  if(-not $line){ return $null }
  if($line -notmatch '^(\d{6})\s+(\w+)\s+([0-9a-f]{40})\t'){ throw "Unsupported tree entry: $Path" }
  return @{ mode=$matches[1]; type=$matches[2]; sha=$matches[3] }
}

if($Action -eq 'probe') {
  $result = Invoke-PandoraSync @{operation='probe';branch=$Branch}
  $result | ConvertTo-Json -Compress
  exit 0
}

if($Action -eq 'start') {
  if($Branch -notmatch $AllowedBranch){ throw 'Branch is outside Pandora managed sync prefixes.' }
  if(-not $BaseSha){ $BaseSha = (Invoke-Git @('rev-parse','origin/main') | Select-Object -First 1).Trim() }
  $result = Invoke-PandoraSync @{operation='start_branch';branch=$Branch;baseSha=$BaseSha}
  $result | ConvertTo-Json -Compress
  exit 0
}

$Branch = (Invoke-Git @('symbolic-ref','--short','HEAD') | Select-Object -First 1).Trim()
if($Branch -notmatch $AllowedBranch){ Write-Host "Pandora sync skipped for unmanaged branch $Branch"; exit 0 }
$trackedDirty = Invoke-Git @('status','--porcelain','--untracked-files=no')
if($trackedDirty){ throw 'Tracked working tree is dirty after commit; refusing publication.' }
$localCommit = (Invoke-Git @('rev-parse','HEAD') | Select-Object -First 1).Trim()
$parents = ((Invoke-Git @('rev-list','--parents','-n','1',$localCommit) | Select-Object -First 1).Trim() -split '\s+')
if($parents.Count -ne 2){ throw 'Only single-parent worker commits are supported by automatic publication.' }
$parent = $parents[1]
$tree = (Invoke-Git @('rev-parse',"$localCommit^{tree}") | Select-Object -First 1).Trim()

$remote = Invoke-PandoraSync @{operation='probe';branch=$Branch}
if([int]$remote.status -eq 404){
  Invoke-PandoraSync @{operation='start_branch';branch=$Branch;baseSha=$parent} | Out-Null
  $remote = Invoke-PandoraSync @{operation='probe';branch=$Branch}
}
if([int]$remote.status -ne 200 -or [string]$remote.sha -ne $parent){ throw "Remote branch is not exactly at local parent. remote=$($remote.sha) parent=$parent" }

$paths = @(Invoke-Git @('diff-tree','--no-commit-id','--name-only','-r',$parent,$localCommit)) | Where-Object { $_ -ne '' }
if($paths.Count -lt 1){ throw 'Empty commits are not published automatically.' }
$changes = @()
foreach($path in $paths){
  $current = Get-TreeEntry $localCommit $path
  if($null -eq $current){
    $old = Get-TreeEntry $parent $path
    if($null -eq $old){ throw "Delete preimage missing: $path" }
    $changes += @{path=$path;mode=$old.mode;action='delete'}
    continue
  }
  if($current.type -ne 'blob'){ throw "Non-blob path is not supported: $path" }
  $bytes = Read-BlobBytes $current.sha
  try { $encoded = [Convert]::ToBase64String($bytes) } finally { [Array]::Clear($bytes,0,$bytes.Length) }
  $changes += @{path=$path;mode=$current.mode;action='upsert';contentBase64=$encoded}
}

$message = ((Invoke-Git @('log','-1','--format=%B',$localCommit)) -join "`n").TrimEnd("`r","`n")
$author = @{name=((Invoke-Git @('show','-s','--format=%an',$localCommit)) -join '').Trim();email=((Invoke-Git @('show','-s','--format=%ae',$localCommit)) -join '').Trim();date=((Invoke-Git @('show','-s','--format=%aI',$localCommit)) -join '').Trim()}
$committer = @{name=((Invoke-Git @('show','-s','--format=%cn',$localCommit)) -join '').Trim();email=((Invoke-Git @('show','-s','--format=%ce',$localCommit)) -join '').Trim();date=((Invoke-Git @('show','-s','--format=%cI',$localCommit)) -join '').Trim()}
$result = Invoke-PandoraSync @{operation='publish_commit';branch=$Branch;expectedParentSha=$parent;expectedTreeSha=$tree;localCommitSha=$localCommit;message=$message;author=$author;committer=$committer;changes=$changes}
if(-not $result.ok -or -not $result.exactTree){ throw 'Provider readback did not prove exact source tree.' }

$remoteSha = [string]$result.remoteSha
$backupRef = "refs/pandora-local/$Branch/$localCommit"
& git -C $Repo update-ref $backupRef $localCommit | Out-Null
if($LASTEXITCODE -ne 0){ throw 'Could not create local recovery ref.' }
if($remoteSha -eq $localCommit){
  & git -C $Repo update-ref "refs/remotes/origin/$Branch" $remoteSha | Out-Null
  git -C $Repo config "branch.$Branch.remote" origin
  git -C $Repo config "branch.$Branch.merge" "refs/heads/$Branch"
  Write-Host "PANDORA_SYNC_OK branch=$Branch sha=$remoteSha exact_commit=true exact_tree=true"
  exit 0
}

$authorTime = [DateTimeOffset]::Parse($author.date).ToUniversalTime().ToUnixTimeSeconds()
$committerTime = [DateTimeOffset]::Parse($committer.date).ToUniversalTime().ToUnixTimeSeconds()
$commitBody = "tree $tree`nparent $parent`nauthor $($author.name) <$($author.email)> $authorTime +0000`ncommitter $($committer.name) <$($committer.email)> $committerTime +0000`n`n$message"
$tmp = Join-Path $env:TEMP ("pandora-commit-object-"+[guid]::NewGuid().ToString()+'.bin')
try {
  [IO.File]::WriteAllBytes($tmp,[Text.Encoding]::UTF8.GetBytes($commitBody))
  $rebuilt = ((Invoke-Git @('hash-object','-t','commit','-w',$tmp)) | Select-Object -First 1).Trim()
} finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
if($rebuilt -ne $remoteSha){ throw "Remote source is safe but canonical commit reconstruction failed. remote=$remoteSha rebuilt=$rebuilt local=$localCommit" }
& git -C $Repo update-ref "refs/heads/$Branch" $remoteSha $localCommit | Out-Null
& git -C $Repo update-ref "refs/remotes/origin/$Branch" $remoteSha | Out-Null
git -C $Repo config "branch.$Branch.remote" origin
git -C $Repo config "branch.$Branch.merge" "refs/heads/$Branch"
Write-Host "PANDORA_SYNC_OK branch=$Branch sha=$remoteSha exact_commit=false exact_tree=true local_backup=$backupRef"
