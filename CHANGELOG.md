# Changelog

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
