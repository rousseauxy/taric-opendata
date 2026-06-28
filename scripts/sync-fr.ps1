# Downloads French RITA (Référentiel Intégré Tarifaire Automatisé) tariff data.
# Source: https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action
# Plain HTML form — no JSF/ViewState, no session required. Stateless POST per file.
#
# Downloads:
#   1. 7 global reference XMLs (countries, additional codes, documents, regimes, etc.)
#   2. exportNomencDroit for all CN chapters → zipped into RITA_NomencDroit.zip
param(
    [string]$OutputFolder = "downloads/fr",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$PageUrl = "https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action"
$UA      = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
$Format  = "XML"

# ─── 1. Global reference files ───────────────────────────────────────────────

$globalExports = [ordered]@{
    exportPays     = "RITA_Donnees_references_GEO.xml"   # Countries / geographical areas
    exportCodAdd   = "RITA_Donnees_references_CAC.xml"   # Additional codes
    exportDocument = "RITA_Donnees_references_DOC.xml"   # Document references
    exportRenvoi   = "RITA_Donnees_references_RNV.xml"   # Renvoi (cross-references)
    exportCodCpta  = "RITA_Donnees_references_CTX.xml"   # Tax/accounting codes
    exportRegime   = "RITA_Donnees_references_RGD.xml"   # Customs regimes
    exportCodMesa  = "RITA_Donnees_references_UTM.xml"   # Units of measurement
}

$downloaded = @()
$skipped    = @()

foreach ($kv in $globalExports.GetEnumerator()) {
    $outPath = Join-Path $OutputFolder $kv.Value
    if (-not $Force -and (Test-Path $outPath)) {
        Write-Host "Already exists: $($kv.Value)"
        $skipped += $kv.Value
        continue
    }
    Write-Host "Downloading $($kv.Key) → $($kv.Value)..."
    try {
        $body = "expertsTelechargementsConversation.typeService=&expertsTelechargementsConversation.formatExport=$Format&$($kv.Key)=T%C3%A9l%C3%A9charger"
        $r = Invoke-WebRequest -Uri $PageUrl -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" `
            -UserAgent $UA -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
        if ($r.Content -match 'Aucune donn|Fichier non') { Write-Warning "$($kv.Key): no data returned"; continue }
        Set-Content -Path $outPath -Value $r.Content -Encoding UTF8 -NoNewline
        $downloaded += $kv.Value
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    } catch { Write-Warning "Failed $($kv.Key): $_" }
}

# ─── 2. Combined Nomenclature + duties (exportNomencDroit) per CN chapter ────

$nomZip = Join-Path $OutputFolder "RITA_NomencDroit.zip"
$nomTmp = Join-Path $OutputFolder "_nomenc_tmp"
New-Item -ItemType Directory -Force -Path $nomTmp | Out-Null

# Get chapter list from the live page
Write-Host "`nFetching chapter list from RITA..."
$page     = Invoke-WebRequest -Uri $PageUrl -UserAgent $UA -UseBasicParsing -MaximumRedirection 10
$chapters = [regex]::Matches($page.Content, '<option[^>]*value="(\d{2})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object
Write-Host "Found $($chapters.Count) chapters — downloading exportNomencDroit for each..."

$nomDownloaded = 0
foreach ($chp in $chapters) {
    $xmlPath = Join-Path $nomTmp "RITA_NomencDroit_CHP$chp.xml"
    Write-Host "  Chapter $chp..." -NoNewline
    try {
        $r = Invoke-WebRequest -Uri $PageUrl -Method POST -ContentType "application/x-www-form-urlencoded" `
            -Body "expertsTelechargementsConversation.typeService=&expertsTelechargementsConversation.formatExport=$Format&expertsTelechargementsConversation.chapitreCritereD.code=$chp&exportNomencDroit=T%C3%A9l%C3%A9charger" `
            -UserAgent $UA -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
        if ($r.Content -match 'Aucune donn|Fichier non') { Write-Host " (no data)"; continue }
        Set-Content -Path $xmlPath -Value $r.Content -Encoding UTF8 -NoNewline
        $nomDownloaded++
        Write-Host " $([math]::Round((Get-Item $xmlPath).Length / 1KB)) KB"
    } catch { Write-Host " FAILED: $_" }
}

if ($nomDownloaded -gt 0) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (Test-Path $nomZip) { Remove-Item $nomZip }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($nomTmp, $nomZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    $downloaded += "RITA_NomencDroit.zip"
    Write-Host "Zipped $nomDownloaded chapters → $([math]::Round((Get-Item $nomZip).Length / 1MB, 1)) MB"
}
Remove-Item $nomTmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Downloaded: $($downloaded.Count) file(s)"
if ($skipped.Count -gt 0) { Write-Host "Skipped (already exist): $($skipped.Count)" }
