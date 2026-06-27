# Downloads Swedish Customs Tariff (Tulltaxan) full snapshot from Tullverket's Tariff File Distribution.
# Source: https://distr.tullverket.se/tulltaxan/xml/tot/
# Files are PGP ASCII-armored with a DEFLATE-compressed payload containing gzipped XML.
# Despite the .pgp extension, there is no encryption — we unpack to .xml.gz without any key.
param(
    [string]$OutputFolder = "downloads/se",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$TotUrl = "https://distr.tullverket.se/tulltaxan/xml/tot"

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

Write-Host "Listing full-snapshot files from $TotUrl/"
$listing   = Invoke-WebRequest -Uri "$TotUrl/" -UseBasicParsing -AllowInsecureRedirect -MaximumRedirection 10
$fileNames = $listing.Links | Select-Object -ExpandProperty href | Where-Object { $_ -like '*.xml.gz.pgp' }
Write-Host "Found $($fileNames.Count) files"

$downloaded = @()
$skipped    = @()

foreach ($fileName in $fileNames) {
    $outName = $fileName -replace '\.pgp$', ''   # strip .pgp → keep as .xml.gz
    $outPath = Join-Path $OutputFolder $outName

    if (-not $Force -and (Test-Path $outPath)) {
        $skipped += $outName
        Write-Host "Already exists: $outName"
        continue
    }

    $url = "$TotUrl/$fileName"
    Write-Host "Downloading $fileName..."
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

Write-Host ""
Write-Host "Downloaded: $($downloaded.Count) new file(s)"
if ($skipped.Count -gt 0) { Write-Host "Skipped (already exist): $($skipped.Count)" }
