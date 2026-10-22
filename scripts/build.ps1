# Full build pipeline: decompile -> patch -> build -> sign.
# Run from the repo root. Requires apktool, build-tools 35.0.0, python.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bt   = "C:\Users\o0o\AppData\Local\Android\Sdk\build-tools\35.0.0"
$ks   = Join-Path $root "okam.keystore"

# Inputs (original APKs must be placed in $root\originals\)
$orig = Join-Path $root "originals"
foreach ($f in @("base.apk","split_config.arm64_v8a.apk","split_config.en.apk","split_config.xxhdpi.apk")) {
    if (-not (Test-Path (Join-Path $orig $f))) { throw "missing original: $f (put the four APKs in originals\)" }
}

$out = Join-Path $root "out"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1. decompile
$tree = Join-Path $root "apktool"
if (Test-Path $tree) { Remove-Item -Recurse -Force $tree }
& java -jar (Join-Path $root "apktool.jar") d (Join-Path $orig "base.apk") -o $tree -f
if ($LASTEXITCODE -ne 0) { throw "apktool decompile failed" }

# 2. patch smali
& python (Join-Path $root "patches\apply_smali_patches.py") --tree $tree
if ($LASTEXITCODE -ne 0) { throw "smali patches failed" }

# 3. rebuild + sign base
& java -jar (Join-Path $root "apktool.jar") b $tree -o (Join-Path $root "patched_base.apk")
if ($LASTEXITCODE -ne 0) { throw "apktool build failed" }
& "$bt\zipalign.exe" -p -f 4 (Join-Path $root "patched_base.apk") (Join-Path $root "patched_base.aligned")
& "$bt\apksigner.bat" sign --ks $ks --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out (Join-Path $out "base.apk") (Join-Path $root "patched_base.aligned")

# 4. patch .so constant + sign split
& python (Join-Path $root "patches\patch_so.py") --src (Join-Path $orig "split_config.arm64_v8a.apk") `
  --dst (Join-Path $root "split_patched.arm64_v8a.apk")
& "$bt\zipalign.exe" -p -f 4 (Join-Path $root "split_patched.arm64_v8a.apk") (Join-Path $root "split_patched.aligned")
& "$bt\apksigner.bat" sign --ks $ks --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out (Join-Path $out "split_config.arm64_v8a.apk") (Join-Path $root "split_patched.aligned")

# 5. sign unchanged splits
foreach ($s in @("split_config.en.apk","split_config.xxhdpi.apk")) {
  & "$bt\zipalign.exe" -p -f 4 (Join-Path $orig $s) (Join-Path $root "$s.aligned")
  & "$bt\apksigner.bat" sign --ks $ks --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
    --out (Join-Path $out $s) (Join-Path $root "$s.aligned")
}

Write-Host "BUILD OK -> $out"
