# Scrapes UK Advance Tariff Rulings (ATaR) from the GOV.UK "Search for Advance Tariff
# Rulings" service and writes them to downloads/atar/atar.csv (release asset consumed by
# TaricHive's AtarImporter). ATaR is the GB analogue of EU BTIs.
#
# WHY SCRAPING: unlike the GB tariff (DBT CSV API) or EU EBTI (DDS2 CSV export), UK ATaR
# has NO bulk/API feed — only this HTML search service. GOV.UK content is Open Government
# Licence, so reuse is permitted. Enumeration: /search?page=N returns 25 /ruling/{id} links
# per page; each ruling page is a 6-field GOV.UK summary list.
#
# HEAVY / periodic (~6.6k ruling pages + ~265 search pages). Politeness delay between
# requests; change detection skips a full re-scrape when the total ruling count is unchanged.
param(
    [string]$OutputFolder = "downloads/atar",
    [int]   $DelayMs      = 150,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$Base = "https://www.tax.service.gov.uk/search-for-advance-tariff-rulings"
$UA   = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"

function Get-Html([string]$Url) {
    for ($t = 1; $t -le 4; $t++) {
        try { return (Invoke-WebRequest -Uri $Url -UserAgent $UA -UseBasicParsing -TimeoutSec 60).Content }
        catch { if ($t -eq 4) { throw }; Start-Sleep -Seconds ([math]::Pow(2, $t)) }
    }
}
function Clean([string]$s) {
    $s = $s -replace '<[^>]*>', ' '
    $s = [System.Net.WebUtility]::HtmlDecode($s)
    ($s -replace '\s+', ' ').Trim()
}
function ConvertDate([string]$s) {
    if ([string]::IsNullOrWhiteSpace($s)) { return '' }
    try { return ([datetime]::ParseExact($s.Trim(), 'dd MMM yyyy', [Globalization.CultureInfo]::InvariantCulture)).ToString('yyyy-MM-dd') }
    catch { return $s.Trim() }
}

# ─── 1. Total count + change detection ────────────────────────────────────────
$first = Get-Html "$Base/search?page=1"
$total = if ($first -match '([\d,]+)\s+results') { [int]($matches[1] -replace ',', '') } else { 0 }
if ($total -eq 0) { throw "Could not read ATaR result count from the search page." }
$pages = [math]::Ceiling($total / 25)
Write-Host "ATaR: $total rulings across $pages search pages"

$sentinel = Join-Path $OutputFolder "atar-version.txt"
if (-not $Force -and (Test-Path $sentinel) -and (Get-Content $sentinel -Raw).Trim() -eq "count=$total") {
    Write-Host "ATaR unchanged ($total) — skipping scrape."
    exit 0
}

# ─── 2. Enumerate ruling ids across all search pages ──────────────────────────
$ids = [System.Collections.Generic.List[string]]::new()
for ($p = 1; $p -le $pages; $p++) {
    $html = if ($p -eq 1) { $first } else { Get-Html "$Base/search?page=$p" }
    foreach ($m in [regex]::Matches($html, 'ruling/(\d+)')) { $ids.Add($m.Groups[1].Value) }
    if ($p % 20 -eq 0) { Write-Host "  search page $p/$pages ($($ids.Count) ids so far)" }
    Start-Sleep -Milliseconds $DelayMs
}
$ids = @($ids | Select-Object -Unique)
Write-Host "Collected $($ids.Count) unique ruling ids"

# ─── 3. Fetch + parse each ruling (6-field GOV.UK summary list) ────────────────
$rows = [System.Collections.Generic.List[object]]::new()
$i = 0; $fail = 0
foreach ($id in $ids) {
    $i++
    try {
        $h = Get-Html "$Base/ruling/$id"
        $keys = [regex]::Matches($h, 'govuk-summary-list__key[^>]*>(.*?)</dt>', 'Singleline')
        $vals = [regex]::Matches($h, 'govuk-summary-list__value[^>]*>(.*?)</dd>', 'Singleline')
        $map = @{}
        for ($k = 0; $k -lt [Math]::Min($keys.Count, $vals.Count); $k++) {
            $map[(Clean $keys[$k].Groups[1].Value)] = (Clean $vals[$k].Groups[1].Value)
        }
        $code = (($map['Commodity code'] -replace '\(opens in new tab\)', '')).Trim()
        if (-not $code) { $fail++; continue }
        $rows.Add([pscustomobject]@{
            Reference     = $id
            CommodityCode = $code
            StartDate     = ConvertDate $map['Start date']
            EndDate       = ConvertDate $map['Expiry date']
            Description   = $map['Description']
            Keywords      = $map['Keywords']
            Justification = $map['Justification']
        })
    } catch { $fail++; Write-Host "  ruling $id failed: $($_.Exception.Message)" }
    if ($i % 100 -eq 0) { Write-Host "  $i/$($ids.Count) rulings ($fail failed)" }
    Start-Sleep -Milliseconds $DelayMs
}

if ($rows.Count -eq 0) { throw "No ATaR rulings parsed — aborting without writing atar.csv." }

# ─── 4. Write CSV + sentinel ──────────────────────────────────────────────────
$csv = Join-Path $OutputFolder "atar.csv"
$rows | Export-Csv -Path $csv -NoTypeInformation -Encoding UTF8
"count=$total" | Set-Content $sentinel -NoNewline
Write-Host "Wrote $($rows.Count) rulings -> atar.csv ($fail failed)"
