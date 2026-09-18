# Mirrors the Belgian IDMS technical documentation — the rules and code lists the import system
# (IDMS, PLDA's successor) validates a declaration against.
#
# Source: https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/idms/all
#
#   <date>_IDMS_VRE.xlsx      the validation rules: active, inactive, temporarily blocking
#   <date>_codelist.xlsx      IDMS's own filtered copy of the code lists
#   <date>-idms-xsd.zip       the message XSDs (IE413B/415B/428B/429B)
#
# WHY: the rules a declaration generator follows were read from a PDF that stopped moving in May
# 2024, while the workbook beside it kept changing — by 2026-09-08 it had switched off BE0211 and
# BE0212, capped a declaration at 999 items in the XSD, and added "a supplementary unit cannot be
# 0". None of that is announced; the file is simply replaced. A copy taken once is wrong within
# months, in both directions.
#
# THE FILE NAMES CARRY THE DATE, AND THE FORMAT OF THE DATE IS NOT FIXED. Mostly yymmdd
# (260908_IDMS_VRE.xlsx), but the page also links 09042025_IDMS_VRE.xlsx (ddmmyyyy) and
# 20230922 IDMS_XSD.zip (yyyymmdd), and keeps every old edition linked in its archive section. So
# the page is read for links, each is dated from its own name, and the newest of each kind wins —
# never the first match, which on this page is an archived one.
param(
    [string]$OutputFolder = "downloads/be-idms",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem

$UA      = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"
$Site    = "https://financien.belgium.be"
$PageUrl = "$Site/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/idms/all"

# Asset = the stable name it is published under, so a consumer never has to know today's date.
# Entry = something the archive must contain (an .xlsx is a ZIP too), which is what tells a real
# file from an error page that happens to be the right size.
$kinds = @(
    @{ Kind = 'VRE';      Pattern = '_IDMS_VRE[^/]*\.xlsx$';   Asset = 'IDMS_VRE.xlsx';      MinBytes = 50KB;  Entry = 'workbook.xml' }
    @{ Kind = 'codelist'; Pattern = '_codelist\.xlsx$';        Asset = 'IDMS_codelist.xlsx'; MinBytes = 100KB; Entry = 'workbook.xml' }
    @{ Kind = 'XSD';      Pattern = 'idms[-_ ]xsd\.zip$';      Asset = 'IDMS_XSD.zip';       MinBytes = 2KB;   Entry = 'IE415B.xsd' }
)

# ─── Read the page ────────────────────────────────────────────────────────────

function Get-EditionDate([string]$fileName) {
    # yymmdd, ddmmyyyy or yyyymmdd at the start of the name; null when it carries none.
    if ($fileName -match '^(\d{8})') {
        $d = $Matches[1]
        $fmt = if ($d.StartsWith('20')) { 'yyyyMMdd' } else { 'ddMMyyyy' }
    }
    elseif ($fileName -match '^(\d{6})') { $d = $Matches[1]; $fmt = 'yyMMdd' }
    else { return $null }
    try { return [datetime]::ParseExact($d, $fmt, [Globalization.CultureInfo]::InvariantCulture) }
    catch { return $null }
}

Write-Host "Reading $PageUrl"
$page = Invoke-WithRetry -What "IDMS documentation page" -Action {
    Invoke-WebRequest -Uri $PageUrl -UseBasicParsing -UserAgent $UA -TimeoutSec 60
}
$hrefs = [regex]::Matches($page.Content, 'href="([^"]+\.(?:xlsx|zip))"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique

$picked = @{}
foreach ($k in $kinds) {
    $candidates = foreach ($h in $hrefs) {
        $name = [uri]::UnescapeDataString(($h -split '/')[-1])
        if ($name -notmatch $k.Pattern) { continue }
        $date = Get-EditionDate $name
        if ($date) { [pscustomobject]@{ Href = $h; Name = $name; Date = $date } }
    }
    $newest = @($candidates) | Sort-Object Date -Descending | Select-Object -First 1
    if (-not $newest) {
        throw "No $($k.Kind) link on the page (pattern '$($k.Pattern)') — the page changed shape."
    }
    $picked[$k.Kind] = $newest
    Write-Host ("  {0,-8} {1}  ({2:yyyy-MM-dd}, newest of {3})" -f $k.Kind, $newest.Name, $newest.Date, @($candidates).Count)
}

# ─── Download ─────────────────────────────────────────────────────────────────

$hashes = [ordered]@{}

foreach ($k in $kinds) {
    $p    = $picked[$k.Kind]
    $url  = if ($p.Href.StartsWith('http')) { $p.Href } else { "$Site$($p.Href)" }
    $tmp  = Join-Path $OutputFolder "$($k.Asset).tmp"

    Invoke-Download -Uri $url -OutFile $tmp -What "IDMS $($k.Kind)" -UserAgent $UA -TimeoutSec 120

    # The same three checks as sync-csrd2: a size floor for an error body, the ZIP magic for an
    # HTML page of plausible size, and opening it for a truncation that keeps the header.
    $size = (Get-Item $tmp).Length
    if ($size -lt $k.MinBytes) {
        Remove-Item $tmp -Force
        throw "$($k.Kind) download is $size bytes, under the $($k.MinBytes) floor — an error response, not the file."
    }
    $magic = [System.IO.File]::ReadAllBytes($tmp)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        Remove-Item $tmp -Force
        throw "$($k.Kind) download is not a ZIP container (magic: $($magic -join ' '))."
    }
    $names = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        try { $names = @($zip.Entries | ForEach-Object { $_.Name }) } finally { $zip.Dispose() }
    }
    catch {
        Remove-Item $tmp -Force
        throw "$($k.Kind) download will not open — $($_.Exception.Message)"
    }
    if ($names -notcontains $k.Entry) {
        Remove-Item $tmp -Force
        throw "$($k.Kind) holds no '$($k.Entry)' — got: $($names -join ', ')"
    }

    $hashes[$k.Kind] = (Get-FileHash $tmp -Algorithm SHA256).Hash
    $final = Join-Path $OutputFolder $k.Asset
    if (Test-Path $final) { Remove-Item $final -Force }
    Move-Item $tmp $final
}

# ─── Change detection ─────────────────────────────────────────────────────────
#
# On content, not on the dates in the names: a file can be replaced under the same name, and a
# new name can carry identical bytes. Most runs find all three unchanged and publish nothing.

$versionFile = Join-Path $OutputFolder "be-idms-version.txt"
$lines = foreach ($k in $kinds) {
    $p = $picked[$k.Kind]
    "$($k.Kind.ToLowerInvariant())=$($hashes[$k.Kind]) $($p.Date.ToString('yyyy-MM-dd')) $($p.Name)"
}
$marker = ($lines -join "`n")

if (-not $Force -and (Test-Path $versionFile)) {
    $stored = ((Get-Content $versionFile -Raw) -split "`n" | ForEach-Object { ($_ -split ' ')[0] }) -join "`n"
    $fresh  = ($lines | ForEach-Object { ($_ -split ' ')[0] }) -join "`n"
    if ($stored.Trim() -eq $fresh.Trim()) {
        Write-Host "IDMS documentation unchanged since the last run — nothing to publish."
        # The workflow publishes on the presence of the assets, so they go.
        foreach ($k in $kinds) { Remove-Item (Join-Path $OutputFolder $k.Asset) -Force }
        exit 0
    }
    Write-Host "IDMS documentation changed since the last run."
}

$marker | Set-Content $versionFile -NoNewline
Write-Host "IDMS documentation ready to publish:"
$lines | ForEach-Object { Write-Host "  $_" }
