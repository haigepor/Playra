param([switch]$Release, [string]$Device)
$ErrorActionPreference = 'Stop'
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$flutter = Join-Path $projectRoot '.tooling\flutter\bin\flutter.bat'
$env:ANDROID_HOME = 'C:\Android\Sdk'
$env:JAVA_HOME = 'C:\Program Files\Eclipse Adoptium\jdk-21.0.10.7-hotspot'
$env:Path = "$env:JAVA_HOME\bin;$projectRoot\.tooling\flutter\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
$env:NO_PROXY = 'localhost,127.0.0.1,::1'
Push-Location -LiteralPath $projectRoot
try {
  if ($Device) { & $flutter run -d $Device }
  elseif ($Release) { & $flutter build apk --release }
  else { & $flutter build apk --debug }
  if ($LASTEXITCODE -ne 0) { throw 'Android build or run failed' }
} finally { Pop-Location }
