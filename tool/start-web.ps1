param([int]$Port = 8931, [switch]$Build, [switch]$NoOpen)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  . (Join-Path $PSScriptRoot 'use-dev-env.ps1')
}
$flutter = if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  Join-Path $env:PLAYRA_FLUTTER_HOME 'bin\flutter.bat'
} else { Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat' }
Push-Location -LiteralPath $projectRoot
try {
  if ($Build) {
    & $flutter build web --release --no-wasm-dry-run --no-web-resources-cdn
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
    $url = "http://127.0.0.1:$Port"
    Write-Host "Playra Web: $url"
    if (-not $NoOpen) { Start-Process $url }
    & python -m http.server $Port --directory build/web
  } else {
    & $flutter run -d chrome --web-port $Port
  }
} finally {
  Pop-Location
}
