# Findings: the ad stack and the dead ends

## Ad stack inventory

- TopOn / AnyThink mediation, renamed to `com.secmtp.sdk` (the `com.anythink`
  package holds only debug R classes).
- Ad networks: AdMob, Pangle (ByteDance), IronSource, Vungle, FAN, Bigo,
  Mintegral, AdColony, Tramini.
- Flutter bridge: `f5.c` (plugin), `f5.a$b.onMethodCall` (dispatcher),
  handlers `i5.a` (init), `j5.a` (interstitial), `k5.a` (native), `g5.a`
  (banner), `l5.a` (rewarded), `m5.a` (splash). Method names in `n5.a`.
- Only the **native** format is actually used by this app (no banner /
  interstitial / rewarded / splash events in logcat).

## How the app boots the ads (and why it is hard to kill at init)

- `i5.a` (plugin init) calls `ATSDK.init(...)` 3-arg -> 4-arg -> 5-arg.
  Patching the 5-arg `init` to a no-op (still calling `onSuccess()`) is
  **insufficient**: `AdMobInitManager.initSDK` still runs 5x. Probe build
  confirmed: `P1 ATSDK.init5 ENTER` fires once, `P3 AdMobInitManager.initSDK
  ENTER` fires 5x, `P2 wwm.ww4 ENTER` never fires.
- `wwm.ww(Context, String, String, ATNetworkConfig)` has **zero callers** and
  never fires. `wwm.vn(Context)` (dead, line 1296) is the only other init path.
- `ATInitializationProvider` (`wn.ww(Application)`) only registers lifecycle
  callbacks — not an init trigger.
- No other bootstrap: no dynamic dex (the only dex is FAN's
  `audience_network.dex`), no app-package init (only `SplashAdActivity` touches
  `secmtp`), and the JSON assets (`supplierconfig.json`, `builddatas.json`,
  `network_debug_config.json`) are name-mapping only.

Conclusion: the mediation adapters initialise through a route we never
identified. Killing at init is not viable; the kill must be at the ad object /
plugin boundary. That is what patch #5 does.

## Dead ends (do not re-investigate)

- **Second TopOn copy under `com.anythink.core`**: referenced by obfuscated
  classes (`v0`, `r0`, `m0`, `c1`, `e1`) and by the debug tool, but no class
  declares `com.anythink.core.*` — those references are dangling (R8 leftovers).
  Not a live ad path.
- **`ATAdStatusInfo.isReady() -> false` alone**: removes the ad but the Dart
  layer busy-polls `checkReadyToShow` in a tight loop (162% CPU, ~230 lines/s).
  Must be paired with `k5/c.e() -> true` + `i() -> empty view`.
- **Patching only `ATSDK.init`**: proven insufficient (see above).
- **`--type` typing reveal / `--x-pos`**: not ad-related, but documented in the
  project's house style notes; unrelated to this repo.

## Instruments that misled us

- **Sampling a frame that falls in the gap between cues** yields a blank plate
  indistinguishable from a dead feature. Always check the cue timeline.
- **A unit test of a pure function** cannot see that the feature was wired into
  a code path the renderer never takes. (Lyric-project lesson; applies here too.)
- **Exit code 0 is not success.** `make_video.mjs` silently ignores
  `--report-only` and writes no file; the failure reads like a crash.
- **`--no-beats` is not optional** for this app's beat grid (Kali Kali scores
  2.51 < 3.0 threshold). N/A here but the same "refusal is correct, not a bug"
  principle holds: an untrusted grid pulls words off hand-tapped times.

## Key constants

- Vendor signing-cert MD5: `64D33A12C0451837365F911F691D9334`
- Mod signing-cert MD5:    `BD40CB13A568C953EC589D72239FC793`
- App package: `com.okampro.oksmart`
- TopOn renamed package: `com.secmtp.sdk`
- Flutter plugin native handler: `k5/c` (native ads), method names in `k5/a.c`
  (`checkNativeAdLoadStatus` / `nativeAdReady` -> `e()`, `loadNativeAd` -> `f()`,
  `showNativeAd` -> `k()`, render -> `i()`).
