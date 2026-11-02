param(
    [string]$Adb = 'D:/leidian/LDPlayer14/adb.exe',
    [string]$Serial = 'emulator-5554',
    [string]$Abi = '',
    [string]$Ndk = 'D:/Android/Sdk/ndk/28.2.13676358',
    [string]$Output = '.dart_tool/lumina-core-contract'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = [IO.Path]::GetFullPath((Join-Path $root $Output))
New-Item -ItemType Directory -Path $out -Force | Out-Null
$compiler = Join-Path $Ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe'
$package = Join-Path $root 'packages/lumina_engine'
$coreTestAbi = if ($Abi) { $Abi } else { (& $Adb -s $Serial shell getprop ro.product.cpu.abi).Trim() }
$target = switch ($coreTestAbi) {
    'x86_64' { 'x86_64-linux-android24' }
    'arm64-v8a' { 'aarch64-linux-android24' }
    default { throw "Unsupported test-device ABI: $coreTestAbi" }
}
& $compiler "--target=$target" -shared -fPIC -O2 -Wall -Wextra -Werror "$package/test/native/fake_core.c" -o "$out/libfake_core.so"
if ($LASTEXITCODE) { throw 'Fake supplier compilation failed' }
& $compiler "--target=$target" -fPIE -pie -O2 -Wall -Wextra -Werror -I "$package/include" "$package/src/lumina_core_shim.c" "$package/test/native/core_contract_test.c" -ldl -o "$out/core_contract_test"
if ($LASTEXITCODE) { throw 'Contract test compilation failed' }
$device = '/data/local/tmp/playra-core-contract'
& $Adb -s $Serial shell "mkdir -p $device"
& $Adb -s $Serial push "$out/libfake_core.so" "$out/core_contract_test" $device
if ($LASTEXITCODE) { throw 'Test upload failed' }
& $Adb -s $Serial shell "chmod 755 $device/core_contract_test"
$lines = @()
foreach ($case in @('normal', 'missing', 'selftest', 'late', 'blocking', 'never', 'concurrent', 'queue', 'malformed', 'padding')) {
    $result = & $Adb -s $Serial shell "cd $device && ./core_contract_test $device/libfake_core.so $case"
    $lines += $result
    Write-Output $result
    if ($LASTEXITCODE) { throw "Contract test failed: $case" }
}
[IO.File]::WriteAllLines("$out/native-contract-tests.log", $lines, [Text.UTF8Encoding]::new($false))
