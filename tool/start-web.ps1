param([int]$Port = 8931, [switch]$Build, [switch]$NoOpen)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutter = Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat'
Push-Location -LiteralPath $projectRoot
try {
  if ($Build -or -not (Test-Path -LiteralPath 'build\web\index.html')) {
    & $flutter build web --no-wasm-dry-run
    if ($LASTEXITCODE -ne 0) { throw 'Web build failed' }
  }
  if (-not (Test-Path -LiteralPath 'tool\web_backend\node_modules\playwright')) {
    & npm.cmd ci --prefix tool/web_backend --ignore-scripts --no-audit
    if ($LASTEXITCODE -ne 0) { throw 'Web service dependencies failed' }
  }
  $env:KAZUMI_WEB_PORT = "$Port"
  $logs = Join-Path $projectRoot '.dart_tool\web-service'
  New-Item -ItemType Directory -Path $logs -Force | Out-Null
  $url = "http://127.0.0.1:$Port"
  $running = $false
  try { $running = (Invoke-RestMethod "$url/api/health" -TimeoutSec 2).status -eq 'ok' } catch {}
  if (-not $running) {
    $service = Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList (Join-Path $projectRoot 'tool\web_backend\server.cjs') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
    [System.IO.File]::WriteAllText((Join-Path $logs 'pid.txt'), "$($service.Id)", [System.Text.UTF8Encoding]::new($false))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
      try { $running = (Invoke-RestMethod "$url/api/health" -TimeoutSec 1).status -eq 'ok'; if ($running) { break } } catch {}
      Start-Sleep -Milliseconds 200
    }
    if (-not $running) { throw "Web service failed; inspect $logs" }
  }
  Write-Host "Kazumi Web: $url"
  if (-not $NoOpen) { Start-Process $url }
} finally { Pop-Location }
