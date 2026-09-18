# Mirrors the Belgian customs systems' technical documentation — the rules, code lists and XSDs
# each system validates a declaration against — from minfin's documentation pages.
#
#   -System IDMS   import (IE415B/IE413B…)        technische-documentatie-0/idms/all
#   -System AES    export (CC515C…)               aes/aes-export
#   -System NCTS   transit (CC015C…), P5 and P6   technische-documentatie-0/ncts, …/ncts-p5, …/ncts-p6
#
# WHY: a declaration generator reads its rules from whatever copy it was given, and minfin replaces
# these files without announcement. The IDMS rules we held were a 2024 PDF; by 2026-09-08 the live
# workbook had switched off two rules the PDF presents as requirements. A copy taken once is wrong
# within months, in both directions.
#
# THE FILE NAMES CARRY THE EDITION, IN NO FIXED FORMAT, AND OLD EDITIONS STAY LINKED. Seen on these
# pages: 260908_IDMS_VRE (yymmdd), 09042025_IDMS_VRE (ddmmyyyy), 20230922 IDMS_XSD (yyyymmdd),
# "AES validation rules 2026-01-09", "NCTSP5 Rules and Conditions 30 03 26" (dd MM yy), "… 22 10
# 2025" (dd MM yyyy), "MIGv041" (a version), and names with nothing at all ("national code
# lists_0.zip"). So each link is keyed by the edition its own name states and the newest of each
# kind wins; an undated kind must match exactly one link, or the run stops rather than guess.
#
# THE NEWEST EDITION IS NOT ALWAYS ON THE PAGE YOU WOULD EXPECT. On 2026-09-18 the NCTS P5 page
# offered "Rules and Conditions 04 03 26" while the general NCTS page offered "30 03 26". A system
# is therefore a set of pages, and the newest is taken across all of them.
#
# A PAGE CAN ANSWER 200 WITH NOTHING IN IT. The AES page did, once, on 2026-09-18. That is not an
# error to the HTTP client, so it would not be retried; a page with no document links is therefore
# treated as a failed attempt inside the retry, not as "the page changed shape".
param(
    [Parameter(Mandatory)][ValidateSet('IDMS', 'AES', 'NCTS')][string]$System,
    [string]$OutputFolder,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force
if (-not $OutputFolder) { $OutputFolder = "downloads/be-$($System.ToLowerInvariant())" }
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

Add-Type -AssemblyName System.IO.Compression.FileSystem

$UA   = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"
$Site = "https://financien.belgium.be"
$Docs = "$Site/nl/douane_accijnzen/ondernemingen/applicaties-da"

# ─── What each system publishes ───────────────────────────────────────────────
#
# Pattern is matched against the unescaped file name. Asset is the stable name it is published
# under; "{key}" in it takes the pattern's "key" group, for a kind that is several files (one per
# national code list). Entry is a wildcard some entry of the ZIP container must match — xlsx and
# docx are ZIPs too — which tells a real file from an error page of plausible size.

$xlsx = 'workbook.xml'; $docx = 'document.xml'

$systems = @{
    IDMS = @{
        Pages = @("$Docs/technische-documentatie-0/idms/all")
        Kinds = @(
            @{ Pattern = '_IDMS_VRE[^/]*\.xlsx$';  Asset = 'IDMS_VRE.xlsx';      Entry = $xlsx;        MinBytes = 50KB }
            @{ Pattern = '_codelist\.xlsx$';       Asset = 'IDMS_codelist.xlsx'; Entry = $xlsx;        MinBytes = 100KB }
            @{ Pattern = 'idms[-_ ]xsd\.zip$';     Asset = 'IDMS_XSD.zip';       Entry = 'IE415B.xsd'; MinBytes = 2KB }
        )
        Title = 'Belgian IDMS documentation'
        Notes = @'
Auto-synced from the [minfin IDMS technical documentation](https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/idms/all) — what Belgium's import system validates a declaration against.

- `IDMS_VRE.xlsx`: the validation rules, on three sheets — active, inactive (not enforced) and temporarily blocking — plus a change log. This is the live rule set; the Business rules PDF on the same page stopped being updated in May 2024.
- `idms-rules.json`: the same rules with a `status` on each, so an inactive rule cannot be mistaken for a live one.
- `IDMS_codelist.xlsx` / `idms-codelists.json`: IDMS's own filtered code lists (CL093 holds 28 codes here against 15 in the EU CCI list; CL214 carries the national 1VDP and 1ZVB).
- `IDMS_XSD.zip`: the message schemas.
- `be-idms-version.txt`: the source file each asset came from, its edition and SHA-256.
'@
    }
    AES = @{
        Pages = @("$Docs/aes/aes-export")
        Kinds = @(
            @{ Pattern = '^AES validation rules .*\.xlsx$';     Asset = 'AES_rules.xlsx';          Entry = $xlsx;   MinBytes = 50KB }
            @{ Pattern = '^AES validation nat rules .*\.xlsx$'; Asset = 'AES_national_rules.xlsx'; Entry = $xlsx;   MinBytes = 50KB }
            # Dated XSD archives only; the undated "Belgian XSD for AES V2.zip" is an old one.
            @{ Pattern = 'XSD.*\d{4}.*\.zip$';                  Asset = 'AES_XSD.zip';             Entry = '*.xsd'; MinBytes = 100KB; RequireEdition = $true }
            @{ Pattern = '^national code lists.*\.zip$';        Asset = 'AES_national_codelists.zip'; Entry = 'CLBE*'; MinBytes = 2KB }
        )
        Title = 'Belgian AES documentation'
        Notes = @'
Auto-synced from the [minfin AES export documentation](https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/aes/aes-export) — what Belgium's export system validates a declaration against.

- `AES_rules.xlsx`: the validation rules — active, inactive, "other active rules" (error codes with a description, no expression), the "missing documents filter", and release notes.
- `aes-rules.json`: the same rules, each with the `sheet` it came from and a `status` where the sheet states one (`active` / `inactive`).
- `AES_national_rules.xlsx` / `aes-national-rules.json`: a second rule workbook minfin publishes as "validation nat rules", same layout; its editions are dated independently of the main one and overlap most of it.
- `AES_XSD.zip`: the Belgian national adaptation of the AES XSDs, newest dated edition.
- `AES_national_codelists.zip`: the Belgian national code lists (CLBE213, CLBE239, CLBE380) as JSON.
- `be-aes-version.txt`: the source file each asset came from, its edition and SHA-256.
'@
    }
    NCTS = @{
        Pages = @(
            "$Docs/technische-documentatie-0/ncts"
            "$Docs/technische-documentatie-0/ncts/ncts-p5"
            "$Docs/technische-documentatie-0/ncts/ncts-p6"
        )
        Kinds = @(
            @{ Pattern = '^NCTSP5 Rules and Conditions .*\.xlsx$';     Asset = 'NCTS_P5_rules.xlsx';       Entry = $xlsx; MinBytes = 50KB; RequireEdition = $true }
            @{ Pattern = '^(?<key>CLBE\d{3})(?!\d).*\.xlsx$';              Asset = 'NCTS_{key}.xlsx';          Entry = $xlsx; MinBytes = 4KB }
            @{ Pattern = '^nctsp6-XSD-MIG\.zip$';                      Asset = 'NCTS_P6_XSD.zip';          Entry = '*.xsd'; MinBytes = 20KB }
            @{ Pattern = '^NCTS P6 Business Rules MIGv\d+\.docx$';     Asset = 'NCTS_P6_business_rules.docx'; Entry = $docx; MinBytes = 50KB; RequireEdition = $true }
            @{ Pattern = '^NCTS P6 Code Lists MIGv\d+\.docx$';         Asset = 'NCTS_P6_code_lists.docx';  Entry = $docx; MinBytes = 50KB; RequireEdition = $true }
            @{ Pattern = '^NCTS P6 main document MIGv\d+\.docx$';      Asset = 'NCTS_P6_main_document.docx'; Entry = $docx; MinBytes = 50KB; RequireEdition = $true }
            @{ Pattern = '^P5DELTA FOR EO\.xlsx$';                     Asset = 'NCTS_P5_to_P6_delta.xlsx'; Entry = $xlsx; MinBytes = 10KB }
        )
        Title = 'Belgian NCTS documentation'
        Notes = @'
Auto-synced from the minfin NCTS documentation ([general](https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/ncts), [P5](https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/ncts/ncts-p5), [P6](https://financien.belgium.be/nl/douane_accijnzen/ondernemingen/applicaties-da/technische-documentatie-0/ncts/ncts-p6)) — what Belgium's transit system validates a declaration against. Belgium runs NCTS Phase 6 ("opt-out") since 2026-04-01, per the P6 main document.

- `NCTS_P5_rules.xlsx` / `ncts-p5-rules.json`: "Rules and Conditions" — the Belgian rules (BE…) and the EU rules and conditions, each rule with the `sheet` it came from. The newest edition is taken across all three pages: the general NCTS page has carried a newer one than the P5 page.
- `NCTS_CLBE*.xlsx` / `ncts-national-codelists.json`: the Belgian national code lists.
- `NCTS_P6_business_rules.docx`, `NCTS_P6_code_lists.docx`, `NCTS_P6_main_document.docx`: the P6 message implementation guide, as published (Word; not converted).
- `NCTS_P6_XSD.zip`: the P6 message schemas.
- `NCTS_P5_to_P6_delta.xlsx`: what changed from P5 to P6 for economic operators.
- `be-ncts-version.txt`: the source file each asset came from, its edition and SHA-256.
'@
    }
}

$config = $systems[$System]

# ─── Editions ─────────────────────────────────────────────────────────────────

function Get-Edition([string]$name) {
    # A sortable key for the edition a file name states, or $null. Dates first, then versions.
    $c = [Globalization.CultureInfo]::InvariantCulture
    $tries = @(
        @{ Rx = '(?<!\d)(\d{4}-\d{2}-\d{2})(?!\d)';   Fmt = 'yyyy-MM-dd' }
        @{ Rx = '(?<!\d)(\d{2} \d{2} \d{4})(?!\d)';   Fmt = 'dd MM yyyy' }
        @{ Rx = '(?<!\d)(\d{2} \d{2} \d{2})(?!\d)';   Fmt = 'dd MM yy' }
        @{ Rx = '(?<!\d)(20\d{6})(?!\d)';             Fmt = 'yyyyMMdd' }
        @{ Rx = '(?<!\d)(\d{8})(?!\d)';               Fmt = 'ddMMyyyy' }
        @{ Rx = '^(\d{6})(?!\d)';                     Fmt = 'yyMMdd' }
    )
    foreach ($t in $tries) {
        if ($name -match $t.Rx) {
            $d = [datetime]::MinValue
            if ([datetime]::TryParseExact($Matches[1], $t.Fmt, $c, 'None', [ref]$d)) { return 'd' + $d.ToString('yyyy-MM-dd') }
        }
    }
    if ($name -match '(?i)v(\d+(?:\.\d+)*)') {
        return 'v' + (($Matches[1] -split '\.' | ForEach-Object { $_.PadLeft(6, '0') }) -join '.')
    }
    return $null
}

# ─── Read the pages ───────────────────────────────────────────────────────────

$links = foreach ($pageUrl in $config.Pages) {
    Write-Host "Reading $pageUrl"
    $content = Invoke-WithRetry -What "page $(($pageUrl -split '/')[-1])" -Action {
        $resp = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing -UserAgent $UA -TimeoutSec 60
        # Inside the retry on purpose: an empty 200 is a failed attempt, not an answer.
        if ($resp.Content -notmatch 'href="[^"]+\.(?:xlsx|zip|docx|pdf)"') {
            throw "the page came back with no document links ($($resp.Content.Length) bytes)"
        }
        $resp.Content
    }
    foreach ($m in [regex]::Matches($content, 'href="([^"]+\.(?:xlsx|zip|docx))"')) {
        $href = $m.Groups[1].Value
        $url  = if ($href.StartsWith('http')) { $href } else { "$Site$href" }
        [pscustomobject]@{ Url = $url; Name = [uri]::UnescapeDataString(($href -split '/')[-1]).Trim() }
    }
}
$links = @($links | Sort-Object Url -Unique)

# ─── Pick the newest of each kind ─────────────────────────────────────────────

$picked = [System.Collections.Generic.List[object]]::new()
foreach ($k in $config.Kinds) {
    $matches_ = @(foreach ($l in $links) {
        $m = [regex]::Match($l.Name, $k.Pattern, 'IgnoreCase')
        if (-not $m.Success) { continue }
        $key = if ($m.Groups['key'].Success) { $m.Groups['key'].Value.ToUpperInvariant() } else { '' }
        [pscustomobject]@{ Url = $l.Url; Name = $l.Name; Key = $key; Edition = (Get-Edition $l.Name) }
    })
    if ($k.RequireEdition) { $matches_ = @($matches_ | Where-Object Edition) }
    if ($matches_.Count -eq 0) { throw "No link matches '$($k.Pattern)' — the page changed shape." }

    foreach ($group in ($matches_ | Group-Object Key)) {
        $dated = @($group.Group | Where-Object Edition | Sort-Object Edition -Descending)
        $chosen = if ($dated.Count -gt 0) { $dated[0] }
                  elseif (@($group.Group | Sort-Object Url -Unique).Count -eq 1) { $group.Group[0] }
                  else { throw "'$($k.Pattern)' matches several undated files ($(($group.Group.Name) -join ', ')) — cannot tell which is current." }
        $asset = $k.Asset.Replace('{key}', $group.Name)
        $picked.Add([pscustomobject]@{ Kind = $k; Asset = $asset; Url = $chosen.Url; Name = $chosen.Name; Edition = $chosen.Edition; Of = $group.Count })
        Write-Host ("  {0,-30} {1}  ({2}; {3} candidate(s))" -f $asset, $chosen.Name, ($chosen.Edition ?? 'undated'), $group.Count)
    }
}

# ─── Download ─────────────────────────────────────────────────────────────────

foreach ($p in $picked) {
    $tmp = Join-Path $OutputFolder "$($p.Asset).tmp"
    Invoke-Download -Uri $p.Url -OutFile $tmp -What "$System $($p.Asset)" -UserAgent $UA -TimeoutSec 180

    # The same three checks as sync-csrd2: a size floor for an error body, the ZIP magic for an
    # HTML page of plausible size, and opening it for a truncation that keeps the header.
    $size = (Get-Item $tmp).Length
    if ($size -lt $p.Kind.MinBytes) {
        Remove-Item $tmp -Force
        throw "$($p.Asset) is $size bytes, under the $($p.Kind.MinBytes) floor — an error response, not the file."
    }
    $magic = [System.IO.File]::ReadAllBytes($tmp)[0..1]
    if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
        Remove-Item $tmp -Force
        throw "$($p.Asset) is not a ZIP container (magic: $($magic -join ' '))."
    }
    $names = $null
    try {
        $zip = [System.IO.Compression.ZipFile]::OpenRead($tmp)
        try { $names = @($zip.Entries | ForEach-Object { $_.Name }) } finally { $zip.Dispose() }
    }
    catch {
        Remove-Item $tmp -Force
        throw "$($p.Asset) will not open — $($_.Exception.Message)"
    }
    if (-not ($names | Where-Object { $_ -like $p.Kind.Entry })) {
        Remove-Item $tmp -Force
        throw "$($p.Asset) holds no entry like '$($p.Kind.Entry)' — got: $($names -join ', ')"
    }

    $p | Add-Member Hash (Get-FileHash $tmp -Algorithm SHA256).Hash
    $final = Join-Path $OutputFolder $p.Asset
    if (Test-Path $final) { Remove-Item $final -Force }
    Move-Item $tmp $final
}

# ─── Change detection ─────────────────────────────────────────────────────────
#
# On content, not on the names: a file can be replaced under the same name (the undated ones can
# only change that way), and a new name can carry identical bytes.

$tag         = "be-$($System.ToLowerInvariant())"
$versionFile = Join-Path $OutputFolder "$tag-version.txt"
$lines = foreach ($p in ($picked | Sort-Object Asset)) { "$($p.Asset)=$($p.Hash) $($p.Edition ?? 'undated') $($p.Name)" }

if (-not $Force -and (Test-Path $versionFile)) {
    $stored = ((Get-Content $versionFile -Raw) -split "`n" | ForEach-Object { ($_ -split ' ')[0].Trim() } | Where-Object { $_ }) -join "`n"
    $fresh  = ($lines | ForEach-Object { ($_ -split ' ')[0] }) -join "`n"
    if ($stored -eq $fresh) {
        Write-Host "$System documentation unchanged since the last run — nothing to publish."
        # The workflow publishes on the presence of the assets, so they go.
        foreach ($p in $picked) { Remove-Item (Join-Path $OutputFolder $p.Asset) -Force }
        exit 0
    }
    Write-Host "$System documentation changed since the last run."
}

($lines -join "`n") | Set-Content $versionFile -NoNewline
# Beside the assets rather than among them: the workflow uploads the folder, and the notes are the
# release's description, not a file anyone downloads.
$config.Notes | Set-Content (Join-Path (Split-Path $OutputFolder -Parent) "$tag-notes.md")
$config.Title | Set-Content (Join-Path (Split-Path $OutputFolder -Parent) "$tag-title.txt") -NoNewline

Write-Host "$System documentation ready to publish:"
$lines | ForEach-Object { Write-Host "  $_" }
