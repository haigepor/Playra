param([int]$Port = 8932, [switch]$Build, [switch]$NoOpen)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Push-Location -LiteralPath $projectRoot
try {
  if ($Build -or -not (Test-Path -LiteralPath 'build\shadcn-preview\index.html')) {
    & '.\.tooling\flutter\bin\flutter.bat' build web --target lib/main_shadcn_preview.dart --output build/shadcn-preview --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'Component gallery build failed' }
  }
  $env:SHADCN_PREVIEW_PORT = "$Port"
  $url = "http://127.0.0.1:$Port"
  $running = $false
  try { $running = (Invoke-WebRequest $url -TimeoutSec 2).StatusCode -eq 200 } catch {}
  if (-not $running) {
    $logs = Join-Path $projectRoot '.dart_tool\shadcn-preview'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    $service = Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList (Join-Path $projectRoot 'tool\shadcn-preview-server.cjs') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
    [IO.File]::WriteAllText((Join-Path $logs 'pid.txt'), "$($service.Id)", [Text.UTF8Encoding]::new($false))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
      try { $running = (Invoke-WebRequest $url -TimeoutSec 1).StatusCode -eq 200; if ($running) { break } } catch {}
      Start-Sleep -Milliseconds 200
    }
    if (-not $running) { throw "Component gallery server failed; inspect $logs" }
  }
  Write-Host "Shadcn gallery: $url"
  if (-not $NoOpen) { Start-Process $url }
} finally { Pop-Location }
