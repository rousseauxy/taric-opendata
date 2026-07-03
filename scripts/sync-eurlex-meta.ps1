# Mirrors EU secondary-legislation METADATA from the EU Publications Office CELLAR
# repository via its public SPARQL endpoint. Manifest only — no full text (see
# sync-eurlex-full.ps1 for that). This is the fast, daily-synced half.
#
# WHY CELLAR, NOT eur-lex.europa.eu:
#   The eur-lex.europa.eu search/HTML frontend is WAF-protected (returns HTTP 202 to
#   scripted clients). CELLAR (publications.europa.eu) is the sanctioned machine
#   interface — a Virtuoso SPARQL endpoint plus content-negotiation by CELEX — and is
#   NOT behind that WAF. See scripts/sync-eurlex-annexes.ps1 for the (blocked) HTML route.
#
# SCOPE: ALL of CELEX sector 3 (secondary legislation — regulations, directives,
#   decisions), ~233k works. This guarantees complete coverage of every regulation a
#   TARIC measure can reference: a TARIC GeneratingRegulationId always maps to a sector-3
#   CELEX (e.g. R2309660 -> 32023R0966), so any cited act is in this set regardless of its
#   legal-act directory (customs 0230, sanctions 18, GSP 116, trade agreements 114, ...).
#   Consumers (e.g. CustomsHive) join Regulation.Celex to the measure's computed CELEX and
#   filter/browse locally — no per-code lookup against CELLAR needed.
#
#   Enumeration is partitioned by CELEX year ("3{year}...") to keep every query small and
#   avoid deep OFFSET over the full 233k. Each year is ~1.5k-5k works and returns in seconds.
#
# OUTPUT:
#   eurlex-manifest.csv  — one row per work: CELEX, title, OJ id, dates, in-force flag,
#                          resource-type, ELI, directory codes.
#   eurlex-version.txt   — change-detection sentinel (work count + max doc date).
#
# The manifest is what CustomsHive/Tarbel needs for the per-measure regulation modal and the
# legislation browser (title + OJ + dates + deep-link to EUR-Lex via CELEX/ELI).

