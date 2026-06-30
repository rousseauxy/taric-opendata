# Downloads EU TARIC data from two sources:
#   Monthly XLSX extractions from CIRCABC (European Commission DG TAXUD).
#     Source: https://circabc.europa.eu/ui/group/0e5f18c2-4b2f-42e9-aed4-dfe50ae1263b/library/64db9d0f-e7c9-4084-afe9-f47e70e53c10
#     Access: Alfresco guest authentication (public content, no login required).
#   Daily delta (update) ZIPs from the EC DDS2 TARIC portal.
#     Source: https://ec.europa.eu/taxation_customs/dds2/taric/daily_publications.jsp?Lang=en
#     Rolling ~6-week window; already-downloaded files are skipped.
param(
    [string]$OutputFolder = "downloads/eu",
    [string[]]$SkipFiles  = @(),
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
$monthlyZipName = "eu-taric-$zipMonth.zip"
Write-Host "Syncing CIRCABC TARIC data: $zipMonth ($($monthFolder.Title))"

# ─── Download XLSX files and pack monthly ZIP ─────────────────────────────────

if (-not $Force -and $SkipFiles -contains $monthlyZipName) {
    Write-Host "$monthlyZipName already in release — skipping CIRCABC download."
} else {
    $files = Get-Children $monthFolder.NodeId | Where-Object { $_.MimeType -match 'spreadsheet|excel' }
    if (-not $files) { Write-Host "No XLSX files found in $($monthFolder.Title)"; exit 0 }
    Write-Host "Found $($files.Count) XLSX files"

    $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) "eu-taric-$zipMonth"
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

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zipPath = Join-Path $OutputFolder $monthlyZipName
    $tmpZip  = "$zipPath.tmp"
    if (Test-Path $tmpZip) { Remove-Item $tmpZip }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($tmpDir, $tmpZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    Remove-Item $tmpDir -Recurse -Force
    Move-Item $tmpZip $zipPath -Force

    Write-Host ""
    Write-Host "Downloaded: $count file(s) → $monthlyZipName ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB)"
}

# ─── Daily delta updates ─────────────────────────────────────────────────────

$DailyBase = "https://ec.europa.eu/taxation_customs/dds2/taric"
Write-Host ""
Write-Host "Syncing TARIC daily delta updates..."
$dailyHtml = (Invoke-WebRequest -Uri "$DailyBase/daily_publications.jsp?Lang=en" -UseBasicParsing -UserAgent $UA -TimeoutSec 30).Content

$dailyEntries = [System.Text.RegularExpressions.Regex]::Matches(
    $dailyHtml,
    'publicationDate=(\d{4}-\d{2}-\d{2} \d{2}:\d{2})&(?:amp;)?message=extract'
) | ForEach-Object {
    $pubDate = $_.Groups[1].Value
    $time    = ($pubDate -split ' ')[1] -replace ':', ''
    $day     = ($pubDate -split ' ')[0] -replace '-', ''
    $zipName = "TARIC_${day}_${time}.zip"
    $dlUrl   = "$DailyBase/taric_management.jsp?publicationDate=$([uri]::EscapeDataString($pubDate))&message=extract"
    [PSCustomObject]@{ ZipName = $zipName; Url = $dlUrl; PubDate = $pubDate }
}

Write-Host "Found $($dailyEntries.Count) daily update(s) listed"
$dlCount = 0; $skipCount = 0
foreach ($e in $dailyEntries) {
    $outPath = Join-Path $OutputFolder $e.ZipName
    if (-not $Force -and ($SkipFiles -contains $e.ZipName -or (Test-Path $outPath))) { $skipCount++; continue }
    Write-Host "  $($e.ZipName)  ($($e.PubDate))..." -NoNewline
    Invoke-WebRequest -Uri $e.Url -UserAgent $UA -UseBasicParsing -OutFile $outPath -TimeoutSec 60
    Write-Host " $([math]::Round((Get-Item $outPath).Length / 1KB, 0)) KB"
    $dlCount++
}
if ($skipCount -gt 0) { Write-Host "Skipped (already present): $skipCount" }
Write-Host "Daily deltas downloaded: $dlCount"

# ─── TARIC Business codes & Correlation tables (CIRCABC reference library) ───
# Second CIRCABC library: group 0e5f18c2 / library 90dd4b94-39dd-45f4-8f33-ec9ef9820016
# These nodes only resolve via the CMIS path, not the Atom API used above.

$CmisBase = "https://circabc.europa.eu/service/cmis/s/workspace:SpacesStore/i"

function Get-CircabcChildren($nodeId) {
    $r = Invoke-WebRequest -Uri "$CmisBase/$nodeId/children" -UserAgent $UA -UseBasicParsing -Headers $Headers -TimeoutSec 30
    ([xml]$r.Content).feed.entry | ForEach-Object {
        $href = ($_.link | Where-Object { $_.rel -eq 'self' }).href
        $href -match 'i/([0-9a-f-]{36})' | Out-Null
        [PSCustomObject]@{
            Title    = $_.title.'#text' ?? $_.title
            NodeId   = $matches[1]
            MimeType = $_.content.type
        }
    }
}

Write-Host ""
Write-Host "Syncing TARIC Business codes and Correlation tables..."
$refCount = 0; $refSkip = 0

# Business codes — single library with files at root
foreach ($item in (Get-CircabcChildren '3fdd730a-0988-4b75-bab5-5f416022452c') |
        Where-Object { $_.MimeType -match 'spreadsheet|excel|ms-excel' }) {
    $safeName = $item.Title -replace '[<>:"/\\|?*]', '_'
    $outPath  = Join-Path $OutputFolder $safeName
    if (-not $Force -and ($SkipFiles -contains $safeName -or (Test-Path $outPath))) {
        Write-Host "  Already exists: $safeName"; $refSkip++; continue
    }
    Write-Host "  Downloading: $($item.Title)..."
    Invoke-WebRequest -Uri "$BaseUrl/$($item.NodeId)/content" -UserAgent $UA -UseBasicParsing -Headers $Headers -OutFile $outPath -TimeoutSec 60
    $downloaded += $safeName; $refCount++
    Write-Host "    -> $([math]::Round((Get-Item $outPath).Length / 1KB, 0)) KB"
}

# Correlation tables — walk subfolders (HS-CN-TARIC, Dual use codes, REACH, Sanctions against Russia)
foreach ($folder in (Get-CircabcChildren '3de7201f-51e1-4379-8f45-6cce273e97f0') |
        Where-Object { -not $_.MimeType }) {
    Write-Host "  Subfolder: $($folder.Title)"
    foreach ($item in (Get-CircabcChildren $folder.NodeId) |
            Where-Object { $_.MimeType -match 'spreadsheet|excel|ms-excel' }) {
        $safeName = "$($folder.Title) - $($item.Title)" -replace '[<>:"/\\|?*]', '_'
        $outPath  = Join-Path $OutputFolder $safeName
        if (-not $Force -and ($SkipFiles -contains $safeName -or (Test-Path $outPath))) {
            Write-Host "    Already exists: $safeName"; $refSkip++; continue
        }
        Write-Host "    Downloading: $($item.Title)..."
        Invoke-WebRequest -Uri "$BaseUrl/$($item.NodeId)/content" -UserAgent $UA -UseBasicParsing -Headers $Headers -OutFile $outPath -TimeoutSec 60
        $downloaded += $safeName; $refCount++
        Write-Host "      -> $([math]::Round((Get-Item $outPath).Length / 1KB, 0)) KB"
    }
}

Write-Host "Reference docs downloaded: $refCount (skipped: $refSkip)"
