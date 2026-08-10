# Downloads the EU Binding Tariff Information (EBTI) full extract from DDS2.
# Source: https://ec.europa.eu/taxation_customs/dds2/ebti/
# Full extract (~390 MB ZIP) is regenerated daily; change detection uses the
# exportdate JS variable so the 390 MB download is skipped when unchanged.
# In GitHub Actions, pre-populate ebti-version.txt from the prior release before
# calling this script so the version check works without a local downloads cache.
param(
    [string]$OutputFolder = "downloads/ebti",
    [string[]]$SkipFiles  = @(),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$UA      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
$BaseUrl = "https://ec.europa.eu/taxation_customs/dds2/ebti"

# The DDS2 endpoints stall now and then, and an unretried stall fails the whole run: the
# 2026-08-07 11:08 and 2026-08-08 11:02 runs both died on the export-date fetch below hitting its
# 15-second timeout, with the endpoint otherwise healthy. Nothing was lost either time — the next
# run re-reads the export date and downloads the extract if it moved — so the cost was a false red
# on a job whose whole point is to tell us when something IS wrong.
#
# Four attempts with exponential backoff, matching sync-eu.ps1 and sync-eurlex-meta.ps1. Still
# throws on the last: a publisher that is genuinely down must fail loudly.
# ─── Resolve current export date ─────────────────────────────────────────────

$today = Get-Date -Format 'yyyyMMdd'
Write-Host "Fetching EBTI export date..."
$js = (Invoke-WithRetry -What "EBTI export date" -Action {
    Invoke-WebRequest -Uri "$BaseUrl/exportdate/exportdate_$today.js" `
        -UserAgent $UA -UseBasicParsing -TimeoutSec 15
}).Content
if ($js -notmatch 'ebtiExportDate\s*=\s*\["([^"]+)"\]') {
    throw "Could not parse ebtiExportDate from: $js"
}
$exportDate = $matches[1]   # e.g. "29-06-2026"
Write-Host "Current EBTI export date: $exportDate"

# ─── Change detection ─────────────────────────────────────────────────────────

$zipFile     = Join-Path $OutputFolder "DDS2-EBTI_Full.zip"
$versionFile = Join-Path $OutputFolder "ebti-version.txt"

if (-not $Force -and (Test-Path $versionFile)) {
    $stored = (Get-Content $versionFile -Raw).Trim()
    if ($stored -eq $exportDate) {
        Write-Host "EBTI export unchanged ($exportDate) — nothing to download."
        exit 0
    }
    Write-Host "Export date changed: $stored → $exportDate"
}

# ─── Download full extract ────────────────────────────────────────────────────

Write-Host "Downloading DDS2-EBTI_Full.zip (~390 MB)..."
$tmpFile = Join-Path $OutputFolder "DDS2-EBTI_Full.zip.tmp"
# A stalled 390 MB download leaves a partial .tmp behind; the size and ZIP-magic checks below
# would catch it, but only after the retry had "succeeded" against it. Removed before each try.
Invoke-WithRetry -What "EBTI full extract" -Action {
    if (Test-Path $tmpFile) { Remove-Item $tmpFile -Force }
    Invoke-WebRequest -Uri "$BaseUrl/ebti_export_management.jsp?message=extractFull" `
        -UserAgent $UA -UseBasicParsing -OutFile $tmpFile -TimeoutSec 600 -MaximumRedirection 5
}

$sz = (Get-Item $tmpFile).Length
if ($sz -lt 10MB) { Remove-Item $tmpFile; throw "Downloaded file too small ($sz bytes) — likely an error response" }

$magic = [System.IO.File]::ReadAllBytes($tmpFile)[0..1]
if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
    Remove-Item $tmpFile; throw "Downloaded file is not a ZIP (magic: $($magic -join ' '))"
}

if (Test-Path $zipFile) { Remove-Item $zipFile }
Move-Item $tmpFile $zipFile
$exportDate | Set-Content $versionFile -NoNewline

Write-Host "Downloaded: $([math]::Round((Get-Item $zipFile).Length / 1MB, 1)) MB → DDS2-EBTI_Full.zip (export date: $exportDate)"
