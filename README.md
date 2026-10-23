# O-KAM Pro — ad-free build

A reproducible patch that removes every in-app ad from the O-KAM Pro
security-camera app (`com.okampro.oksmart`), including the "18+" creatives,
without breaking the camera functionality.

The app is a Flutter build. Its ad logic lives in an obfuscated Dart AOT
snapshot (`libapp.so`), so it cannot be edited directly. The ad stack is
TopOn/AnyThink mediation, renamed to `com.secmtp.sdk`, plus AdMob, Pangle,
IronSource, Vungle, FAN, Bigo, Mintegral, AdColony and Tramini. We patch
at the **Java/TopOn boundary** instead, which is where the mediation actually
runs.

## What the patch does

| # | Target | Change |
|---|---|---|
| 1 | `lib/arm64-v8a/libOKSMARTJIAMI.so` | Replace the vendor signing-cert MD5 constant `64D33A…` with the mod key's MD5 `BD40CB…`. Bypasses the app's signature check so our re-signed APK is accepted. No code change; the `.so` stays stored and page-aligned. |
| 2 | `com/okampro/oksmart/MainActivity$a.smali` | Skip the `SplashAdActivity` launch (`jumpToActivity`). |
| 3 | `com/secmtp/sdk/core/api/ATSDK.smali` | Make `init(...)` a no-op that still calls `onSuccess()` (so Dart does not hang), but skips `wwm.wv().ww(...)` so no placement config is fetched. |
| 4 | `com/secmtp/sdk/core/api/ATAdStatusInfo.smali` | Force `isReady()` to `false`. Blocks banner / interstitial / rewarded / splash ads. |
| 5 | `k5/c.smali` (native ad helper) | `e()` always returns `true` (stops the Dart busy-poll), `i()` returns an empty `ATNativeAdView` (no creative is ever drawn), and `f()` no longer calls `makeAdRequest()` (no ad is ever fetched). |

Result: no ad is requested, no ad is shown, no busy loop, CPU stays at ~3–7%.

## Release

| release | files |
|---|---|
| **[v1.0.1 — latest](https://github.com/mhzsajan/okam-adfree/releases/tag/v1.0.1)** | **`O-KAM-Pro-3.0.17-adfree.apk` — single universal APK. Use this one.** All code, resources and native libs in one file; installs like any normal APK. |
| [v1.0.0](https://github.com/mhzsajan/okam-adfree/releases/tag/v1.0.0) | the original 4-file split set (`base.apk` + 3 × `split_config.*.apk`), kept as a fallback. |

### Recommended: the single universal APK

Copy it to the phone and tap it (or via adb):

```powershell
adb install -r O-KAM-Pro-3.0.17-adfree.apk
```

The universal APK is the Play base + the arm64-v8a libs merged into one file,
with Play's split markers (`android:requiredSplitTypes` / `isSplitRequired`)
stripped from the manifest — without that strip PackageInstaller rejects any
single-file build with `INSTALL_FAILED_MISSING_SPLIT`. The `en` and `xxhdpi`
splits are not merged and not needed: the base already carries unqualified
**English** strings (its string pool has no Devanagari at all) and every
density bucket (`mdpi`…`xxxhdpi`). Verified on-device: English UI, live camera,
no ads.

An upgrade over an existing split install (`-r`) works and keeps the app data
(you stay logged in).

### Fallback: the split set

```powershell
adb install-multiple -r --no-incremental base.apk split_config.arm64_v8a.apk split_config.en.apk split_config.xxhdpi.apk
```

Only the main profile (user 0) is touched — the Secure Folder copy must be
removed manually (see below).

## How to rebuild for a future app update

See [`docs/METHOD.md`](docs/METHOD.md) for the full end-to-end procedure and
[`docs/FINDINGS.md`](docs/FINDINGS.md) for the dead ends (so you do not
re-discover them). The short version:

```powershell
# 1. decompile
apktool d base.apk -o apktool

# 2. apply smali patches (idempotent, fails loudly if anchors drift).
#    This also strips Play's split markers from AndroidManifest.xml, which is
#    what makes a standalone (universal) install possible.
python patches/apply_smali_patches.py --tree apktool

# 3. rebuild + sign base
apktool b apktool -o patched_base.apk
zipalign -p -f 4 patched_base.apk patched_base.aligned
apksigner sign --ks okam.keystore --ks-key-alias okam --ks-pass pass:okam123 --key-pass pass:okam123 `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out out\base.apk patched_base.aligned

# 4. patch the .so constant + sign the split
python patches/patch_so.py --src split_config.arm64_v8a.apk --dst split_patched.arm64_v8a.apk
zipalign -p -f 4 split_patched.arm64_v8a.apk split_patched.aligned
apksigner sign ... --out out\split_config.arm64_v8a.apk split_patched.aligned
# (en / xxhdpi splits are signed unchanged)

# 5. build the single universal APK (base + arm64 libs merged)
python patches/merge_universal.py --base out\base.apk `
  --abi-split out\split_config.arm64_v8a.apk --dst universal.apk
zipalign -p -f 4 universal.apk universal.aligned
apksigner sign --ks okam.keystore --ks-key-alias okam --ks-pass pass:okam123 --key-pass pass:okam123 `
  --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true `
  --out O-KAM-Pro-<version>-adfree.apk universal.aligned
aapt2 dump xmltree O-KAM-Pro-<version>-adfree.apk --file AndroidManifest.xml | findstr Split
#    -> must print NOTHING (no split markers). If requiredSplitTypes survives,
#       step 2 did not run on this tree.

# 6. install (universal is enough; the split set also still works)
adb install -r O-KAM-Pro-<version>-adfree.apk
```

`scripts/build.ps1` automates steps 1–4. `scripts/verify.ps1` runs the
post-install checks.

## Secure Folder

The O-KAM copy inside the Secure Folder (user 150) cannot be removed via
`adb` (`SecurityException: Shell does not have permission to access user 150`).
Remove it manually: Secure Folder → long-press O-KAM → Uninstall.

## Important warnings

- `extractNativeLibs=false` — the `.so` entries must stay **stored and 4 KB
  aligned**. Never deflate or re-zip them by hand; use the provided scripts.
- Two renders must not share one tree: `lyrics.generated.js`-style shared state
  is not an issue here, but the `apktool/` tree is the single source of truth
  for one build at a time.
- Never round-trip a non-ASCII file through PowerShell `Get-Content`/`Set-Content`
  (it double-encodes UTF-8). The smali files are ASCII, but the tooling uses
  Python to be safe.
- Verify the **file**, not the exit code. A successful exit code is not proof
  of a correct APK.

See [`docs/VERIFY.md`](docs/VERIFY.md) for the verification instruments and the
ones that misled us.
