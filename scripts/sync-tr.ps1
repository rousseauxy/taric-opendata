# Downloads the Turkish Customs Tariff (TGTC — Türk Gümrük Tarife Cetveli) nomenclature from the
# Ministry of Trade and parses it into tr-nomenclature.csv (consumed by TaricHive's TrImporter).
#   Source: https://ggm.ticaret.gov.tr/ — the annual "İstatistik Pozisyonlarına Bölünmüş Türk
#           Gümrük Tarife Cetveli", published as a zip of per-chapter legacy .xls files.
# The zip's nomenclature files ("NN fasıl YYYY.xls") give the 12-digit GTİP code, Turkish
# description, unit of measure and the base (474) duty rate. Parsing uses Python + xlrd (the .xls
# is legacy BIFF — see parse-tgtc.py). Descriptions are Turkish only; TaricHive backfills the EN/
# NL/FR/DE via the EU CN cross-reference (GTİP digits 1-8 = HS6 + CN2).
param(
    [string]$OutputFolder = "downloads/tr",
    [int]   $Year         = 0,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
if ($Year -le 0) { $Year = (Get-Date).Year }
$py = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }

function Resolve-TgtcUrl([int]$y) {
    $page = "https://ggm.ticaret.gov.tr/haberler/$y-yili-istatistik-pozisyonlarina-bolunmus-turk-gumruk-tarife-cetveli-yayimlanmistir"
    try { $html = (Invoke-WebRequest -Uri $page -UserAgent $UA -UseBasicParsing -TimeoutSec 60).Content }
    catch { return $null }
    $m = [regex]::Match($html, 'href="(?<u>[^"]*TGTC\.zip)"', 'IgnoreCase')
    if (-not $m.Success) { return $null }
    $u = $m.Groups['u'].Value
    if ($u -notmatch '^https?://') { $u = "https://ggm.ticaret.gov.tr" + $(if ($u.StartsWith("/")) { $u } else { "/$u" }) }
    return $u
}

# ─── Resolve the latest TGTC zip (current year, then previous) ─────────────────
$zipUrl = $null; $usedYear = $Year
foreach ($y in @($Year, ($Year - 1))) {
    $zipUrl = Resolve-TgtcUrl $y
    if ($zipUrl) { $usedYear = $y; break }
}
if (-not $zipUrl) { throw "Could not resolve the TGTC zip URL from ggm.ticaret.gov.tr." }
Write-Host "TGTC $usedYear : $zipUrl"

$sentinel = Join-Path $OutputFolder "tr-version.txt"
if (-not $Force -and (Test-Path $sentinel) -and (Get-Content $sentinel -Raw).Trim() -eq $zipUrl) {
    Write-Host "TGTC unchanged — skipping."
    exit 0
}

# ─── Download + extract ───────────────────────────────────────────────────────
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "tgtc-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Force -Path $tmp | Out-Null
try {
    $zip = Join-Path $tmp "tgtc.zip"
    Invoke-WebRequest -Uri ([uri]::EscapeUriString($zipUrl)) -UserAgent $UA -UseBasicParsing -OutFile $zip -TimeoutSec 300
    Write-Host "  downloaded $([math]::Round((Get-Item $zip).Length / 1MB, 1)) MB"

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $ex = Join-Path $tmp "x"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $ex)

    # Nomenclature chapter files are "NN fasıl YYYY.xls"; the chapter-*notes* ("Fasıl N.xls") have a
    # different structure and are excluded by the leading-digits pattern.
    $flat = Join-Path $tmp "chapters"; New-Item -ItemType Directory -Force -Path $flat | Out-Null
    $n = 0
    Get-ChildItem -Path $ex -Recurse -Filter *.xls |
        Where-Object { $_.Name -match '^\d{2}\s+fas' } |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $flat $_.Name) -Force; $n++ }
    Write-Host "  chapter files: $n"
    if ($n -eq 0) { throw "No TGTC nomenclature chapter files ('NN fasıl') found in the zip." }

    # ─── Parse (Python + xlrd) ────────────────────────────────────────────────
    & $py -m pip install --quiet --disable-pip-version-check xlrd 2>&1 | Out-Null
    $csv = Join-Path $OutputFolder "tr-nomenclature.csv"
    & $py (Join-Path $PSScriptRoot "parse-tgtc.py") $flat $csv
    if (-not (Test-Path $csv) -or (Get-Item $csv).Length -lt 100) { throw "parse-tgtc.py produced no usable output." }

    $zipUrl | Set-Content $sentinel -NoNewline
    Write-Host "Wrote tr-nomenclature.csv ($([math]::Round((Get-Item $csv).Length / 1KB, 0)) KB)"
}
finally {
    try { Remove-Item $tmp -Recurse -Force } catch { }
}
