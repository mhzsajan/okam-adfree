# Method: removing ads from O-KAM Pro

This document is the reproducible procedure. Read `FINDINGS.md` first for the
map of the ad stack and the dead ends.

## Prerequisites

- Android SDK build-tools 35.0.0 (`zipalign`, `apksigner`) on PATH or at
  `C:\Users\o0o\AppData\Local\Android\Sdk\build-tools\35.0.0`.
- apktool (`java -jar tools\apktool.jar` — keep the jar in `tools/`, gitignored).
- Python 3.10+.
- ADB with a device attached (`adb devices`).
- The four original APKs in `originals\`: `base.apk`, `split_config.arm64_v8a.apk`,
  `split_config.en.apk`, `split_config.xxhdpi.apk` (pull from the device after a
  Play Store install — see "Updating for a new app version").
- The signing keystore at the repo root as `okam.keystore`. **Gitignored — never
  commit it, and keep a backup outside any temp directory.** Losing it means no
  more in-place upgrades: the `.so` cert constant and every installed build are
  tied to this one key. Generate once:

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

The same script also strips Play's split markers from `AndroidManifest.xml`
(`android:requiredSplitTypes="base__abi,base__density"`, `android:splitTypes=""`,
and the `com.android.vending.splits.required` meta-data; apktool auto-adds
`android:isSplitRequired="true"` while the attribute is present, so removing it
removes all three markers). Without this strip, PackageInstaller rejects the
rebuilt base — standalone or merged — with `INSTALL_FAILED_MISSING_SPLIT`.

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

## Step 6 — merge the single universal APK (primary deliverable)

`patches/merge_universal.py` combines the signed base and the signed ABI split
into ONE normal APK. The `en`/`xxhdpi` splits are **not** merged — the base
already carries unqualified English strings (its string pool has no Devanagari)
and every density bucket, so an English device loses nothing. All lib entries
stay `STORED` and page-aligned.

```powershell
python patches/merge_universal.py --base out\base.apk `
  --abi-split out\split_config.arm64_v8a.apk --dst out\universal_unsigned.apk
zipalign -p -f 4 out\universal_unsigned.apk out\universal_aligned.apk
apksigner sign --ks okam.keystore --ks-key-alias okam `
  --ks-pass pass:okam123 --key-pass pass:okam123 `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out "out\O-KAM-Pro-<version>-adfree.apk" out\universal_aligned.apk

# gate — must print NOTHING, or the split markers survived and install will fail:
aapt2 dump xmltree "out\O-KAM-Pro-<version>-adfree.apk" --file AndroidManifest.xml | findstr Split
```

## Step 7 — install

```powershell
# preferred: single file
adb install -r "out\O-KAM-Pro-<version>-adfree.apk"

# fallback: the split set
adb install-multiple -r --no-incremental `
  out\base.apk out\split_config.arm64_v8a.apk out\split_config.en.apk out\split_config.xxhdpi.apk
```

An `-r` upgrade over an older build signed with the same key preserves app
data (login, devices, settings). Only the main profile (user 0) is touched —
no other profile should carry this app.

## Step 8 — verify

```powershell
scripts\verify.ps1
```

See `docs/VERIFY.md`.

## Updating for a new app version

`scripts\build.ps1` automates steps 1–6 (it reads the version from the
originals' badging, runs every stage with a hard failure on any non-zero
exit, and gates the universal APK on "no split markers in the manifest").
The manual sequence above is what it does.

1. Install the new version from the Play Store on the device, pull the new
   four original APKs into `originals\`, and keep the previous version's
   originals under `originals\v<old>\` (history matters when an anchor patch
   needs comparing).
2. Run `scripts\build.ps1` (or steps 1–8 manually).
3. If `apply_smali_patches.py` fails on an anchor, open the new smali, find the
   equivalent code, and update the anchor in `patches/apply_smali_patches.py`.
   Do not weaken an anchor to make it match — that is how a patch silently
   stops applying.
4. If `patch_so.py` fails, the cert-MD5 constant in `libOKSMARTJIAMI.so` moved
   or changed — grep the new `.so` for the hex, confirm the new value against
   `keytool -printcert -rfc` of the *original* APK, and update the old/new
   pair (`--old-md5`/`--new-md5`).
5. Re-verify with `scripts\verify.ps1` and a manual screenshot check.
6. Bump `CHANGELOG.md` and cut a new release.
