# Downloads Norwegian customs tariff data from the Tolletaten CKAN open data portal.
# Source: https://data.toll.no  —  Licence: CC BY 4.0
param(
    [string]$OutputFolder = "downloads/no",
    [string[]]$SkipFiles  = @(),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$CkanBase = "https://data.toll.no/api/3/action"

# All datasets published by Tolletaten on data.toll.no (CC BY 4.0).
$datasetIds = @(
    # Tariff structure & commodity numbers
    "customstariffstructure",
    "tolltariffstruktur",
    "varenummer",
    "datogyldighetforvare",

    # Duty rates
    "tollavgiftssats",
    "innfoerselsavgift",
    "raavaretollavgiftssats",
    "tilleggstollavgiftssats",
    "ratetradeagreements",
    "utfoerselsavgift",

    # Quotas & concessions
    "tollkvote",
    "boundtariffconcessions",
    "lettelse",

    # Restrictions & references
    "innfoerselsrestriksjon",
    "innfoerselsreferanse",
    "utfoerselsrestriksjon",
    "utfoerselsreferanse",
    "henvisning",
    "reference",

    # Classification & lookup
    "landgruppe",
    "medlemsland",
    "prosedyrekode",
    "typetilfelle",
    "ekspedisjonsenhet",
    "feilmelding",

    # Exchange rates
    "valutakurs",
    "valutakurs_historisk"
)

$downloaded = @()
foreach ($id in $datasetIds) {
    Write-Host "Fetching CKAN package: $id"
    $pkg = Invoke-RestMethod -Uri "$CkanBase/package_show?id=$id" -UseBasicParsing

    if (-not $pkg.success) {
        Write-Warning "CKAN returned failure for package '$id'. Skipping."
        continue
    }

    foreach ($resource in $pkg.result.resources) {
        $url = $resource.url
        if (-not $url) { continue }

        # Build a clean filename: {dataset}-{resource-name}.{ext}
        $ext      = if ($url -match '\.(\w+)(\?|$)') { $matches[1] } else { "bin" }
        $resName  = ($resource.name -replace '[^\w\-]', '_').ToLower()
        $filename = "$id-$resName.$ext"
        $outPath  = Join-Path $OutputFolder $filename

        if (-not $Force -and $SkipFiles -contains $filename) {
            Write-Host "Up to date (in release): $filename"
            continue
        }

        if ((Test-Path $outPath) -and -not $Force) {
            # Skip if local copy is at least as recent as the remote resource.
            $localDate  = (Get-Item $outPath).LastWriteTimeUtc
            $remoteDate = try { [datetime]::Parse($resource.last_modified ?? $resource.created) } catch { [datetime]::MinValue }
            if ($localDate -ge $remoteDate) {
                Write-Host "Up to date: $filename"
                continue
            }
        }

        Write-Host "Downloading: $filename"
        try {
            Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
            $downloaded += $filename
            Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
        } catch {
            Write-Warning "Failed: $filename — $_"
            if (Test-Path $outPath) { Remove-Item $outPath }
        }
    }
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
