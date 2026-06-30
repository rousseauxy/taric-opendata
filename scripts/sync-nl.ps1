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
