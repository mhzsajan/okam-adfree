$ErrorActionPreference = "Continue"
$pkg = "com.okampro.oksmart"

# Install-state assertions (universal APK must be a single split, right version)
$pkginfo = adb shell dumpsys package $pkg
$ver = (($pkginfo | Select-String "versionName=").Line -split "versionName=", 2)[1].Trim()
$splits = (($pkginfo | Select-String "splits=").Line -split "splits=", 2)[1].Trim()
Write-Host "versionName: $ver"
Write-Host "splits: $splits   (a universal install must be exactly [base])"
if ($splits -ne "[base]") { Write-Host "FAIL: not installed as a single universal APK"; exit 1 }

$pid = (adb shell pidof $pkg).Trim()
Write-Host "pid: $pid"
if (-not $pid) { Write-Host "FAIL: app not running"; exit 1 }

$crash = (adb logcat -d 2>$null | Select-String "FATAL|AndroidRuntime.*Exception").Count
Write-Host "crashes since boot: $crash"

$before = (adb logcat -d 2>$null | Select-String "checkReadyToShow").Count
Start-Sleep -Seconds 3
$after  = (adb logcat -d 2>$null | Select-String "checkReadyToShow").Count
Write-Host "checkReadyToShow lines in 3s: $($after - $before)  (must be 0)"

$loads = (adb logcat -d 2>$null | Select-String "nativeAdDidFinishLoading").Count
$shows = (adb logcat -d 2>$null | Select-String "nativeAdDidShowNativeAd").Count
Write-Host "native ad loads: $loads   shows: $shows  (must be 0)"

$cpu = (adb shell top -b -n 1 -o PID,%CPU,ARGS 2>$null | Select-String $pkg).ToString().Trim()
Write-Host "cpu: $cpu"

Write-Host ""
Write-Host "Capture screenshots with:  cmd /c `"adb exec-out screencap -p > shot.png`""
