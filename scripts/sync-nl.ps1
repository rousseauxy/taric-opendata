# Downloads Netherlands DTV (Douane Tarief Voorziening) tariff data.
# Source manifest: https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml
param(
    [string]$OutputFolder = "downloads/nl",
    [string]$Month        = (Get-Date -Format "yyyy-MM"),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$ManifestUrl = "https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml"

Write-Host "Fetching DTV download manifest..."
$manifestContent = Invoke-WebRequest -Uri $ManifestUrl -UseBasicParsing
$xml = [xml]$manifestContent.Content

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

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Host "Already exists: $filename"
        continue
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

Write-Host "Downloaded $($downloaded.Count) new file(s)"
