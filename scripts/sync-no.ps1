# Downloads Norwegian customs tariff data from the Tolletaten CKAN open data portal.
# Source: https://data.toll.no  —  Licence: CC BY 4.0
#
# Filenames are stable (no date or version), so the release is refreshed in place —
# there is deliberately no "already in the release, skip it" path: that would freeze
# the mirror at the first run of each month.
param(
    [string]$OutputFolder = "downloads/no",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force

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
    $pkg = Invoke-WithRetry -What "CKAN $id" -Action {
        Invoke-RestMethod -Uri "$CkanBase/package_show?id=$id" -UseBasicParsing -TimeoutSec 60
    }

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
        # Retries, then throws. It used to warn and carry on, which is worse than it sounds here:
        # the publish step uploads whatever is in the folder with --clobber and leaves every other
        # release asset alone, so a skipped file is not absent from the release, it is SILENTLY
        # STALE — and the content-keyed freshness marker then sees it unchanged and does not
        # re-import it. That is the "reported success while publishing nothing" family this
        # pipeline has already produced four times.
        Invoke-Download -Uri $url -OutFile $outPath -What $filename
        $downloaded += $filename
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    }
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
