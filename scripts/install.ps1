$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out  = Join-Path $root "out"
$apks = @("base.apk","split_config.arm64_v8a.apk","split_config.en.apk","split_config.xxhdpi.apk") |
        ForEach-Object { Join-Path $out $_ }
foreach ($a in $apks) { if (-not (Test-Path $a)) { throw "missing $a -- run build.ps1 first" } }
& adb install-multiple -r --no-incremental @apks
if ($LASTEXITCODE -ne 0) { throw "install failed" }
Write-Host "INSTALLED (main profile only)"
