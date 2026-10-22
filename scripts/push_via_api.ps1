# Push the committed repo to GitHub using the Git Data API (bypasses git transport).
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$owner = "mhzsajan"; $repo = "okam-adfree"
$tmp = Join-Path $env:TEMP "ghpush"; New-Item -ItemType Directory -Force -Path $tmp | Out-Null

$skipDirs = @(".git","out","release","apktool","originals")
$files = Get-ChildItem -Recurse -File | Where-Object {
    $rel = $_.FullName.Substring($root.Length+1).Replace("\","/")
    $skip = $false
    foreach ($d in $skipDirs) { if ($rel -like "$d/*") { $skip = $true } }
    if ($_.Extension -in @(".apk",".keystore",".jks",".aligned")) { $skip = $true }
    -not $skip
}

# 1. create blobs
$treeEntries = @()
foreach ($f in $files) {
    $rel = $f.FullName.Substring($root.Length+1).Replace("\","/")
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($f.FullName))
    $body = @{ content = $b64; encoding = "base64" } | ConvertTo-Json -Compress
    $bodyFile = Join-Path $tmp "blob.json"
    [IO.File]::WriteAllText($bodyFile, $body)
    $resp = gh api "repos/$owner/$repo/git/blobs" --method POST --input $bodyFile 2>&1
    if ($LASTEXITCODE -ne 0) { throw "blob failed for $rel : $resp" }
    $sha = ($resp | ConvertFrom-Json).sha
    $treeEntries += @{ path = $rel; mode = "100644"; type = "blob"; sha = $sha }
    Write-Host "blob $rel -> $sha"
}

# 2. create tree
$treeBody = @{ tree = $treeEntries } | ConvertTo-Json -Depth 5 -Compress
$treeFile = Join-Path $tmp "tree.json"
[IO.File]::WriteAllText($treeFile, $treeBody)
$treeResp = gh api "repos/$owner/$repo/git/trees" --method POST --input $treeFile 2>&1
if ($LASTEXITCODE -ne 0) { throw "tree failed: $treeResp" }
$treeSha = ($treeResp | ConvertFrom-Json).sha
Write-Host "tree -> $treeSha"

# 3. create commit
$commitBody = @{ message = "Initial commit: O-KAM Pro ad-free patch (v1.0.0)"; tree = $treeSha; parents = @() } | ConvertTo-Json -Depth 5 -Compress
$commitFile = Join-Path $tmp "commit.json"
[IO.File]::WriteAllText($commitFile, $commitBody)
$commitResp = gh api "repos/$owner/$repo/git/commits" --method POST --input $commitFile 2>&1
if ($LASTEXITCODE -ne 0) { throw "commit failed: $commitResp" }
$commitSha = ($commitResp | ConvertFrom-Json).sha
Write-Host "commit -> $commitSha"

# 4. create main ref
$refBody = @{ ref = "refs/heads/main"; sha = $commitSha } | ConvertTo-Json -Compress
$refFile = Join-Path $tmp "ref.json"
[IO.File]::WriteAllText($refFile, $refBody)
$refResp = gh api "repos/$owner/$repo/git/refs" --method POST --input $refFile 2>&1
if ($LASTEXITCODE -ne 0) { throw "ref failed: $refResp" }
Write-Host "ref main -> $commitSha"

Write-Host "PUSHED via API. Now create the release with scripts/publish.ps1 (release part)."
