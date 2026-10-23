# Full build pipeline: decompile -> patch -> rebuild -> sign -> merge universal.
# Run from anywhere (paths resolve relative to the repo).
#
#   scripts\build.ps1                # full build, writes out\O-KAM-Pro-<ver>-adfree.apk
#
# Requirements (all local to the repo, none committed):
#   tools\apktool.jar      apktool (gitignored)
#   originals\*.apk        the four original Play APKs (gitignored)
#   okam.keystore          signing key (gitignored - NEVER commit, keep a backup!)
#
# The universal APK is the primary deliverable; the split set in out\ is the
# fallback. apply_smali_patches.py also strips Play's split markers from
# AndroidManifest.xml - without that, the universal APK cannot install at all
# (INSTALL_FAILED_MISSING_SPLIT).

param(
    [string]$Originals = "",
    [string]$Keystore = "",
    [string]$Apktool = "",
    [string]$SkipUniversal = $false
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$bt = "C:\Users\o0o\AppData\Local\Android\Sdk\build-tools\35.0.0"
if (-not $Originals) { $Originals = Join-Path $root "originals" }
if (-not $Keystore)  { $Keystore  = Join-Path $root "okam.keystore" }
if (-not $Apktool)   { $Apktool   = Join-Path $root "tools\apktool.jar" }

# --- input validation (fail loudly, never half-build) ---
foreach ($f in @("base.apk", "split_config.arm64_v8a.apk", "split_config.en.apk", "split_config.xxhdpi.apk")) {
    if (-not (Test-Path (Join-Path $Originals $f))) { throw "missing original: $f (put the four APKs in $Originals)" }
}
if (-not (Test-Path $Apktool))   { throw "apktool.jar not found at $Apktool" }
if (-not (Test-Path $Keystore))  { throw "keystore not found at $Keystore" }

# version from the original base (never typed by hand)
$badging = & "$bt\aapt2.exe" dump badging (Join-Path $Originals "base.apk") 2>&1
if ($LASTEXITCODE -ne 0) { throw "aapt2 badging failed" }
$ver = ($badging | Select-String "versionName=") -replace ".*versionName='([^']+)'.*", '$1'
$vc  = ($badging | Select-String "versionCode=")  -replace ".*versionCode='(\d+)'.*", '$1'
Write-Host "BUILD TARGET: O-KAM Pro $ver (versionCode $vc)"

$out = Join-Path $root "out"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# 1. decompile (fresh tree every time - never patch a stale one)
$tree = Join-Path $root "apktool"
if (Test-Path $tree) { Remove-Item -Recurse -Force $tree }
& java -jar $Apktool d (Join-Path $Originals "base.apk") -o $tree -f
if ($LASTEXITCODE -ne 0) { throw "apktool decompile failed" }

# 2. patch smali + strip split markers (idempotent, fails loudly on anchor drift)
& python (Join-Path $root "patches\apply_smali_patches.py") --tree $tree
if ($LASTEXITCODE -ne 0) { throw "smali patches failed - update the anchors for the new version" }

# 3. rebuild + sign base
& java -jar $Apktool b $tree -o (Join-Path $root "patched_base.apk")
if ($LASTEXITCODE -ne 0) { throw "apktool build failed" }
& "$bt\zipalign.exe" -p -f 4 (Join-Path $root "patched_base.apk") (Join-Path $root "patched_base.aligned")
if ($LASTEXITCODE -ne 0) { throw "zipalign base failed" }
& "$bt\apksigner.bat" sign --ks $Keystore --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out (Join-Path $out "base.apk") (Join-Path $root "patched_base.aligned")
if ($LASTEXITCODE -ne 0) { throw "sign base failed" }

# 4. patch the cert-MD5 constant in the .so + sign the ABI split
& python (Join-Path $root "patches\patch_so.py") --src (Join-Path $Originals "split_config.arm64_v8a.apk") `
  --dst (Join-Path $root "split_patched.arm64_v8a.apk")
if ($LASTEXITCODE -ne 0) { throw "patch_so failed - the .so constant may have changed in $ver" }
& "$bt\zipalign.exe" -p -f 4 (Join-Path $root "split_patched.arm64_v8a.apk") (Join-Path $root "split_patched.aligned")
if ($LASTEXITCODE -ne 0) { throw "zipalign split failed" }
& "$bt\apksigner.bat" sign --ks $Keystore --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out (Join-Path $out "split_config.arm64_v8a.apk") (Join-Path $root "split_patched.aligned")
if ($LASTEXITCODE -ne 0) { throw "sign split failed" }

# 5. sign the unchanged config splits (fallback set only; universal drops them)
foreach ($s in @("split_config.en.apk", "split_config.xxhdpi.apk")) {
    & "$bt\zipalign.exe" -p -f 4 (Join-Path $Originals $s) (Join-Path $root "$s.aligned")
    if ($LASTEXITCODE -ne 0) { throw "zipalign $s failed" }
    & "$bt\apksigner.bat" sign --ks $Keystore --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
      --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
      --out (Join-Path $out $s) (Join-Path $root "$s.aligned")
    if ($LASTEXITCODE -ne 0) { throw "sign $s failed" }
}

# 6. merge the universal single-file APK (base + arm64 libs)
if (-not $SkipUniversal) {
    $uniUnsigned = Join-Path $out "universal_unsigned.apk"
    $uniAligned  = Join-Path $out "universal_aligned.apk"
    $uniFinal    = Join-Path $out "O-KAM-Pro-$ver-adfree.apk"
    & python (Join-Path $root "patches\merge_universal.py") --base (Join-Path $out "base.apk") `
      --abi-split (Join-Path $out "split_config.arm64_v8a.apk") --dst $uniUnsigned
    if ($LASTEXITCODE -ne 0) { throw "merge_universal failed" }
    & "$bt\zipalign.exe" -p -f 4 $uniUnsigned $uniAligned
    if ($LASTEXITCODE -ne 0) { throw "zipalign universal failed" }
    & "$bt\apksigner.bat" sign --ks $Keystore --ks-key-alias okam --ks-pass "pass:okam123" --key-pass "pass:okam123" `
      --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
      --out $uniFinal $uniAligned
    if ($LASTEXITCODE -ne 0) { throw "sign universal failed" }

    # gate: split markers must be GONE from the built manifest, or install fails
    $markers = & "$bt\aapt2.exe" dump xmltree $uniFinal --file AndroidManifest.xml 2>&1 |
        Select-String "isSplitRequired|requiredSplitTypes|splitTypes"
    if ($markers) { throw "split markers survived the rebuild - strip step did not run:" + ($markers -join "; ") }
    & "$bt\apksigner.bat" verify $uniFinal
    if ($LASTEXITCODE -ne 0) { throw "apksigner verify failed for universal" }
    Write-Host "UNIVERSAL OK -> $uniFinal"
}

Write-Host "BUILD OK -> $out  (version $ver)"
