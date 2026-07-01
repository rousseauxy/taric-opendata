# Downloads specific annexes from EUR-Lex consolidated regulation HTML and extracts
# structured tables as CSV files.
#
# Current target: BIJLAGE 23-01 of Regulation (EU) 2015/2447 (UCC IA)
#   Air transport cost percentages to include in customs value (Article 136 UCC IA).
#   Used to determine how much of the air freight cost forms part of the customs value
#   when goods are imported by air from a non-EU country.
#
# Source: https://eur-lex.europa.eu/legal-content/NL/ALL/?uri=CELEX:32015R2447
# Output: CSV mapping departure airport to EU arrival zone percentages.
#
# Change detection: consolidation date stored in eurlex-version.txt.
# The annex only changes when the regulation is formally amended — typically infrequent.

param(
    [string]$OutputFolder = "downloads/eurlex",
    [string]$Language     = "NL",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$UA    = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
$Celex = "32015R2447"

# ─── Discover latest consolidated version ────────────────────────────────────

Write-Host "Querying EUR-Lex for latest consolidated version of $Celex ($Language)..."
$allUrl  = "https://eur-lex.europa.eu/legal-content/$Language/ALL/?uri=CELEX:$Celex"
$allHtml = (Invoke-WebRequest -Uri $allUrl -UserAgent $UA -UseBasicParsing -TimeoutSec 30).Content

# Consolidated CELEX IDs look like 02015R2447-20XXXXXX
$consolPattern = "0$($Celex.Substring(1))-(\d{8})"
$versions = [regex]::Matches($allHtml, $consolPattern) |
    ForEach-Object { $_.Value } | Sort-Object -Descending -Unique
if (-not $versions) { throw "No consolidated versions found for $Celex on EUR-Lex" }

$latestCelex = $versions[0]           # e.g. 02015R2447-20200720
$latestDate  = $latestCelex -replace '.*-', ''   # e.g. 20200720
Write-Host "Latest consolidated version: $latestCelex"
if ($versions.Count -gt 1) {
    Write-Host "All consolidations found: $($versions -join ', ')"
}

# ─── Change detection ─────────────────────────────────────────────────────────

$versionFile = Join-Path $OutputFolder "$Celex-version.txt"
$csvOut      = Join-Path $OutputFolder "$Celex-annex23-01.csv"

if (-not $Force -and (Test-Path $versionFile)) {
    $stored = (Get-Content $versionFile -Raw).Trim()
    if ($stored -eq $latestDate) {
        Write-Host "No change since $latestDate — skipping download."
        exit 0
    }
    Write-Host "Version changed: $stored → $latestDate"
}

# ─── Download full regulation HTML ───────────────────────────────────────────

$htmlUrl = "https://eur-lex.europa.eu/legal-content/$Language/TXT/HTML/?uri=CELEX:$latestCelex"
Write-Host "Downloading HTML: $htmlUrl"
$html = (Invoke-WebRequest -Uri $htmlUrl -UserAgent $UA -UseBasicParsing -TimeoutSec 120).Content
Write-Host "Downloaded: $([math]::Round($html.Length / 1KB, 0)) KB"

# ─── Locate BIJLAGE 23-01 section ────────────────────────────────────────────

# EUR-Lex consolidated HTML marks annexes via id attributes or heading text.
# The Dutch version uses "BIJLAGE", English uses "ANNEX".
$markerPatterns = @(
    'id="ANX_23-01"',
    'id="anx_23-01"',
    'BIJLAGE\s+23-01',
    'ANNEX\s+23-01'
)
$annexStart = $null
foreach ($pat in $markerPatterns) {
    $m = [regex]::Match($html, "(?is)$pat")
    if ($m.Success) {
        $annexStart = $m.Index
        Write-Host "Found annex marker via pattern: $pat (offset $annexStart)"
        break
    }
}
if ($null -eq $annexStart) {
    throw "Could not locate BIJLAGE 23-01 / ANNEX 23-01 in the downloaded HTML. " +
          "The document structure may have changed — inspect the HTML manually."
}

# Slice from annex start to the next annex (23-02) or a safe maximum
$tail = $html.Substring($annexStart)

$nextMarkerPatterns = @('BIJLAGE\s+23-02', 'ANNEX\s+23-02', 'id="ANX_23-02"', 'id="anx_23-02"')
$nextIdx = $null
foreach ($pat in $nextMarkerPatterns) {
    # Skip the first ~50 chars so we don't re-match the current marker
    $m = [regex]::Match($tail.Substring(50), "(?is)$pat")
    if ($m.Success) { $nextIdx = 50 + $m.Index; break }
}
$annexHtml = if ($null -ne $nextIdx) {
    $tail.Substring(0, $nextIdx)
} else {
    $tail.Substring(0, [Math]::Min(500000, $tail.Length))
}
Write-Host "Annex 23-01 section isolated: $($annexHtml.Length) chars"

# ─── Parse all tables in the section ─────────────────────────────────────────

function Get-CellText([string]$raw) {
    $raw -replace '(?is)<br\s*/?>', ' / ' `
         -replace '<[^>]+>', '' `
         -replace '&nbsp;', ' ' `
         -replace '&#160;', ' ' `
         -replace '&amp;', '&' `
         -replace '&lt;', '<' `
         -replace '&gt;', '>' `
         -replace '\s+', ' ' |
    ForEach-Object { $_.Trim() }
}

function Parse-HtmlTable([string]$tableHtml) {
    $rows = [regex]::Matches($tableHtml, '(?is)<tr[^>]*>(.*?)</tr>')
    $parsed = @()
    foreach ($row in $rows) {
        $cells = [regex]::Matches($row.Groups[1].Value, '(?is)<t[dh][^>]*>(.*?)</t[dh]>') |
            ForEach-Object { Get-CellText $_.Groups[1].Value }
        if ($cells.Count -gt 0) { $parsed += ,@($cells) }
    }
    return $parsed
}

$tables = [regex]::Matches($annexHtml, '(?is)<table[^>]*>.*?</table>')
Write-Host "Found $($tables.Count) table(s) in annex section"

if ($tables.Count -eq 0) {
    throw "No <table> elements found in BIJLAGE 23-01 section"
}

# Use the largest table (most cells) as the main data table
$mainTable = $tables | Sort-Object { $_.Value.Length } -Descending | Select-Object -First 1
$parsedRows = Parse-HtmlTable $mainTable.Value

Write-Host "Parsed $($parsedRows.Count) rows from main table"

if ($parsedRows.Count -lt 2) {
    throw "Table appears empty or could not be parsed ($($parsedRows.Count) rows)"
}

# ─── Diagnostic preview ───────────────────────────────────────────────────────

Write-Host ""
Write-Host "─── Table preview (first 8 rows) ────────────────────────────────────"
$parsedRows | Select-Object -First 8 | ForEach-Object {
    Write-Host ($_ -join "  |  ")
}
Write-Host "─────────────────────────────────────────────────────────────────────"
Write-Host ""

# ─── Write CSV ────────────────────────────────────────────────────────────────

# Heuristic: first non-empty row with the most cells is the header
$headerRow  = ($parsedRows | Sort-Object { $_.Count } -Descending)[0]
$headerIdx  = $parsedRows.IndexOf($headerRow)
$dataRows   = $parsedRows | Select-Object -Skip ($headerIdx + 1)

function ConvertTo-CsvLine([array]$cells) {
    ($cells | ForEach-Object { '"' + ($_ -replace '"', '""') + '"' }) -join ','
}

$sb = [System.Text.StringBuilder]::new()
$sb.AppendLine((ConvertTo-CsvLine $headerRow)) | Out-Null
foreach ($row in $dataRows) {
    # Pad short rows to header width so CSV columns stay aligned
    $padded = $row + @('') * ([Math]::Max(0, $headerRow.Count - $row.Count))
    $sb.AppendLine((ConvertTo-CsvLine $padded)) | Out-Null
}
$sb.ToString() | Set-Content $csvOut -Encoding UTF8

$latestDate | Set-Content $versionFile -NoNewline
Write-Host "Saved $($dataRows.Count) data rows → $csvOut"
Write-Host "Version recorded: $latestDate"
