param([int]$Port = 8933, [switch]$Build, [switch]$NoOpen)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$previewRoot = Join-Path $projectRoot 'build\modern-home-preview'
$previousPort = $env:KAZUMI_WEB_PORT
$previousRoot = $env:KAZUMI_WEB_ROOT
Push-Location -LiteralPath $projectRoot
try {
  if ($Build -or -not (Test-Path -LiteralPath (Join-Path $previewRoot 'index.html'))) {
    & '.\.tooling\flutter\bin\flutter.bat' build web --target lib/main_home_preview.dart --output build/modern-home-preview --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'Android home preview build failed' }
  }
  if (-not (Test-Path -LiteralPath 'tool\web_backend\node_modules\playwright')) {
    & npm.cmd ci --prefix tool/web_backend --ignore-scripts --no-audit
    if ($LASTEXITCODE -ne 0) { throw 'Preview service dependencies failed' }
  }
  [IO.File]::WriteAllText((Join-Path $previewRoot 'home-preview.json'), '{"preview":"android-home-v1"}', [Text.UTF8Encoding]::new($false))
  $env:KAZUMI_WEB_PORT = "$Port"
  $env:KAZUMI_WEB_ROOT = $previewRoot
  $url = "http://127.0.0.1:$Port"
  $logs = Join-Path $projectRoot '.dart_tool\modern-home-preview'
  New-Item -ItemType Directory -Path $logs -Force | Out-Null
  $running = $false
  try { $running = (Invoke-RestMethod "$url/home-preview.json" -TimeoutSec 2).preview -eq 'android-home-v1' } catch {}
  if (-not $running) {
    $service = Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList (Join-Path $projectRoot 'tool\web_backend\server.cjs') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
    [IO.File]::WriteAllText((Join-Path $logs 'pid.txt'), "$($service.Id)", [Text.UTF8Encoding]::new($false))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
      if ($service.HasExited) { throw "Preview process exited; inspect $logs" }
      try { $running = (Invoke-RestMethod "$url/home-preview.json" -TimeoutSec 1).preview -eq 'android-home-v1'; if ($running) { break } } catch {}
      Start-Sleep -Milliseconds 200
    }
    if (-not $running) { throw "Preview failed; inspect $logs" }
  }
  if ((Invoke-RestMethod "$url/api/health" -TimeoutSec 3).status -ne 'ok') { throw 'Preview API health check failed' }
  Write-Host "Android home preview: $url"
  if (-not $NoOpen) { Start-Process $url }
} finally {
  $env:KAZUMI_WEB_PORT = $previousPort
  $env:KAZUMI_WEB_ROOT = $previousRoot
  Pop-Location
}
