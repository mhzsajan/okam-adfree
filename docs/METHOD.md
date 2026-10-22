# Method: removing ads from O-KAM Pro

This document is the reproducible procedure. Read `FINDINGS.md` first for the
map of the ad stack and the dead ends.

## Prerequisites

- Android SDK build-tools 35.0.0 (`zipalign`, `apksigner`) on PATH or at
  `C:\Users\o0o\AppData\Local\Android\Sdk\build-tools\35.0.0`.
- apktool 3.0.3 (`java -jar apktool.jar`).
- Python 3.10+.
- ADB with a device attached (`adb devices`).
- The four original APKs: `base.apk`, `split_config.arm64_v8a.apk`,
  `split_config.en.apk`, `split_config.xxhdpi.apk` (pull from the device or
  from a Play Store backup).
- A signing keystore. Generate once:

```powershell
keytool -genkeypair -v -keystore okam.keystore -alias okam -keyalg RSA `
  -keysize 2048 -validity 10000 -storepass okam123 -keypass okam123 `
  -dname "CN=OKAM Mod"
```

## Step 1 — decompile

```powershell
apktool d base.apk -o apktool
```

## Step 2 — apply smali patches

```powershell
python patches/apply_smali_patches.py --tree apktool
```

The patcher is idempotent: re-running on an already-patched tree is a no-op.
If an anchor string is missing it exits non-zero instead of silently doing
nothing — that is the signal that the app updated and the anchors drifted.

## Step 3 — rebuild + sign the base

```powershell
apktool b apktool -o patched_base.apk
zipalign -p -f 4 patched_base.apk patched_base.aligned
apksigner sign --ks okam.keystore --ks-key-alias okam `
  --ks-pass pass:okam123 --key-pass pass:okam123 `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out out\base.apk patched_base.aligned
```

## Step 4 — patch the signing-cert constant in the split's .so

The app verifies its own signing certificate at runtime by comparing an MD5
constant embedded in `lib/arm64-v8a/libOKSMARTJIAMI.so` against the running
app's cert. Replace the vendor constant with the mod key's constant.

First compute the mod key's cert MD5:

```powershell
keytool -list -v -keystore okam.keystore -alias okam 2>$null |
  Select-String "MD5"   # -> MD5: BD:40:CB:...  -> strip colons -> BD40CB...
```

Then patch (raw bytes, same length, so alignment is preserved):

```powershell
python patches/patch_so.py --src split_config.arm64_v8a.apk `
  --dst split_patched.arm64_v8a.apk `
  --old-md5 64D33A12C0451837365F911F691D9334 `
  --new-md5 BD40CB13A568C953EC589D72239FC793
zipalign -p -f 4 split_patched.arm64_v8a.apk split_patched.aligned
apksigner sign --ks okam.keystore --ks-key-alias okam `
  --ks-pass pass:okam123 --key-pass pass:okam123 `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out out\split_config.arm64_v8a.apk split_patched.aligned
```

`patch_so.py` rewrites the zip entry with the patched bytes and a correct CRC,
preserving the `STORED` compression of the `.so` (required for
`extractNativeLibs=false`).

## Step 5 — sign the unchanged splits

```powershell
foreach ($s in @("split_config.en.apk","split_config.xxhdpi.apk")) {
  zipalign -p -f 4 $s "out\$s.aligned"
  apksigner sign --ks okam.keystore --ks-key-alias okam `
    --ks-pass pass:okam123 --key-pass pass:okam123 `
    --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
    --out "out\$s" "out\$s.aligned"
}
```

## Step 6 — install

```powershell
adb install-multiple -r --no-incremental `
  out\base.apk out\split_config.arm64_v8a.apk out\split_config.en.apk out\split_config.xxhdpi.apk
```

Data is preserved (login, devices, settings). Only the main profile (user 0).

## Step 7 — verify

```powershell
scripts\verify.ps1
```

See `docs/VERIFY.md`.

## Updating for a new app version

1. Pull the new original APKs.
2. Re-run steps 1–7.
3. If `apply_smali_patches.py` fails on an anchor, open the new smali, find the
   equivalent code, and update the anchor in `patches/apply_smali_patches.py`.
   Do not weaken an anchor to make it match — that is how a patch silently
   stops applying.
4. Re-verify with `scripts/verify.ps1` and a manual screenshot check.
5. Bump `CHANGELOG.md` and cut a new release.
