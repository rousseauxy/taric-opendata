# Downloads Netherlands DTV (Douane Tarief Voorziening) tariff data.
# Source manifest: https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml
param(
    [string]$OutputFolder = "downloads/nl",
    [string]$Month        = (Get-Date -Format "yyyy-MM"),
    [string[]]$SkipFiles  = @(),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$ManifestUrl = "https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml"

$curlHeaders = @(
    "-H", "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36",
    "-H", "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "-H", "Accept-Language: nl-NL,nl;q=0.9,en-US;q=0.8,en;q=0.7",
    "-H", "Referer: https://www.belastingdienst.nl/"
)

Write-Host "Fetching DTV download manifest..."
$manifestText = curl -fsSL @curlHeaders $ManifestUrl
if ($LASTEXITCODE -ne 0) { throw "curl failed fetching manifest (exit $LASTEXITCODE)" }
$xml = [xml]$manifestText

# Save raw manifest for traceability
$xml.Save((Join-Path $OutputFolder "manifest.xml"))

# Extract download URLs from the manifest using the known <download><url> structure.
# The month filter maps "yyyy-MM" → "yyyy_MM" to match the filename date prefix.
$monthPrefix = $Month -replace '-', '_'
$urls = $xml.SelectNodes("//download/url") |
    ForEach-Object { $_.InnerText.Trim() } |
    Where-Object { $_ -match [regex]::Escape($monthPrefix) }

if ($urls.Count -eq 0) {
    Write-Warning "No files found in manifest for month '$Month'. Inspect $OutputFolder/manifest.xml to check availability."
    exit 1
}

Write-Host "Found $($urls.Count) file(s) in manifest for $Month"

# A month's release must carry a full snapshot. DTV republishes the ~240 MB full weekly and the
# daily incrementals only replay on top of one, so in the first days of a month - before the
# first weekly full lands - the month's files are incrementals alone. Published as they were, the
# consumer sees a release with no full in it: TaricHive prunes its download directory to the
# current release's assets, opened the largest zip it had left (a 30 KB incremental) as the full,
# and served the Netherlands with zero measures for three days (2026-09-02..05). Carrying the
# newest earlier full forward makes every release self-contained. The manifest does not mark
# fulls and the names have the same shape, so a full is recognised by size (Content-Length).
$fullThreshold = 50MB
function Get-RemoteLength([string]$u) {
    $head = curl -sI @curlHeaders $u
    if ($LASTEXITCODE -ne 0) { return 0 }
    $m = [regex]::Match(($head -join "`n"), '(?im)^content-length:\s*(\d+)')
    if ($m.Success) { return [long]$m.Groups[1].Value } else { return 0 }
}
$hasFull = $false
foreach ($u in $urls) {
    if ((Get-RemoteLength $u) -ge $fullThreshold) { $hasFull = $true; break }
}
if (-not $hasFull) {
    $earlier = $xml.SelectNodes("//download/url") |
        ForEach-Object { $_.InnerText.Trim() } |
        Where-Object { $_ -notmatch [regex]::Escape($monthPrefix) } |
        Sort-Object -Descending
    foreach ($u in $earlier) {
        if ((Get-RemoteLength $u) -ge $fullThreshold) {
            Write-Host "No full snapshot in $Month yet - carrying forward $(($u -split '[?#]')[0] | Split-Path -Leaf)"
            $urls = @($u) + @($urls)
            break
        }
    }
    if (-not $hasFull -and $urls.Count -gt 0 -and (Get-RemoteLength $urls[0]) -lt $fullThreshold) {
        Write-Warning "No full snapshot found in the manifest at all; the release will hold incrementals only."
    }
}

$downloaded = @()
foreach ($url in $urls) {
    $filename = ($url -split '[?#]')[0] | Split-Path -Leaf
    $outPath  = Join-Path $OutputFolder $filename

    if (-not $Force -and ($SkipFiles -contains $filename -or (Test-Path $outPath))) {
        Write-Host "Already exists: $filename"
        continue
    }

    Write-Host "Downloading: $filename"
    curl -fsSL @curlHeaders -o $outPath $url
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Failed: $filename (curl exit $LASTEXITCODE)"
        if (Test-Path $outPath) { Remove-Item $outPath }
    } else {
        $downloaded += $filename
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    }
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
