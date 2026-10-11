param(
  [switch]$Release,
  [string]$Device,
  [string]$AndroidSdk = $env:ANDROID_HOME,
  [string]$JavaHome = $env:JAVA_HOME
)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutter = Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat'
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
try {
  $env:ANDROID_HOME = [IO.Path]::GetFullPath($AndroidSdk)
  $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
  $env:JAVA_HOME = [IO.Path]::GetFullPath($JavaHome)
  $env:Path = "$env:JAVA_HOME\bin;$projectRoot\.tooling\flutter\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
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
  if ($Device) { & $flutter run -d $Device }
  elseif ($Release) { & $flutter build apk --release }
  else { & $flutter build apk --debug }
  if ($LASTEXITCODE -ne 0) { throw 'Android build or run failed' }
} finally {
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
