# Downloads US Harmonized Tariff Schedule (HTS) from USITC.
# Source: https://hts.usitc.gov/
# Uses /reststop/currentRelease for revision-based change detection (~10 revisions/year).
# Downloads the full HTS (chapters 01-99) as both JSON and CSV in a single API call each.
#
# In GitHub Actions, pre-populate hts-version.json from the prior release before calling
# this script so the revision check works without a checkout of previous downloads.
param(
    [string]$OutputFolder = "downloads/us",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$BaseUrl = "https://hts.usitc.gov/reststop"
$UA      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

# ─── Check current revision ───────────────────────────────────────────────────

$rel = (Invoke-WebRequest -Uri "$BaseUrl/currentRelease" -UserAgent $UA -UseBasicParsing -TimeoutSec 15).Content |
    ConvertFrom-Json
$release = $rel.name    # e.g. "2026HTSRev10"
Write-Host "Current HTS release: $release ($($rel.title))"

$versionFile = Join-Path $OutputFolder "hts-version.json"
if (-not $Force -and (Test-Path $versionFile)) {
    $stored = (Get-Content $versionFile -Raw | ConvertFrom-Json).name
    if ($stored -eq $release) {
        Write-Host "Already at latest release ($release) — nothing to download."
        exit 0
    }
    Write-Host "Revision changed: $stored → $release"
}

# ─── Download full HTS ───────────────────────────────────────────────────────

$jsonFile = Join-Path $OutputFolder "hts-us.json"
$csvFile  = Join-Path $OutputFolder "hts-us.csv"

Write-Host "Downloading JSON (all chapters 01-99)..."
Invoke-WebRequest -Uri "$BaseUrl/exportList?from=0101&to=9999.99.99.99&format=JSON&styles=false" `
    -UserAgent $UA -UseBasicParsing -MaximumRedirection 5 -OutFile $jsonFile -TimeoutSec 180
Write-Host "  → $([math]::Round((Get-Item $jsonFile).Length / 1MB, 1)) MB"

Write-Host "Downloading CSV (all chapters 01-99)..."
Invoke-WebRequest -Uri "$BaseUrl/exportList?from=0101&to=9999.99.99.99&format=CSV&styles=false" `
    -UserAgent $UA -UseBasicParsing -MaximumRedirection 5 -OutFile $csvFile -TimeoutSec 180
Write-Host "  → $([math]::Round((Get-Item $csvFile).Length / 1MB, 1)) MB"

# Write version marker (used as change-detection sentinel on next run)
$rel | ConvertTo-Json | Set-Content $versionFile -NoNewline

Write-Host ""
Write-Host "Downloaded: $release"
