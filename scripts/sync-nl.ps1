# Downloads Netherlands DTV (Douane Tarief Voorziening) tariff data.
# Source manifest: https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml
param(
    [string]$OutputFolder = "downloads/nl",
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

# Collect all download URLs from the manifest.
# The DTV manifest contains elements with url/href attributes or text content URLs.
$urls = @()
$xml.SelectNodes("//*") | ForEach-Object {
    foreach ($attr in $_.Attributes) {
        if ($attr.Value -match "^https?://" -and $attr.Value -match "\.(zip|xml|gz)") {
            $urls += $attr.Value
        }
    }
    if ($_.InnerText -match "^https?://" -and $_.InnerText -match "\.(zip|xml|gz)") {
        $urls += $_.InnerText.Trim()
    }
}
$urls = $urls | Select-Object -Unique

if ($urls.Count -eq 0) {
    Write-Warning "No download URLs found in manifest. Inspect $OutputFolder/manifest.xml to determine the correct structure."
    exit 1
}

Write-Host "Found $($urls.Count) file(s) in manifest"

$downloaded = @()
foreach ($url in $urls) {
    $filename = ($url -split '[?#]')[0] | Split-Path -Leaf
    $outPath  = Join-Path $OutputFolder $filename

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Host "Already exists: $filename"
        continue
    }

    Write-Host "Downloading: $filename"
    Invoke-WebRequest -Uri $url -OutFile $outPath -UseBasicParsing
    $downloaded += $filename
    Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
}

Write-Host "Downloaded $($downloaded.Count) new file(s)"
