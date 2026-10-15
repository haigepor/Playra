param([int]$Port = 8931, [switch]$Build, [switch]$NoOpen,
  [int]$RuntimePort = 8945, [int]$BangumiEchPort = 8946)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  . (Join-Path $PSScriptRoot 'use-dev-env.ps1')
}
$flutter = if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  Join-Path $env:PLAYRA_FLUTTER_HOME 'bin\flutter.bat'
} else { Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat' }
$savedRuntimePort = $env:PLAYRA_SOURCE_RUNTIME_PORT
$savedEchPort = $env:PLAYRA_BANGUMI_ECH_PORT
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
  $logs = Join-Path $projectRoot '.dart_tool\web-service'
  New-Item -ItemType Directory -Path $logs -Force | Out-Null
  $env:KAZUMI_WEB_PORT = "$Port"
  function Ensure-LocalService($ServicePort, $HealthPath, $ServiceName, $Executable, $Arguments, $LogName) {
    if ($ServicePort -lt 1 -or $ServicePort -gt 65535) { throw '服务端口须为 1–65535' }
    $healthUrl = "http://127.0.0.1:$ServicePort/$HealthPath"
    $health = $null
    try { $health = Invoke-RestMethod $healthUrl -TimeoutSec 2 } catch {}
    if ($health -and $health.service -ne $ServiceName) { throw "端口 $ServicePort 已被其他服务占用" }
    if ($health.service -eq $ServiceName) { return }
    $process = Start-Process -FilePath $Executable -ArgumentList $Arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $logs "$LogName.log") -RedirectStandardError (Join-Path $logs "$LogName-error.log")
    [IO.File]::WriteAllText((Join-Path $logs "$LogName.pid"), "$($process.Id)", [Text.UTF8Encoding]::new($false))
    for ($attempt = 0; $attempt -lt 100; $attempt++) {
      try { $health = Invoke-RestMethod $healthUrl -TimeoutSec 1; if ($health.service -eq $ServiceName) { return } } catch {}
      if ($process.HasExited) { break }
      Start-Sleep -Milliseconds 300
    }
    throw "服务 $ServiceName 启动失败，请检查 $logs"
  }
  if ($RuntimePort) {
    if (-not (Test-Path 'tool/source_runtime/vendor/anifive/client.py')) {
      throw '请先用 tool/source_runtime/import_anifive.py 导入四源 SDK，详见四源接入文档。'
    }
    $python = if ($env:PLAYRA_BUILD_PYTHON) { $env:PLAYRA_BUILD_PYTHON } else { (Get-Command python.exe).Source }
    Ensure-LocalService $RuntimePort 'v1/health' 'playra-source-runtime' $python @('-B', '-X', 'utf8', 'tool/source_runtime/server.py', '--port', "$RuntimePort") 'runtime'
    $env:PLAYRA_SOURCE_RUNTIME_PORT = "$RuntimePort"
  }
  if ($BangumiEchPort) {
    $dart = Join-Path (Split-Path $flutter -Parent) 'cache\dart-sdk\bin\dart.exe'
    Ensure-LocalService $BangumiEchPort 'health' 'playra-bangumi-ech' $dart @('run', 'tool/bangumi_web_bridge.dart', "$BangumiEchPort") 'bangumi-ech'
    $env:PLAYRA_BANGUMI_ECH_PORT = "$BangumiEchPort"
  }
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
  [Environment]::SetEnvironmentVariable('PLAYRA_BANGUMI_ECH_PORT', $(if ($null -eq $savedEchPort) { [NullString]::Value } else { $savedEchPort }), 'Process')
  [Environment]::SetEnvironmentVariable('PLAYRA_SOURCE_RUNTIME_PORT', $(if ($null -eq $savedRuntimePort) { [NullString]::Value } else { $savedRuntimePort }), 'Process')
}
