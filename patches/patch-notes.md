# Patch notes

Each patch, what it does, and why.

## 1. `MainActivity$a.smali` — skip `SplashAdActivity`

The app's Flutter side calls the `jumpToActivity` method channel, which starts
`SplashAdActivity` (a fullscreen ad). We return immediately. Dart calls this
fire-and-forget and never waits for a reply, so no callback is needed.

## 2. `ATSDK.smali` — no-op `init`

`init(...)` 5-arg now calls `p4.onSuccess()` (if non-null) and returns, skipping
`wwm.wv().ww(...)`. This prevents placement-config fetch and ad-network
bootstrap. The success callback keeps the Dart layer from hanging.

Note: this alone is insufficient — `AdMobInitManager.initSDK` still runs 5x via
an unidentified route. It is kept as belt-and-braces.

## 3. `ATAdStatusInfo.smali` — `isReady() -> false`

Forces every format (banner, interstitial, rewarded, splash, native) to report
"not ready", so the app never attempts to show one. On its own this causes a
162% CPU busy-poll; it must be paired with patch 5.

## 4. `k5/c.smali` — native ad helper (three edits)

- `e()` (checkNativeAdLoadStatus / nativeAdReady) always returns `true`. This
  terminates the Dart `while(!ready)` poll that otherwise spins at 162% CPU.
- `f()` (loadNativeAd) no longer calls `makeAdRequest()`. No ad is ever fetched.
- `i()` (render) returns a fresh empty `ATNativeAdView`. Non-null is required:
  returning null is what triggers the spin.

Together with patch 3, this means: no request, no show, no spin, no gap.
