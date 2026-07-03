# Mirrors EU customs legislation METADATA from the EU Publications Office CELLAR
# repository via its public SPARQL endpoint. Manifest only — no full text (see
# sync-eurlex-full.ps1 for that). This is the fast, daily-synced half.
#
# WHY CELLAR, NOT eur-lex.europa.eu:
#   The eur-lex.europa.eu search/HTML frontend is WAF-protected (returns HTTP 202 to
#   scripted clients). CELLAR (publications.europa.eu) is the sanctioned machine
#   interface — a Virtuoso SPARQL endpoint plus content-negotiation by CELEX — and is
#   NOT behind that WAF. See scripts/sync-eurlex-annexes.ps1 for the (blocked) HTML route.
#
# SCOPE:
#   EU legal acts classified under a "directory code" (dir-eu-legal-act) prefix.
#   Customs tariff legislation lives under 0230* (Application of the Common Customs Tariff):
#     023030   Tariff derogations
#     02303010   Tariff suspensions
#     02303020   Tariff quotas
#   Use -DirectoryCodePrefix "02" for the whole Customs Union chapter (~15k works),
#   "0230" for CCT application (~9.5k, the default), or a narrower code.
#
# OUTPUT:
#   eurlex-manifest.csv / .json  — one row per work: CELEX, title, OJ id, dates,
#                                  in-force flag, resource-type, ELI, directory codes.
#   eurlex-version.txt            — change-detection sentinel (work count + max doc date).
#
# The manifest is what CustomsHive/Tarbel needs for the per-measure regulation modal
# (title + OJ + dates + deep-link to EUR-Lex via CELEX/ELI).

param(
    [string]   $OutputFolder        = "downloads/eurlex",
    [string]   $DirectoryCodePrefix = "0230",     # customs tariff legislation
    [string]   $TitleLanguage       = "ENG",      # ISO 639-3 for the title column
    [int]      $Limit               = 0,          # 0 = all; >0 caps works (for testing)
    [int]      $BatchSize           = 500,
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
        try { return Invoke-RestMethod -Uri $Endpoint -Method Post -Body $body -TimeoutSec 180 }
        catch {
            if ($try -eq 4) { throw }
            Write-Host "  SPARQL retry $try after error: $($_.Exception.Message)"
            Start-Sleep -Seconds ([math]::Pow(2, $try))
        }
    }
}

# ─── Enumerate works under the directory-code prefix (paged) ──────────────────

$titleLangUri = "$LangBase$TitleLanguage"
Write-Host "Enumerating EUR-Lex works under directory-code prefix '$DirectoryCodePrefix' (title lang: $TitleLanguage)..."

$works  = [System.Collections.Generic.List[object]]::new()
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
  ?w cdm:resource_legal_id_celex ?celex ;
     cdm:resource_legal_is_about_concept_directory-code ?dir .
  BIND(REPLACE(STR(?dir), ".*/", "") AS ?dircode)
  FILTER(STRSTARTS(?dircode, "$DirectoryCodePrefix"))
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
ORDER BY DESC(?docDate) ?celex
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
    Write-Host "  fetched $($works.Count) works..."
    $offset += $rows.Count
    if ($rows.Count -lt $take) { break }
}

if ($works.Count -eq 0) { throw "No works returned for directory-code prefix '$DirectoryCodePrefix'." }
Write-Host "Total works: $($works.Count)"

# ─── Change detection ─────────────────────────────────────────────────────────

$maxDate     = ($works | Where-Object DocDate | Sort-Object DocDate -Descending | Select-Object -First 1).DocDate
$sentinel    = "count=$($works.Count);maxdate=$maxDate;prefix=$DirectoryCodePrefix"
$versionFile = Join-Path $OutputFolder "eurlex-version.txt"
if (-not $Force -and (Test-Path $versionFile)) {
    if ((Get-Content $versionFile -Raw).Trim() -eq $sentinel) {
        Write-Host "No change since last run ($sentinel) — skipping manifest write."
        exit 0
    }
}

# ─── Write manifest ───────────────────────────────────────────────────────────

$csvOut  = Join-Path $OutputFolder "eurlex-manifest.csv"
$jsonOut = Join-Path $OutputFolder "eurlex-manifest.json"
$works | Export-Csv -Path $csvOut -NoTypeInformation -Encoding UTF8
$works | ConvertTo-Json -Depth 4 | Set-Content $jsonOut -Encoding UTF8
$manifestMB = ((Get-Item $csvOut).Length + (Get-Item $jsonOut).Length) / 1MB

$sentinel | Set-Content $versionFile -NoNewline
Write-Host ("Manifest written: {0} rows, {1:N2} MB (csv+json). Sentinel: {2}" -f $works.Count, $manifestMB, $sentinel)
