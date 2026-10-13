param(
  [switch]$Release,
  [string]$Device,
  [string]$AndroidSdk = $env:ANDROID_HOME,
  [string]$JavaHome = $env:JAVA_HOME,
  [string]$DartDefineFromFile,
  [string]$RuntimeUrl,
  [switch]$RuntimeAllowHttp
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  . (Join-Path $PSScriptRoot 'use-dev-env.ps1') -AndroidSdk $AndroidSdk -JavaHome $JavaHome
  if (-not $AndroidSdk) { $AndroidSdk = $env:ANDROID_HOME }
  if (-not $JavaHome) { $JavaHome = $env:JAVA_HOME }
}
$flutter = if (Test-Path -LiteralPath (Join-Path $projectRoot '.tooling\dev-environment.json')) {
  Join-Path $env:PLAYRA_FLUTTER_HOME 'bin\flutter.bat'
} else { Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat' }
if (-not $AndroidSdk) {
  $AndroidSdk = $env:ANDROID_SDK_ROOT
}
if (-not $AndroidSdk) {
  $localProperties = Join-Path $projectRoot 'android\local.properties'
  if (Test-Path -LiteralPath $localProperties) {
    $sdkProperty = Get-Content -LiteralPath $localProperties -Encoding UTF8 |
      Where-Object { $_ -match '^sdk\.dir=' } | Select-Object -First 1
    if ($sdkProperty) {
      # Gradle 的 properties 文件会转义 Windows 路径，复用本项目已检测到的 SDK。
      $AndroidSdk = $sdkProperty.Substring(8).Replace('\\', '\').Replace('\:', ':')
    }
  }
}
if (-not $AndroidSdk) {
  $AndroidSdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
}
if (-not $JavaHome) {
  $localJava = Join-Path $projectRoot '.tooling\java'
  if (Test-Path -LiteralPath $localJava) {
    $JavaHome = Get-ChildItem -LiteralPath $localJava -Directory |
      Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'bin\java.exe') } |
      Select-Object -First 1 -ExpandProperty FullName
  }
}
if (-not (Test-Path -LiteralPath $flutter)) { throw 'Install the project Flutter SDK in .tooling/flutter first' }
if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdk 'platform-tools\adb.exe'))) {
  throw 'Android SDK is unavailable; pass -AndroidSdk or set ANDROID_HOME'
}
if (-not $JavaHome -or -not (Test-Path -LiteralPath (Join-Path $JavaHome 'bin\java.exe'))) {
  throw 'JDK is unavailable; pass -JavaHome or set JAVA_HOME'
}
# 只在构建期间配置工具链，避免脚本覆盖调用终端或其他项目的环境。
$savedEnvironment = @{}
foreach ($name in 'ANDROID_HOME', 'ANDROID_SDK_ROOT', 'JAVA_HOME', 'Path', 'NO_PROXY', 'GRADLE_OPTS') {
  $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}
Push-Location -LiteralPath $projectRoot
$generatedDefines = $null
try {
  $env:ANDROID_HOME = [IO.Path]::GetFullPath($AndroidSdk)
  $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
  $env:JAVA_HOME = [IO.Path]::GetFullPath($JavaHome)
  $flutterBin = Split-Path -Parent $flutter
  $env:Path = "$env:JAVA_HOME\bin;$flutterBin;$env:ANDROID_HOME\platform-tools;$env:Path"
  $env:NO_PROXY = (@('localhost', '127.0.0.1', '::1', $savedEnvironment['NO_PROXY']) |
    Where-Object { $_ }) -join ','
  $pubCache = $env:PUB_CACHE
  if (-not $pubCache) { $pubCache = Join-Path $env:LOCALAPPDATA 'Pub\Cache' }
  if ([IO.Path]::GetPathRoot($projectRoot) -ne [IO.Path]::GetPathRoot([IO.Path]::GetFullPath($pubCache))) {
    # Kotlin 增量缓存不能计算跨盘插件路径；仅本次构建关闭，退出后恢复调用者设置。
    # Flutter/Dart 会大写 Windows 环境变量名，因此通过 JVM 属性保留 Kotlin 参数的大小写。
    $env:GRADLE_OPTS = (@($savedEnvironment['GRADLE_OPTS'], '-Dorg.gradle.project.kotlin.incremental=false') |
      Where-Object { $_ }) -join ' '
  }
  $defineArguments = @()
  if ($RuntimeUrl) {
    $runtimeUri = $null
    if (-not [Uri]::TryCreate($RuntimeUrl, [UriKind]::Absolute, [ref]$runtimeUri) -or
        $runtimeUri.Scheme -notin @('https', 'http') -or $runtimeUri.UserInfo -or
        $runtimeUri.Query -or $runtimeUri.Fragment -or
        ($runtimeUri.Scheme -eq 'http' -and -not $RuntimeAllowHttp)) {
      throw '运行地址须为 HTTPS 基址；开发 HTTP 需要 -RuntimeAllowHttp，地址不能含凭据或查询参数'
    }
    $defineArguments += "--dart-define=PLAYRA_SOURCE_RUNTIME_URL=$RuntimeUrl"
  }
  if ($RuntimeAllowHttp) {
    $defineArguments += '--dart-define=PLAYRA_SOURCE_RUNTIME_ALLOW_HTTP=true'
  }
  if ($DartDefineFromFile) {
    $definePath = (Resolve-Path -LiteralPath $DartDefineFromFile).Path
    $defineArguments += "--dart-define-from-file=$definePath"
  } else {
    # 与 CI 保持一致；使用临时文件传入，避免密钥出现在终端与进程参数中。
    $defines = @{}
    foreach ($defineName in 'KAZUMI_APPID', 'KAZUMI_KEY', 'DANDANAPI_APPID', 'DANDANAPI_KEY') {
      $defineValue = [Environment]::GetEnvironmentVariable($defineName, 'Process')
      if ($defineValue) { $defines[$defineName] = $defineValue }
    }
    if ($defines.Count -gt 0) {
      $generatedDefines = Join-Path $projectRoot ('.dart_tool/android-defines-' + [Guid]::NewGuid().ToString('N') + '.json')
      [IO.File]::WriteAllText($generatedDefines, ($defines | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
      $defineArguments += "--dart-define-from-file=$generatedDefines"
    }
  }
  if ($Device) { & $flutter run -d $Device @defineArguments }
  elseif ($Release) { & $flutter build apk --release @defineArguments }
  else { & $flutter build apk --debug @defineArguments }
  if ($LASTEXITCODE -ne 0) { throw 'Android build or run failed' }
} finally {
  if ($generatedDefines -and (Test-Path -LiteralPath $generatedDefines)) {
    Remove-Item -LiteralPath $generatedDefines -Force
  }
  Pop-Location
  foreach ($name in $savedEnvironment.Keys) {
    if ($null -eq $savedEnvironment[$name]) {
      # PowerShell 会把普通 $null 绑定为空字符串；新 .NET 需显式 null 才能移除变量。
      [Environment]::SetEnvironmentVariable($name, [NullString]::Value, 'Process')
    } else {
      [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process')
    }
  }
}
