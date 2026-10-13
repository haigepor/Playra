param([int]$Port = 8931, [switch]$Build, [switch]$NoOpen,
  [int]$RuntimePort = 0)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  . (Join-Path $PSScriptRoot 'use-dev-env.ps1')
}
$flutter = if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  Join-Path $env:PLAYRA_FLUTTER_HOME 'bin\flutter.bat'
} else { Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat' }
$savedRuntimePort = $env:PLAYRA_SOURCE_RUNTIME_PORT
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
  if ($RuntimePort) {
    if ($RuntimePort -lt 1 -or $RuntimePort -gt 65535) { throw '算法服务端口须为 1–65535' }
    $runtimeHealth = $null
    try { $runtimeHealth = Invoke-RestMethod "http://127.0.0.1:$RuntimePort/v1/health" -TimeoutSec 2 } catch {}
    if ($runtimeHealth.service -ne 'playra-source-runtime' -or $runtimeHealth.apiVersion -ne '1') {
      throw "请先运行 Python 3.11+：py -3 -X utf8 tool/source_runtime/server.py --port $RuntimePort"
    }
    $env:PLAYRA_SOURCE_RUNTIME_PORT = "$RuntimePort"
  }
  $logs = Join-Path $projectRoot '.dart_tool\web-service'
  New-Item -ItemType Directory -Path $logs -Force | Out-Null
  $url = "http://127.0.0.1:$Port"
  $running = $false
  try { $running = (Invoke-RestMethod "$url/api/health" -TimeoutSec 2).status -eq 'ok' } catch {}
  if ($running -and $RuntimePort) {
    $runtimeReady = $false
    try { $runtimeReady = (Invoke-RestMethod "$url/api/runtime/v1/health" -TimeoutSec 2).apiVersion -eq '1' } catch {}
    if (-not $runtimeReady) { throw "当前 $Port 的 Web 服务尚未启用运行桥接，请停止该服务后按相同命令重启，或选择另一端口。" }
  }
  if (-not $running) {
    $service = Start-Process -FilePath (Get-Command node.exe).Source -ArgumentList (Join-Path $projectRoot 'tool\web_backend\server.cjs') -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs 'stdout.log') -RedirectStandardError (Join-Path $logs 'stderr.log')
    [System.IO.File]::WriteAllText((Join-Path $logs 'pid.txt'), "$($service.Id)", [System.Text.UTF8Encoding]::new($false))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
      try { $running = (Invoke-RestMethod "$url/api/health" -TimeoutSec 1).status -eq 'ok'; if ($running) { break } } catch {}
      Start-Sleep -Milliseconds 200
    }
    if (-not $running) { throw "Web service failed; inspect $logs" }
  }
  Write-Host "Playra Web: $url"
  if (-not $NoOpen) { Start-Process $url }
} finally {
  Pop-Location
  [Environment]::SetEnvironmentVariable('PLAYRA_SOURCE_RUNTIME_PORT', $(if ($null -eq $savedRuntimePort) { [NullString]::Value } else { $savedRuntimePort }), 'Process')
}
