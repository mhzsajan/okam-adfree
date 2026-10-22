# Verification

**Verify the file, never the exit code.** A render/install that finishes is not
one that is correct.

## Automated (scripts/verify.ps1)

- `adb shell pidof com.okampro.oksmart` is non-empty (app alive).
- No `FATAL` / `AndroidRuntime` exception in logcat since boot.
- `checkReadyToShow` log lines: 0 over a 3 s window (no busy-poll).
- `nativeAdDidFinishLoading` / `nativeAdDidShowNativeAd`: 0.
- CPU under 10% at idle.

## Manual (required — no script can tell a good frame from a bad one)

1. Launch the app, wait 30 s.
2. Screenshot the home (device list), Messages and Mine tabs, and a live camera
   view. Confirm no ad slot, no blank gap, no "18+" creative.
3. Open a live view and confirm video streams and the app does not hang.
4. Check the app's own upsell ("Advertising free" / cloud storage) is still
   present — that is intended; only network ads are removed.

Capture screenshots with:

```powershell
cmd /c "adb exec-out screencap -p > shot.png"
```

(Using PowerShell `>` corrupts the PNG.)

## Instruments that misled us (do not trust)

- **Exit code 0** from `adb install-multiple` / `monkey` is not proof of a
  working app. Always check `pidof` and logcat.
- **`--report-only` style flags**: any flag that "does nothing but report" can
  be silently ignored by the tool it is passed to. Read the tool's help.
- **Sampling a frame in a gap between cues** (lyric-project lesson) yields a
  blank plate indistinguishable from a dead feature.
- **A unit test of a pure function** cannot see that a feature was wired into a
  code path the renderer never takes.
- **`isReady() -> false` alone** looks like success (no ad shown) but pegs CPU
  at 162%. Always measure CPU + log volume, not just the screenshot.
