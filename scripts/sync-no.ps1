# Downloads Norwegian customs tariff data from the Tolletaten CKAN open data portal.
# Source: https://data.toll.no  —  Licence: CC BY 4.0
param(
    [string]$OutputFolder = "downloads/no",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$CkanBase = "https://data.toll.no/api/3/action"

# Datasets to mirror. customstariffstructure is the primary tariff hierarchy;
# tollkvote adds quota data useful for measure enrichment.
$datasetIds = @(
    "customstariffstructure",
    "tollkvote"
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
        Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
        $downloaded += $filename
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    }
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
