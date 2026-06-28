# Downloads EU TARIC data from CIRCABC (European Commission DG TAXUD).
# Source: https://circabc.europa.eu/ui/group/0e5f18c2-4b2f-42e9-aed4-dfe50ae1263b/library/64db9d0f-e7c9-4084-afe9-f47e70e53c10
# Monthly XLSX extractions: nomenclature, duties, measures, geographical areas, exchange rates, etc.
# Access: Alfresco guest authentication (public content, no login required).
param(
    [string]$OutputFolder = "downloads/eu",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$TaricDataFolderId = "64db9d0f-e7c9-4084-afe9-f47e70e53c10"
$BaseUrl = "https://circabc.europa.eu/service/api/node/workspace/SpacesStore"
$UA      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
$Headers = @{ Authorization = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes('guest:')))" }

function Get-Children($nodeId) {
    $r = Invoke-WebRequest -Uri "$BaseUrl/$nodeId/children" -UserAgent $UA -UseBasicParsing -Headers $Headers -TimeoutSec 30
    ([xml]$r.Content).feed.entry | ForEach-Object {
        $cmis = ($_.link | Where-Object { $_.rel -eq 'self' }).href
        [PSCustomObject]@{
            Title    = $_.title.'#text' ?? $_.title
            NodeId   = if ($cmis -match 'SpacesStore/i/([0-9a-f-]{36})') { $matches[1] } else { $null }
            MimeType = $_.content.type
        }
    }
}

# ─── Navigate to latest year / month ─────────────────────────────────────────

$yearStr  = (Get-Date).Year.ToString()
$monthNum = (Get-Date -Format 'MM')

$yearFolder = Get-Children $TaricDataFolderId | Where-Object { $_.Title -eq $yearStr } | Select-Object -First 1
if (-not $yearFolder) {
    $yearFolder = Get-Children $TaricDataFolderId |
        Where-Object { $_.Title -match '^\d{4}$' -and -not $_.MimeType } |
        Sort-Object Title -Descending | Select-Object -First 1
    Write-Host "Year $yearStr not in CIRCABC yet — using $($yearFolder.Title)"
    $yearStr = $yearFolder.Title
}

$months     = Get-Children $yearFolder.NodeId
$monthFolder = $months | Where-Object { $_.Title -match "^$monthNum " } | Select-Object -First 1
if (-not $monthFolder) {
    $monthFolder = $months | Where-Object { -not $_.MimeType } | Sort-Object Title -Descending | Select-Object -First 1
    Write-Host "Month $monthNum not in CIRCABC yet — using $($monthFolder.Title)"
}

$monthNum = $monthFolder.Title.Substring(0, 2)   # "06" from "06 - June"
$zipMonth = "$yearStr-$monthNum"                  # "2026-06"
Write-Host "Syncing CIRCABC TARIC data: $zipMonth ($($monthFolder.Title))"

# ─── Download XLSX files ──────────────────────────────────────────────────────

$files = Get-Children $monthFolder.NodeId | Where-Object { $_.MimeType -match 'spreadsheet|excel' }
if (-not $files) { Write-Host "No XLSX files found in $($monthFolder.Title)"; exit 0 }
Write-Host "Found $($files.Count) XLSX files"

$tmpDir  = Join-Path ([System.IO.Path]::GetTempPath()) "eu-taric-$zipMonth"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$count = 0
foreach ($f in $files) {
    $safeName = $f.Title -replace '[<>:"/\\|?*]', '_'
    $outPath  = Join-Path $tmpDir $safeName
    Write-Host "  $($f.Title)..." -NoNewline
    Invoke-WebRequest -Uri "$BaseUrl/$($f.NodeId)/content" -UserAgent $UA -UseBasicParsing -Headers $Headers `
        -OutFile $outPath -TimeoutSec 120
    Write-Host " $([math]::Round((Get-Item $outPath).Length / 1KB, 0)) KB"
    $count++
}

# ─── Pack into ZIP and check for changes ─────────────────────────────────────

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipName   = "eu-taric-$zipMonth.zip"
$zipPath   = Join-Path $OutputFolder $zipName
$hashFile  = Join-Path $OutputFolder "eu-taric-$zipMonth.sha256"
$tmpZip    = "$zipPath.tmp"

if (Test-Path $tmpZip) { Remove-Item $tmpZip }
[System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $tmpZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
Remove-Item $tmpDir -Recurse -Force

$newHash = (Get-FileHash $tmpZip -Algorithm SHA256).Hash

if (-not $Force -and (Test-Path $hashFile) -and (Get-Content $hashFile -Raw).Trim() -eq $newHash) {
    Remove-Item $tmpZip
    Write-Host "No change detected (SHA256 match) — nothing to upload."
    exit 0
}

Move-Item $tmpZip $zipPath -Force
Set-Content $hashFile $newHash -NoNewline

Write-Host ""
Write-Host "Downloaded: $count file(s) → $zipName ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB)"
