# Downloads UK Global Tariff data from the DBT Data API.
# Source: https://data.api.trade.gov.uk/v1/datasets/uk-tariff-2021-01-01
param(
    [string]$OutputFolder = "downloads/gb",
    [string[]]$SkipFiles  = @(),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$ApiBase  = "https://data.api.trade.gov.uk/v1/datasets/uk-tariff-2021-01-01"
$tables   = @(
    # Summary / pre-joined report tables
    "commodities-report",
    "measures-on-declarable-commodities",
    "measures-as-defined",

    # Raw commodity tables
    "commodities",
    "commodity-descriptions",
    "commodity-indent-nodes",
    "commodity-indents",
    "commodity-footnotes",
    "commodity-origins",
    "commodity-successors",

    # Measures (raw normalized)
    "measures",
    "measure-components",
    "measure-conditions",
    "measure-condition-components",
    "measure-condition-codes",
    "measure-footnotes",
    "measure-actions",
    "measure-types",
    "measure-type-series",
    "measure-duty-expressions",
    "measure-excluded-geo-areas",
    "measure-additional-code-types",
    "measure-measurements",
    "measure-measurements-units",
    "measure-measurement-qualifiers",
    "measure-monetary-units",

    # Additional codes
    "additional-codes",
    "additional-code-types",
    "additional-code-descriptions",

    # Geographic areas
    "geo-areas",
    "geo-area-descriptions",
    "geo-area-memberships",

    # Footnotes
    "footnotes",
    "footnote-types",
    "footnote-descriptions",

    # Certificates
    "certificates",
    "certificate-types",
    "certificate-descriptions",

    # Quotas
    "quota-order-numbers",
    "quota-definitions",
    "quota-origins",
    "quota-origin-exclusions",
    "quota-associations",
    "quota-blockings",
    "quota-suspensions",

    # Regulations
    "regulations",
    "regulation-groups",
    "regulation-amendments",
    "regulation-replacements",
    "regulation-suspensions"

    # Omitted: common-tracked-models, common-transactions, common-version-groups
    # These are internal TARIC audit/versioning tables (~1.5 GB combined) with no tariff data value.
)

# Resolve the current latest version ID so it can be embedded in filenames.
# The /versions?format=json endpoint returns a list ordered newest-first.
Write-Host "Resolving latest UK tariff version..."
$versionId = "latest"
try {
    $versions = Invoke-RestMethod -Uri "$ApiBase/versions?format=json" -UseBasicParsing
    if ($versions.versions -and $versions.versions.Count -gt 0) {
        $versionId = $versions.versions[0].id
    }
} catch {
    Write-Warning "Could not resolve version ID; filenames will use 'latest'. Error: $_"
}

Write-Host "Version: $versionId"

$downloaded = @()
foreach ($table in $tables) {
    $filename = "$table-$versionId.csv"
    $outPath  = Join-Path $OutputFolder $filename

    if (-not $Force -and ($SkipFiles -contains $filename -or (Test-Path $outPath))) {
        Write-Host "Already exists: $filename"
        continue
    }

    $url = "$ApiBase/versions/latest/tables/$table/data?format=csv&download"
    Write-Host "Downloading: $filename"
    try {
        Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
        $sizeMB = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
        Write-Host "  -> ${sizeMB} MB"
        $downloaded += $filename
    } catch {
        Write-Warning "Failed: $filename — $_"
        if (Test-Path $outPath) { Remove-Item $outPath }
    }
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