param(
    [string]   $OutputFolder  = "downloads/eurlex",
    [string]   $Sector        = "3",       # 3 = secondary legislation (regs/directives/decisions)
    [int]      $StartYear     = 0,         # 0 = current UTC year + 1 (catch post-dated acts)
    [int]      $EndYear       = 1952,      # earliest EU legislation
    [string]   $TitleLanguage = "ENG",     # ISO 639-3 for the title column
    [int]      $Limit         = 0,         # 0 = all; >0 caps total works (for testing)
    [int]      $BatchSize     = 5000,
    [switch]   $Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$Endpoint = "http://publications.europa.eu/webapi/rdf/sparql"
$LangBase = "http://publications.europa.eu/resource/authority/language/"

function Invoke-Sparql([string]$Query) {
    $body = @{ query = $Query; format = "application/sparql-results+json" }
    for ($try = 1; $try -le 4; $try++) {
        try { return Invoke-RestMethod -Uri $Endpoint -Method Post -Body $body -TimeoutSec 280 }
        catch {
            if ($try -eq 4) { throw }
            Write-Host "  SPARQL retry $try after error: $($_.Exception.Message)"
            Start-Sleep -Seconds ([math]::Pow(2, $try))
        }
    }
}

# ─── Enumerate sector-3 works, partitioned by CELEX year ──────────────────────

$titleLangUri = "$LangBase$TitleLanguage"
$startYear    = if ($StartYear -gt 0) { $StartYear } else { (Get-Date).Year + 1 }
Write-Host "Enumerating CELEX sector $Sector, years $startYear..$EndYear (title lang: $TitleLanguage)..."

$works = [System.Collections.Generic.List[object]]::new()
$sw    = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($year in ($startYear..$EndYear)) {
    if ($Limit -gt 0 -and $works.Count -ge $Limit) { break }

    $offset = 0
    while ($true) {
        $take = $BatchSize
        if ($Limit -gt 0) { $take = [Math]::Min($BatchSize, $Limit - $works.Count) }
        if ($take -le 0) { break }

        $q = @"
PREFIX cdm: <http://publications.europa.eu/ontology/cdm#>
SELECT ?celex
  (SAMPLE(?dateDoc)  AS ?docDate)
  (SAMPLE(?eif)      AS ?entryIntoForce)
  (SAMPLE(?eov)      AS ?endValidity)
  (SAMPLE(?inforce)  AS ?inForce)
  (SAMPLE(?rtype)    AS ?resourceType)
  (SAMPLE(?eliv)     AS ?eli)
  (SAMPLE(?ojid)     AS ?ojId)
  (SAMPLE(?title)    AS ?title)
  (GROUP_CONCAT(DISTINCT ?dircode; separator="|") AS ?dirCodes)
WHERE {
  ?w cdm:resource_legal_id_sector "$Sector"^^<http://www.w3.org/2001/XMLSchema#string> ;
     cdm:resource_legal_id_celex ?celex .
  FILTER(STRSTARTS(STR(?celex), "$Sector$year"))
  OPTIONAL { ?w cdm:work_date_document ?dateDoc }
  OPTIONAL { ?w cdm:resource_legal_date_entry-into-force ?eif }
  OPTIONAL { ?w cdm:resource_legal_date_end-of-validity ?eov }
  OPTIONAL { ?w cdm:resource_legal_in-force ?inforce }
  OPTIONAL { ?w cdm:work_has_resource-type ?rt . BIND(REPLACE(STR(?rt), ".*/", "") AS ?rtype) }
  OPTIONAL { ?w cdm:resource_legal_eli ?eliv }
  OPTIONAL { ?w cdm:work_id_document ?ojid . FILTER(STRSTARTS(STR(?ojid), "oj:")) }
  OPTIONAL {
    ?expr cdm:expression_belongs_to_work ?w ;
          cdm:expression_uses_language <$titleLangUri> ;
          cdm:expression_title ?title .
  }
}
GROUP BY ?celex
ORDER BY ?celex
OFFSET $offset LIMIT $take
"@

        $rows = (Invoke-Sparql $q).results.bindings
        if (-not $rows -or $rows.Count -eq 0) { break }

        foreach ($b in $rows) {
            $works.Add([pscustomobject]@{
                Celex          = $b.celex.value
                Title          = if ($b.PSObject.Properties['title'])          { $b.title.value }          else { "" }
                ResourceType   = if ($b.PSObject.Properties['resourceType'])   { $b.resourceType.value }   else { "" }
                DocDate        = if ($b.PSObject.Properties['docDate'])         { $b.docDate.value }        else { "" }
                EntryIntoForce = if ($b.PSObject.Properties['entryIntoForce'])  { $b.entryIntoForce.value } else { "" }
                EndValidity    = if ($b.PSObject.Properties['endValidity'])     { $b.endValidity.value }    else { "" }
                InForce        = if ($b.PSObject.Properties['inForce'])         { $b.inForce.value }        else { "" }
                Eli            = if ($b.PSObject.Properties['eli'])             { $b.eli.value }            else { "" }
                OjId           = if ($b.PSObject.Properties['ojId'])            { $b.ojId.value }           else { "" }
                DirCodes       = if ($b.PSObject.Properties['dirCodes'])        { $b.dirCodes.value }       else { "" }
            })
        }

        $offset += $rows.Count
        if ($rows.Count -lt $take) { break }   # last page for this year
    }

    if ($year % 5 -eq 0 -or $year -ge $startYear - 2) {
        Write-Host ("  ..{0}: {1} works total ({2:N0}s)" -f $year, $works.Count, $sw.Elapsed.TotalSeconds)
    }
}

if ($works.Count -eq 0) { throw "No works returned for sector '$Sector'." }
Write-Host ("Total works: {0} in {1:N0}s" -f $works.Count, $sw.Elapsed.TotalSeconds)

# ─── Change detection ─────────────────────────────────────────────────────────

$maxDate     = ($works | Where-Object DocDate | Sort-Object DocDate -Descending | Select-Object -First 1).DocDate
$sentinel    = "scope=sector$Sector;count=$($works.Count);maxdate=$maxDate"
$versionFile = Join-Path $OutputFolder "eurlex-version.txt"
if (-not $Force -and (Test-Path $versionFile)) {
    if ((Get-Content $versionFile -Raw).Trim() -eq $sentinel) {
        Write-Host "No change since last run ($sentinel) — skipping manifest write."
        exit 0
    }
}

# ─── Write manifest (CSV only — 233k rows; JSON would be needlessly large) ─────

$csvOut = Join-Path $OutputFolder "eurlex-manifest.csv"
$works | Export-Csv -Path $csvOut -NoTypeInformation -Encoding UTF8
$manifestMB = (Get-Item $csvOut).Length / 1MB

$sentinel | Set-Content $versionFile -NoNewline
Write-Host ("Manifest written: {0} rows, {1:N1} MB. Sentinel: {2}" -f $works.Count, $manifestMB, $sentinel)
