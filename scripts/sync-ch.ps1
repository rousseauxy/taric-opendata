# Downloads Swiss Customs (BAZG) tariff master data from the public datahub.
# Source: https://datahub.bazg.admin.ch/public-resources/
# Files are ZIP-compressed XML, updated daily. No authentication required.
# Uses ETag headers to skip unchanged files on re-runs.
param(
    [string]$OutputFolder = "downloads/ch",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$DatahubBase = "https://datahub.bazg.admin.ch/public-resources"

# All publicly available BAZG tariff master data files.
# TariffMasterData includes duty rates (Swiss national + EU-harmonised measures).
$files = @(
    "TariffMasterData_v6.zip",         # Full tariff master data incl. duty rates (latest schema)
    "TariffBaseMasterData_v2.zip",     # Base tariff data
    "TariffsTree_v1.zip",              # Commodity tree structure
    "CountryCodes_v3.zip",             # Country code reference
    "PassarCodelists_v1.zip",          # Passar system code lists
    "PassarTaxudCodelists_v1.zip"      # EU TAXUD customs office code lists
)

$downloaded = @()
$skipped    = @()

foreach ($fileName in $files) {
    $url      = "$DatahubBase/$fileName"
    $outPath  = Join-Path $OutputFolder $fileName
    $etagPath = Join-Path $OutputFolder "$fileName.etag"

    # ETag-based change detection: skip download if server file is unchanged
    if (-not $Force -and (Test-Path $outPath) -and (Test-Path $etagPath)) {
        $storedEtag = Get-Content $etagPath -Raw
        try {
            $head = Invoke-WebRequest -Uri $url -Method Head -UseBasicParsing -MaximumRedirection 5
            $currentEtag = ($head.Headers['ETag'] | Select-Object -First 1)
            if ($currentEtag -and $currentEtag -eq $storedEtag.Trim()) {
                Write-Host "Unchanged: $fileName"
                $skipped += $fileName
                continue
            }
        } catch { }
    }

    Write-Host "Downloading $fileName..."
    try {
        $r = Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing -MaximumRedirection 5 -PassThru
        $etag = ($r.Headers['ETag'] | Select-Object -First 1)
        if ($etag) { $etag | Set-Content $etagPath }
        $downloaded += $fileName
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    } catch {
        Write-Warning "Failed: $fileName — $_"
        if (Test-Path $outPath) { Remove-Item $outPath }
    }
}

Write-Host ""
Write-Host "Downloaded: $($downloaded.Count) file(s)"
if ($skipped.Count -gt 0) { Write-Host "Unchanged (skipped): $($skipped.Count)" }
