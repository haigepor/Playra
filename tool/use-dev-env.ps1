param([string]$AndroidSdk, [string]$JavaHome)

# 单独作用域避免点加载时覆盖调用脚本的局部变量；环境仅作用于当前进程。
& {
  param($ScriptDirectory, $AndroidOverride, $JavaOverride)
  $ErrorActionPreference = 'Stop'
  $root = [IO.Path]::GetFullPath((Join-Path $ScriptDirectory '..'))
  $configPath = Join-Path $root '.tooling\dev-environment.json'
  if (-not (Test-Path -LiteralPath $configPath)) {
    throw "Project dependency environment is unavailable: $configPath"
  }
  $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($config.schemaVersion -ne 1) { throw 'Unsupported project environment schema' }
  function Resolve-ProjectPath([string]$Value) {
    if (-not $Value) { throw 'A required dependency path is empty' }
    # 仓库内工具写相对路径；共享 SDK 允许按设备配置绝对路径。
    $path = if ([IO.Path]::IsPathRooted($Value)) { $Value } else { Join-Path $root $Value }
    return [IO.Path]::GetFullPath($path)
  }
  $android = Resolve-ProjectPath $(if ($AndroidOverride) { $AndroidOverride } else { $config.androidSdk })
  $java = Resolve-ProjectPath $(if ($JavaOverride) { $JavaOverride } else { $config.javaHome })
  $flutterHome = Resolve-ProjectPath $(if ($config.flutterHome) { $config.flutterHome } else { '.tooling\flutter' })
  $flutter = Join-Path $flutterHome 'bin'
  $python = Resolve-ProjectPath $config.python
  $node = Resolve-ProjectPath $config.nodeHome
  foreach ($file in @((Join-Path $flutter 'flutter.bat'), $python,
    (Join-Path $node 'node.exe'), (Join-Path $java 'bin\java.exe'),
    (Join-Path $android 'platform-tools\adb.exe'),
    (Join-Path $android 'cmake\3.22.1\bin\cmake.exe'))) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
      throw "Project dependency is missing: $file"
    }
  }
  $directories = @{
    PUB_CACHE = '.tooling\pub-cache'
    GRADLE_USER_HOME = '.tooling\gradle'
    PLAYWRIGHT_BROWSERS_PATH = '.tooling\playwright-browsers'
    npm_config_cache = '.tooling\npm-cache'
    npm_config_prefix = '.tooling\npm-global'
    PIP_CACHE_DIR = '.tooling\pip-cache'
    UV_CACHE_DIR = '.tooling\uv-cache'
    UV_PYTHON_INSTALL_DIR = '.tooling\python'
    ANDROID_USER_HOME = '.tooling\android-user'
    TEMP = '.tooling\temp'
    TMP = '.tooling\temp'
  }
  foreach ($name in $directories.Keys) {
    $directory = Join-Path $root $directories[$name]
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    [Environment]::SetEnvironmentVariable($name, $directory, 'Process')
  }
  # 既有骨架屏预览测试会直接写入此忽略目录，首次检出需要先准备父目录。
  New-Item -ItemType Directory -Path (Join-Path $root '.dart_tool\content-skeleton-before-20261012') -Force | Out-Null
  $env:ANDROID_HOME = [IO.Path]::GetFullPath($android)
  $env:ANDROID_SDK_ROOT = $env:ANDROID_HOME
  $env:JAVA_HOME = [IO.Path]::GetFullPath($java)
  $env:PLAYRA_BUILD_PYTHON = [IO.Path]::GetFullPath($python)
  $env:PLAYRA_FLUTTER_HOME = $flutterHome
  $env:PYTHONUTF8 = '1'
  $env:PYTHONDONTWRITEBYTECODE = '1'
  # 此环境面向 Web/Android，避免生成无关桌面插件的符号链接。
  $env:FLUTTER_WINDOWS = 'false'
  $env:FLUTTER_LINUX = 'false'
  if ($config.browserExecutable) {
    $browser = Resolve-ProjectPath $config.browserExecutable
  } else {
    $browserCatalog = Join-Path $root 'tool\web_backend\node_modules\playwright-core\browsers.json'
    $browser = $null
    if (Test-Path -LiteralPath $browserCatalog) {
      $chromium = (Get-Content -LiteralPath $browserCatalog -Raw -Encoding UTF8 | ConvertFrom-Json).browsers |
        Where-Object { $_.name -eq 'chromium' } | Select-Object -First 1
      $browser = Join-Path $env:PLAYWRIGHT_BROWSERS_PATH "chromium-$($chromium.revision)\chrome-win64\chrome.exe"
    }
  }
  if ($browser -and (Test-Path -LiteralPath $browser)) {
    $env:KAZUMI_CHROME = $browser
    $env:CHROME_EXECUTABLE = $browser
  }
  $prepend = @((Join-Path $root '.tooling\bin'), $flutter,
    (Split-Path -Parent $python), (Join-Path (Split-Path -Parent $python) 'Scripts'),
    $node, (Join-Path $root '.tooling\uv'), (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'),
    (Join-Path $env:ANDROID_HOME 'cmake\3.22.1\bin'))
  $env:Path = (@($prepend) + @($env:Path -split ';' | Where-Object {
    $_ -and $prepend -notcontains $_
  })) -join ';'
} $PSScriptRoot $AndroidSdk $JavaHome
