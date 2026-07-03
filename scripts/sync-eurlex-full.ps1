# Downloads FULL TEXT (HTML) for the EU customs legislation listed in the manifest
# produced by sync-eurlex-meta.ps1, then zips it per language. This is the heavy,
# MANUAL-ONLY half — it is deliberately NOT part of the daily sync.
#
# Reads the CELEX list from eurlex-manifest.csv (published by the meta sync) and
# fetches each act's HTML via CELLAR content-negotiation
# (http://publications.europa.eu/resource/celex/{CELEX}, Accept: application/xhtml+xml).
#
# WHY SEPARATE / MANUAL:
#   Full text is ~hundreds of MB and thousands of HTTP requests; it changes slowly and
#   is optional (the manifest + a EUR-Lex deep-link already covers the regulation modal).
#   HTML compresses ~20-25x, so even the whole Customs Union chapter zips to well under
#   GitHub's 2 GB per-asset limit.
#
# OUTPUT (per language):
#   eurlex-text-{lang}.zip  — {CELEX}.html files.
#
# Older acts / some manifestations have no HTML manifestation (PDF/scan only); those
# are reported as misses and skipped.

param(
    [string]   $OutputFolder = "downloads/eurlex",
    [string]   $ManifestPath = "",                 # defaults to <OutputFolder>/eurlex-manifest.csv
    [string[]] $Languages    = @("ENG"),           # ISO 639-3; add "NLD" for Dutch
    [int]      $Limit        = 0,                   # 0 = all; >0 caps works (for testing)
    [switch]   $Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

if (-not $ManifestPath) { $ManifestPath = Join-Path $OutputFolder "eurlex-manifest.csv" }
if (-not (Test-Path $ManifestPath)) {
    throw "Manifest not found at '$ManifestPath'. Run sync-eurlex-meta.ps1 first (or download eurlex-manifest.csv from the release)."
}

$UA    = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"
$works = Import-Csv -Path $ManifestPath
if ($Limit -gt 0) { $works = $works | Select-Object -First $Limit }
$total = @($works).Count
Write-Host "Manifest: $ManifestPath ($total works$(if ($Limit -gt 0) { " — capped to $Limit" }))"

foreach ($lang in $Languages) {
    $langIso3 = $lang.ToLower()
    $textDir  = Join-Path $OutputFolder "text-$langIso3"
    if (Test-Path $textDir) { Remove-Item $textDir -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $textDir | Out-Null

    Write-Host "Downloading full text ($lang) for $total works..."
    $ok = 0; $miss = 0; $rawBytes = 0; $i = 0
    foreach ($wk in $works) {
        $i++
        if ($i % 100 -eq 0) {
            Write-Host "  $i/$total (ok=$ok miss=$miss, raw=$([math]::Round($rawBytes/1MB,1)) MB)"
        }
        $url = "http://publications.europa.eu/resource/celex/$($wk.Celex)"
        try {
            $resp = Invoke-WebRequest -Uri $url -UserAgent $UA -UseBasicParsing -MaximumRedirection 8 -TimeoutSec 60 `
                -Headers @{ Accept = "application/xhtml+xml"; "Accept-Language" = $langIso3 }
            $html = $resp.Content
            if ([string]::IsNullOrWhiteSpace($html) -or $html.Length -lt 200) { $miss++; continue }
            $file = Join-Path $textDir "$($wk.Celex).html"
            [System.IO.File]::WriteAllText($file, $html, [System.Text.Encoding]::UTF8)
            $rawBytes += (Get-Item $file).Length
            $ok++
        } catch { $miss++ }
    }

    $zip = Join-Path $OutputFolder "eurlex-text-$langIso3.zip"
    if (Test-Path $zip) { Remove-Item $zip -Force }
    if ($ok -eq 0) { Remove-Item $textDir -Recurse -Force; Write-Warning "No HTML retrieved for $lang — no zip written."; continue }
    Compress-Archive -Path (Join-Path $textDir "*") -DestinationPath $zip -CompressionLevel Optimal
    Remove-Item $textDir -Recurse -Force
    $zipBytes = (Get-Item $zip).Length

    Write-Host ""
    Write-Host "─── Full text ($lang): ok=$ok miss=$miss ─────────────────────────"
    Write-Host ("  raw HTML : {0,8:N1} MB  (avg {1:N0} KB/doc)" -f ($rawBytes/1MB), (($rawBytes/$ok)/1KB))
    Write-Host ("  zipped   : {0,8:N1} MB  ({1:N1}x compression)" -f ($zipBytes/1MB), ($rawBytes/$zipBytes))
    if ($ok -lt $total) {
        Write-Host "  NOTE: $ok of $total had HTML (older acts may be PDF/scan only)"
    }
    if ($Limit -gt 0) {
        $perZip = $zipBytes / $ok
        Write-Host "  --- projection from this sample (zipped, $lang) ---"
        foreach ($n in @(991,3996,7668,9509,14956)) {
            Write-Host ("    {0,6} works -> {1,7:N0} MB zipped" -f $n, ($n*$perZip/1MB))
        }
    }
    if ($zipBytes -gt 1.9GB) {
        Write-Warning "eurlex-text-$langIso3.zip is $([math]::Round($zipBytes/1GB,2)) GB — near GitHub's 2 GB per-asset limit. Split by directory-code or year."
    }
}

Write-Host ""
Write-Host "Done."
