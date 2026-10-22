# Publish to GitHub: push the repo and create a release with the APKs attached.
# Run this once the network to github.com is back.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$rel  = Join-Path $root "release"

Set-Location $root
git push -u origin main
if ($LASTEXITCODE -ne 0) { throw "push failed" }

$tag = "v1.0.0"
$notes = "First ad-free build. See CHANGELOG.md."
$apks = @("base.apk","split_config.arm64_v8a.apk","split_config.en.apk","split_config.xxhdpi.apk") |
        ForEach-Object { Join-Path $rel $_ }

gh release create $tag @apks --title "v1.0.0 - ad-free build" --notes $notes
if ($LASTEXITCODE -ne 0) { throw "release creation failed" }
Write-Host "PUBLISHED: https://github.com/mhzsajan/okam-adfree/releases/tag/$tag"
