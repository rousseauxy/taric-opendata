# Downloads French RITA (Référentiel Intégré Tarifaire Automatisé) tariff data.
# Source: https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action
# Plain HTML form — no JSF/ViewState, no session required. Stateless POST per file.
#
# Downloads:
#   1. 8 global reference XMLs (countries, add. codes, documents, preferences, regimes, etc.)
#   2. exportNomenc for all CN chapters → zipped into RITA_Nomenc.zip
#   3. exportNomencDroit for all CN chapters → zipped into RITA_NomencDroit.zip
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
    exportPref     = "RITA_Donnees_references_PRF.xml"   # Valid preference codes
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
        if ($r.Content -match 'Aucune donn|Fichier non|erreur interne') { Write-Warning "$($kv.Key): no data returned"; continue }
        Set-Content -Path $outPath -Value $r.Content -Encoding UTF8 -NoNewline
        $downloaded += $kv.Value
        Write-Host "  -> $([math]::Round((Get-Item $outPath).Length / 1KB)) KB"
    } catch { Write-Warning "Failed $($kv.Key): $_" }
}

# ─── 2. Nomenclature (exportNomenc) and Nomenclature+Duties (exportNomencDroit) ─

Add-Type -AssemblyName System.IO.Compression.FileSystem

Write-Host "`nFetching chapter list from RITA..."
$page     = Invoke-WebRequest -Uri $PageUrl -UserAgent $UA -UseBasicParsing -MaximumRedirection 10
$chapters = [regex]::Matches($page.Content, '<option[^>]*value="(\d{2})"') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique | Sort-Object
Write-Host "Found $($chapters.Count) chapters"

$nomTmp      = Join-Path $OutputFolder "_nomenc_tmp"
$nomDroitTmp = Join-Path $OutputFolder "_nomecdroit_tmp"
$nomZip      = Join-Path $OutputFolder "RITA_Nomenc.zip"
$nomDroitZip = Join-Path $OutputFolder "RITA_NomencDroit.zip"
New-Item -ItemType Directory -Force -Path $nomTmp      | Out-Null
New-Item -ItemType Directory -Force -Path $nomDroitTmp | Out-Null

$nomCount = 0; $droitCount = 0
foreach ($chp in $chapters) {
    Write-Host "  Chapter $chp..." -NoNewline
    try {
        # exportNomenc — CN structure + descriptions (chapitreCritere, no 'D')
        $r1 = Invoke-WebRequest -Uri $PageUrl -Method POST -ContentType "application/x-www-form-urlencoded" `
            -Body "expertsTelechargementsConversation.typeService=&expertsTelechargementsConversation.formatExport=$Format&expertsTelechargementsConversation.chapitreCritere.code=$chp&exportNomenc=T%C3%A9l%C3%A9charger" `
            -UserAgent $UA -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
        if ($r1.Content -notmatch 'Aucune donn|Fichier non|erreur interne') {
            Set-Content -Path (Join-Path $nomTmp "RITA_Nomenc_CHP$chp.xml") -Value $r1.Content -Encoding UTF8 -NoNewline
            $nomCount++
        }

        # exportNomencDroit — CN structure + French duty rates (chapitreCritereD, with 'D')
        $r2 = Invoke-WebRequest -Uri $PageUrl -Method POST -ContentType "application/x-www-form-urlencoded" `
            -Body "expertsTelechargementsConversation.typeService=&expertsTelechargementsConversation.formatExport=$Format&expertsTelechargementsConversation.chapitreCritereD.code=$chp&exportNomencDroit=T%C3%A9l%C3%A9charger" `
            -UserAgent $UA -UseBasicParsing -MaximumRedirection 10 -TimeoutSec 60
        if ($r2.Content -notmatch 'Aucune donn|Fichier non|erreur interne') {
            Set-Content -Path (Join-Path $nomDroitTmp "RITA_NomencDroit_CHP$chp.xml") -Value $r2.Content -Encoding UTF8 -NoNewline
            $droitCount++
        }

        $k1 = if ($nomCount -gt 0) { [math]::Round((Get-Item (Join-Path $nomTmp "RITA_Nomenc_CHP$chp.xml")).Length / 1KB) } else { 0 }
        $k2 = if ($droitCount -gt 0) { [math]::Round((Get-Item (Join-Path $nomDroitTmp "RITA_NomencDroit_CHP$chp.xml")).Length / 1KB) } else { 0 }
        Write-Host " nomenc=$k1 KB, droit=$k2 KB"
    } catch { Write-Host " FAILED: $_" }
}

if ($nomCount -gt 0) {
    if (Test-Path $nomZip) { Remove-Item $nomZip }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($nomTmp, $nomZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    $downloaded += "RITA_Nomenc.zip"
    Write-Host "Zipped $nomCount chapters → RITA_Nomenc.zip ($([math]::Round((Get-Item $nomZip).Length / 1MB, 1)) MB)"
}
if ($droitCount -gt 0) {
    if (Test-Path $nomDroitZip) { Remove-Item $nomDroitZip }
    [System.IO.Compression.ZipFile]::CreateFromDirectory($nomDroitTmp, $nomDroitZip, [System.IO.Compression.CompressionLevel]::Optimal, $false)
    $downloaded += "RITA_NomencDroit.zip"
    Write-Host "Zipped $droitCount chapters → RITA_NomencDroit.zip ($([math]::Round((Get-Item $nomDroitZip).Length / 1MB, 1)) MB)"
}

Remove-Item $nomTmp      -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $nomDroitTmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Downloaded: $($downloaded.Count) file(s)"
if ($skipped.Count -gt 0) { Write-Host "Skipped (already exist): $($skipped.Count)" }
