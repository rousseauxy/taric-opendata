# Mirrors DG TAXUD's CS/RD2 reference data — the lists every national customs application
# validates against.
#
# Source: https://ec.europa.eu/taxation_customs/dds2/rd/
#
#   COL-Generic-{yyyyMMdd}.zip   the Customs Office List, all member states + common transit
#   RD-Generic-{yyyyMMdd}.zip    every reference code list, as nine per-domain ZIPs
#
# WHY: the code lists shipped inside CustomsHive were a 2022 photograph. Italy renumbered its
# Trieste offices since, so a real office of exit (IT322102) could not be validated; and the
# AdditionsDeductions list gained CA and FA on 2026-05-26, two codes we file every week and
# could not confirm. A still photograph of a moving list is wrong in both directions — missing
# codes that exist, offering codes that no longer do.
#
# THE DATE IN THE URL IS A SNAPSHOT DATE, NOT A FILE NAME. The service generates the extract on
# demand at whatever date you ask for, and answers 200 for a date that has not happened yet:
# COL-Generic-20991231.zip is a valid request. So there is nothing to HEAD and no listing to
# scrape — "has it moved" cannot be asked, only answered after the fact. Change detection is
# therefore a hash of what came back, which is cheap here (33 MB, against EBTI's 390 MB).
#
# The same property is worth remembering the other way round: asking for a past date returns the
# lists as they stood then, which is how a historical declaration's codes could be explained.
param(
    [string]$OutputFolder = "downloads/csrd2",
    # Defaults to today (UTC). Pass a past date to pull a historical snapshot.
    [string]$SnapshotDate = (Get-Date).ToUniversalTime().ToString('yyyyMMdd'),
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem

$UA      = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"
$BaseUrl = "https://ec.europa.eu/taxation_customs/dds2/rd/compressed_file/data_download"

if ($SnapshotDate -notmatch '^\d{8}$') {
    throw "SnapshotDate must be yyyyMMdd, got '$SnapshotDate'."
}

# Published under stable names so a consumer does not have to guess today's date to find the
# asset. The snapshot date it was taken at is recorded in csrd2-version.txt beside them, and is
# also carried inside the XML itself.
$downloads = @(
    @{ Prefix = 'COL'; Asset = 'COL-Generic.zip'; MinBytes = 500KB; Entry = 'COL-Generic-*.xml' }
    @{ Prefix = 'RD';  Asset = 'RD-Generic.zip';  MinBytes = 10MB;  Entry = 'RD_*.zip' }
)

# ─── Download ─────────────────────────────────────────────────────────────────

$hashes = [ordered]@{}

foreach ($d in $downloads) {
    $url  = "$BaseUrl/$($d.Prefix)-Generic-$SnapshotDate.zip"
    $tmp  = Join-Path $OutputFolder "$($d.Asset).tmp"

    Write-Host "Downloading $($d.Prefix)-Generic-$SnapshotDate.zip..."
    Invoke-Download -Uri $url -OutFile $tmp -What "CS/RD2 $($d.Prefix)" -UserAgent $UA -TimeoutSec 600

    # Three checks, because the endpoint answers 200 to anything. A size floor catches an error
    # page served as a download; the magic bytes catch an HTML body with a plausible length; and
    # opening the archive catches a truncation that leaves the header intact — the case a size
    # check alone waves through.
    $size = (Get-Item $tmp).Length
    if ($size -lt $d.MinBytes) {
        Remove-Item $tmp -Force
        throw "$($d.Prefix) download is $size bytes, under the $($d.MinBytes) floor — an error response, not an extract."
    }

    $magic = [System.IO.File]::ReadAllBytes($tmp)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        Remove-Item $tmp -Force
        throw "$($d.Prefix) download is not a ZIP (magic: $($magic -join ' '))."
    }

    $names = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        try { $names = @($zip.Entries | ForEach-Object { $_.Name }) } finally { $zip.Dispose() }
    }
    catch {
        Remove-Item $tmp -Force
        throw "$($d.Prefix) download will not open as a ZIP — $($_.Exception.Message)"
    }

    if (-not ($names | Where-Object { $_ -like $d.Entry })) {
        Remove-Item $tmp -Force
        throw "$($d.Prefix) archive holds no entry matching '$($d.Entry)' — got: $($names -join ', ')"
    }

    $hashes[$d.Prefix] = (Get-FileHash $tmp -Algorithm SHA256).Hash
    Write-Host "  $([math]::Round($size / 1MB, 1)) MB, $($names.Count) entr$(if ($names.Count -eq 1) { 'y' } else { 'ies' })"

    $final = Join-Path $OutputFolder $d.Asset
    if (Test-Path $final) { Remove-Item $final -Force }
    Move-Item $tmp $final
}

# ─── Change detection ─────────────────────────────────────────────────────────
#
# After the download rather than before it: see the header. The extract is regenerated daily but
# its contents move only when a code list actually changes, so most days both hashes match and
# there is nothing worth publishing.

$versionFile = Join-Path $OutputFolder "csrd2-version.txt"
$marker = "snapshot=$SnapshotDate`ncol=$($hashes['COL'])`nrd=$($hashes['RD'])"

if (-not $Force -and (Test-Path $versionFile)) {
    $stored = (Get-Content $versionFile -Raw)
    # The snapshot date moves every day and the hashes do not, so it is deliberately not compared.
    $storedHashes = ($stored -split "`n" | Where-Object { $_ -match '^(col|rd)=' }) -join "`n"
    $freshHashes  = ($marker -split "`n" | Where-Object { $_ -match '^(col|rd)=' }) -join "`n"

    if ($storedHashes.Trim() -eq $freshHashes.Trim()) {
        Write-Host "CS/RD2 unchanged since the last run — nothing to publish."
        # The workflow publishes on the presence of the marker file, so it is removed rather than
        # left holding a date that would be republished with identical assets.
        Remove-Item (Join-Path $OutputFolder 'COL-Generic.zip') -Force
        Remove-Item (Join-Path $OutputFolder 'RD-Generic.zip')  -Force
        exit 0
    }
    Write-Host "CS/RD2 content changed since the last run."
}

$marker | Set-Content $versionFile -NoNewline

Write-Host "CS/RD2 snapshot $SnapshotDate ready to publish:"
Write-Host "  COL-Generic.zip  $($hashes['COL'].Substring(0, 16))..."
Write-Host "  RD-Generic.zip   $($hashes['RD'].Substring(0, 16))..."
