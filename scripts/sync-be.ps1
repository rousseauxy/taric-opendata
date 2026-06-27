# Mirrors Belgium Tarbel data from tarbel-opendata GitHub releases.
# Source: https://github.com/rousseauxy/tarbel-opendata
param(
    [string]$OutputFolder = "downloads/be",
    [string]$SourceRepo   = "rousseauxy/tarbel-opendata",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$tag = (Get-Date -Format "yyyy-MM")
$apiUrl = "https://api.github.com/repos/$SourceRepo/releases/tags/$tag"

Write-Host "Fetching release $tag from $SourceRepo..."
try {
    $release = Invoke-RestMethod -Uri $apiUrl -Headers @{
        Accept       = "application/vnd.github.v3+json"
        "User-Agent" = "taric-opendata-sync"
    }
} catch {
    Write-Warning "No release found for tag '$tag' in $SourceRepo. Nothing to mirror."
    exit 0
}

if (-not $release.assets -or $release.assets.Count -eq 0) {
    Write-Host "Release $tag exists but has no assets yet. Skipping."
    exit 0
}

$downloaded = @()
foreach ($asset in $release.assets) {
    $outPath = Join-Path $OutputFolder $asset.name

    if ((Test-Path $outPath) -and -not $Force) {
        Write-Host "Already exists: $($asset.name)"
        continue
    }

    Write-Host "Downloading: $($asset.name) ($([math]::Round($asset.size / 1KB)) KB)"
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $outPath -UseBasicParsing
    $downloaded += $asset.name
}

Write-Host "Mirrored $($downloaded.Count) new file(s) from $SourceRepo@$tag"
