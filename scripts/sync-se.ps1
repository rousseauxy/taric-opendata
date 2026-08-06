# Downloads Swedish Customs Tariff (Tulltaxan) full snapshot from Tullverket's Tariff File Distribution.
# Source: https://distr.tullverket.se/tulltaxan/xml/tot/
# Files are PGP ASCII-armored with a DEFLATE-compressed payload containing gzipped XML.
# Despite the .pgp extension, there is no encryption — we unpack to .xml.gz without any key.
param(
    [string]$OutputFolder = "downloads/se",
    [string[]]$SkipFiles  = @(),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$TotUrl = "https://distr.tullverket.se/tulltaxan/xml/tot"
$DifUrl = "https://distr.tullverket.se/tulltaxan/xml/dif"

function ConvertFrom-PgpToGzip {
    param([string]$PgpAsciiArmor)

    # Extract base64 body between PGP header/footer lines
    $lines = $PgpAsciiArmor -split "`n"
    $b64   = ($lines | Where-Object {
        $_ -notmatch '^-----' -and
        $_ -notmatch '^Version:' -and
        $_ -ne '' -and
        $_ -notmatch '^='
    }) -join ''
    $raw = [Convert]::FromBase64String($b64.Trim())

    # Outer packet: Compressed Data (tag 8, old-format indeterminate length)
    # byte[0] = packet tag, byte[1] = compression algo (1 = ZIP/DEFLATE)
    $deflatePayload = $raw[2..($raw.Length - 1)]

    $inStream  = New-Object System.IO.MemoryStream (, [byte[]]$deflatePayload)
    $deflate   = New-Object System.IO.Compression.DeflateStream($inStream, [System.IO.Compression.CompressionMode]::Decompress)
    $inner     = New-Object System.IO.MemoryStream
    $deflate.CopyTo($inner)
    $deflate.Dispose()
    $innerBytes = $inner.ToArray()

    # Find gzip magic (0x1F 0x8B) — starts inside a PGP Literal Data packet header
    $gzStart = -1
    for ($i = 0; $i -lt $innerBytes.Length - 1; $i++) {
        if ($innerBytes[$i] -eq 0x1F -and $innerBytes[$i + 1] -eq 0x8B) { $gzStart = $i; break }
    }
    if ($gzStart -lt 0) { throw "No gzip magic found in decompressed PGP payload" }

    return $innerBytes[$gzStart..($innerBytes.Length - 1)]
}

# Tullverket publishes two directories, and we only ever mirrored one.
#
#   tot/  full snapshots, refreshed about MONTHLY — currently 33 types × 2 dates
#   dif/  daily IncrementalObjectTraderExport files, the same format NL's incrementals use
#
# Taking only tot/ left the Swedish tariff up to a month stale, with the updates that would
# have closed the gap sitting published and unread. TaricHive's SeImporter now replays the
# incrementals on top of the newest full, exactly as NlImporter does.
Write-Host "Listing full-snapshot files from $TotUrl/"
$listing   = Invoke-WebRequest -Uri "$TotUrl/" -UseBasicParsing -AllowInsecureRedirect -MaximumRedirection 10
$fileNames = @($listing.Links | Select-Object -ExpandProperty href | Where-Object { $_ -like '*.xml.gz.pgp' })
Write-Host "Found $($fileNames.Count) full-snapshot file(s)"

Write-Host "Listing daily incrementals from $DifUrl/"
try {
    $difListing = Invoke-WebRequest -Uri "$DifUrl/" -UseBasicParsing -AllowInsecureRedirect -MaximumRedirection 10
    $difNames   = @($difListing.Links | Select-Object -ExpandProperty href | Where-Object { $_ -like '*.xml.gz.pgp' })
    Write-Host "Found $($difNames.Count) incremental file(s)"
}
catch {
    # Non-fatal: the full snapshot is the critical output and the importer tolerates having no
    # incrementals to replay. Losing dif/ costs freshness, not correctness.
    Write-Warning "Could not list $DifUrl/ — continuing with the full snapshot only: $_"
    $difNames = @()
}

$downloaded = @()
$skipped    = @()

# Both directories carry the date in the filename (…_260803.xml.gz.pgp), so an asset already
# in the release really is an immutable snapshot and the skip is safe — unlike the EU and PL
# cases, where a constant name made the same guard freeze the mirror.
foreach ($set in @(
    @{ Name = 'full';        BaseUrl = $TotUrl; Files = $fileNames },
    @{ Name = 'incremental'; BaseUrl = $DifUrl; Files = $difNames  }
)) {
    foreach ($fileName in $set.Files) {
        $outName = $fileName -replace '\.pgp$', ''   # strip .pgp → keep as .xml.gz
        $outPath = Join-Path $OutputFolder $outName

        if (-not $Force -and ($SkipFiles -contains $outName -or (Test-Path $outPath))) {
            $skipped += $outName
            Write-Host "Already exists: $outName"
            continue
        }

        $url = "$($set.BaseUrl)/$fileName"
        Write-Host "Downloading $($set.Name): $fileName..."
        try {
            $r = Invoke-WebRequest -Uri $url -UseBasicParsing -AllowInsecureRedirect -MaximumRedirection 5
            $pgpText = [System.Text.Encoding]::ASCII.GetString($r.Content)
            $gzBytes = ConvertFrom-PgpToGzip -PgpAsciiArmor $pgpText
            [System.IO.File]::WriteAllBytes($outPath, $gzBytes)
            $downloaded += $outName
            Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
        } catch {
            Write-Warning "Failed: $fileName — $_"
            if (Test-Path $outPath) { Remove-Item $outPath }
        }
    }
}

Write-Host ""
Write-Host "Downloaded: $($downloaded.Count) new file(s)"
if ($skipped.Count -gt 0) { Write-Host "Skipped (already exist): $($skipped.Count)" }
