# Downloads UK Global Tariff data from the DBT Data API.
# Source: https://data.api.trade.gov.uk/v1/datasets/uk-tariff-2021-01-01
param(
    [string]$OutputFolder = "downloads/gb",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$ApiBase  = "https://data.api.trade.gov.uk/v1/datasets/uk-tariff-2021-01-01"
$tables   = @(
    "commodities",
    "measures-on-declarable-commodities",
    "measures-as-defined"
)

# Resolve the current latest version ID so it can be embedded in filenames.
Write-Host "Resolving latest UK tariff version..."
$versionId = "latest"
try {
    $meta = Invoke-RestMethod -Uri "$ApiBase/versions/latest/metadata?format=json" -UseBasicParsing
    if ($meta.version_id) { $versionId = $meta.version_id }
    elseif ($meta.id)     { $versionId = $meta.id }
} catch {
    Write-Warning "Could not resolve version ID; filenames will use 'latest'. Error: $_"
}

Write-Host "Version: $versionId"

$downloaded = @()
foreach ($table in $tables) {
    $filename = "$table-$versionId.csv"
    $outPath  = Join-Path $OutputFolder $filename

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Host "Already exists: $filename"
        continue
    }

    $url = "$ApiBase/versions/latest/tables/$table/data?format=csv&download"
    Write-Host "Downloading: $filename"
    Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
    $sizeMB = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
    Write-Host "  -> ${sizeMB} MB"
    $downloaded += $filename
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
