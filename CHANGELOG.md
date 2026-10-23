# Changelog

## v1.0.1 — 2026-10-23

Single-file install.

### Added
- **`O-KAM-Pro-3.0.17-adfree.apk` — a universal APK** merging the patched base
  and the patched arm64-v8a split into one normal, tappable install file
  (`patches/merge_universal.py`). The 4-file split set stays attached as a
  fallback. Real version preserved: 3.0.17 / versionCode 63.

### Changed
- `apply_smali_patches.py` now also strips Play's split markers from
  `AndroidManifest.xml` (`android:requiredSplitTypes="base__abi,base__density"`,
  `android:splitTypes=""`, meta-data `com.android.vending.splits.required`).
  Without this, PackageInstaller rejects any single-file build with
  `INSTALL_FAILED_MISSING_SPLIT` — the base itself declares it only works with
  its config splits. (apktool auto-adds `android:isSplitRequired="true"` when
  the attribute is present, so removing it removes all three markers.)

### Verified
- Universal APK installs over the existing split install via `adb install -r`
  — app data and login preserved, no uninstall needed.
- `dumpsys package` reports `splits=[base]` (single APK), versionCode 63 /
  versionName 3.0.17.
- English UI intact and all drawables sharp with the `en` / `xxhdpi` splits
  dropped: the base carries unqualified English strings (17,775-string pool,
  no Devanagari) and every density bucket (`mdpi`…`xxxhdpi`).
- Live camera view works, no ad activity in logcat, CPU ~3.4% idle.

## v1.0.0 — 2026-10-22

First ad-free build of O-KAM Pro (`com.okampro.oksmart`).

### Removed
- Splash ad activity (`SplashAdActivity`) is no longer launched.
- TopOn/AnyThink SDK (`com.secmtp.sdk`) is no longer initialised; no placement
  config is fetched, no ad network (AdMob, Pangle, IronSource, Vungle, FAN,
  Bigo, Mintegral, AdColony, Tramini) is bootstrapped.
- `ATAdStatusInfo.isReady()` forced to `false` — banner, interstitial, rewarded
  and splash ads never report as ready.
- Native ads: `makeAdRequest()` no longer called (no creative is ever fetched),
  and the view handed to Flutter is an empty `ATNativeAdView` (no creative is
  ever drawn).
- Signature check bypassed by replacing the vendor cert MD5 constant in
  `libOKSMARTJIAMI.so`.

### Fixed during development
- `ATSDK.init` patch alone was insufficient: `AdMobInitManager.initSDK` still
  ran 5x via an unidentified route. Final kill is at the native-ad boundary
  (`k5/c`), which is the only path the app actually uses.
- `isReady() -> false` alone caused a 162% CPU busy-poll (`checkReadyToShow`
  spin). Fixed by also making `k5/c.e()` report `true` so the poll terminates,
  while `i()` returns an empty view.
- `--title-word` / PowerShell Devanagari argument handling is N/A here, but the
  same "drive non-ASCII from a node/Python script" rule applies to the smali
  patcher (kept ASCII-only).

### Verified
- App launches, stays alive, camera live view works.
- No `nativeAdDidShowNativeAd`, no `nativeAdDidFinishLoading`, no ad traffic.
- CPU ~3–7% at idle (was 162% with the isReady-only patch).
- Installed only in the main profile (user 0).

### Known limitations
- Secure Folder copy (user 150) cannot be removed via adb; remove manually.
- The app's own in-app upsell ("Advertising free" / cloud-storage promo) is
  part of the app UI, not a network ad, and is untouched.
- If the vendor updates the app, re-run the pipeline; the smali anchors may have
  drifted — `apply_smali_patches.py` fails loudly in that case.
