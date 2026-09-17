param(
  [Parameter(Mandatory = $true)][string]$Repo
)

$ErrorActionPreference = 'Stop'
Set-Location $Repo

$head = (git rev-parse HEAD).Trim()
$parent = (git rev-parse HEAD^ 2>$null).Trim()
if (-not $parent) {
  Write-Host "PANDORA_FAST_GATE_OK head=$head reason=no-parent"
  exit 0
}

$changed = @(git diff-tree --no-commit-id --name-only -r $parent $head) | Where-Object { $_ }
Write-Host "Pandora fast gate: $($changed.Count) changed path(s)"

git diff --check $parent $head
if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed' }

$mobile = @($changed | Where-Object { $_ -like 'apps/pandora-mobile/*' })
$worker = @($changed | Where-Object { $_ -like 'workers/windows/*' -or $_ -like 'workers/pandora-builder/*' })
$supabase = @($changed | Where-Object { $_ -like 'supabase/*' -or $_ -like 'scripts/check-supabase-*' -or $_ -like 'scripts/verify-supabase-*' })
$node = @($changed | Where-Object { $_ -like 'src/*' -or $_ -like 'packages/*' -or $_ -like 'test/*' -or $_ -like 'workers/*' -or $_ -eq 'package.json' -or $_ -eq 'package-lock.json' -or $_ -like 'tsconfig*' })

if ($mobile.Count -gt 0) {
  Push-Location (Join-Path $Repo 'apps/pandora-mobile')
  try {
    & flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze gate failed' }
    $changedTests = @($changed | Where-Object { $_ -like 'apps/pandora-mobile/test/*_test.dart' } | ForEach-Object { $_.Substring('apps/pandora-mobile/'.Length) })
    if ($changedTests.Count -gt 0) {
      & flutter test @changedTests
      if ($LASTEXITCODE -ne 0) { throw 'focused flutter test gate failed' }
    }
  } finally {
    Pop-Location
  }
}

if ($worker.Count -gt 0) {
  & npm run test:worker
  if ($LASTEXITCODE -ne 0) { throw 'worker test gate failed' }
}

if ($supabase.Count -gt 0) {
  & node scripts/check-supabase-syntax.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Supabase syntax gate failed' }
  & node scripts/verify-supabase-hardening.mjs
  if ($LASTEXITCODE -ne 0) { throw 'Supabase hardening gate failed' }
}

if ($node.Count -gt 0) {
  & npx tsc -p tsconfig.json --noEmit
  if ($LASTEXITCODE -ne 0) { throw 'TypeScript gate failed' }
  $changedNodeTests = @($changed | Where-Object { $_ -like 'test/*.test.js' -and (Test-Path (Join-Path $Repo $_)) })
  if ($changedNodeTests.Count -gt 0) {
    & node --test @changedNodeTests
    if ($LASTEXITCODE -ne 0) { throw 'focused Node test gate failed' }
  }
}

Write-Host "PANDORA_FAST_GATE_OK head=$head"
