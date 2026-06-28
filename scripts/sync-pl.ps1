# Downloads Polish ISZTAR4 tariff startup file (EU TARIC + Polish national tariff).
# Source: https://ext-isztar4.mf.gov.pl/taryfa_celna/XmlExtractions
# The page uses JSF/PrimeFaces: GET page → AJAX consent checkbox → AJAX download button.
# Response is a ZIP (~220 MB) containing base-YYYYMMDDTHHMMSS.xml (~7.7 GB uncompressed).
param(
    [string]$OutputFolder = "downloads/pl",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$PageUrl   = "https://ext-isztar4.mf.gov.pl/taryfa_celna/XmlExtractions?lang=EN&date=$(Get-Date -Format 'yyyyMMdd')"
$OutFile   = Join-Path $OutputFolder "isztar4-base.zip"
$HashFile  = Join-Path $OutputFolder "isztar4-base.zip.sha256"

# Step 1: GET page — extract form action URL (contains jsessionid) and ViewState
Write-Host "Loading ISZTAR4 XmlExtractions page..."
$page = Invoke-WebRequest -Uri $PageUrl -UseBasicParsing -MaximumRedirection 10 -SessionVariable sess

$formAction = [regex]::Match($page.Content, '<form[^>]+action="(/taryfa_celna/XmlExtractions[^"]+)"').Groups[1].Value
if (-not $formAction) { throw "Could not find form action URL" }
if (-not ($page.Content -match 'javax\.faces\.ViewState[^>]*value="([^"]+)"')) { throw "Could not find ViewState" }
$vs = $matches[1]

$postUrl = "https://ext-isztar4.mf.gov.pl$formAction"
Write-Host "Session established (jsessionid in form action)"

# Step 2: AJAX POST — check the data-protection consent checkbox to enable the download button
Write-Host "Accepting data-protection terms (checkbox AJAX)..."
$ajaxResp = Invoke-WebRequest -Uri $postUrl -Method POST -ContentType "application/x-www-form-urlencoded" `
    -Body ("xmlExtractionsControllerForm=xmlExtractionsControllerForm" +
           "&xmlExtractionsControllerForm%3ArememberMe_input=on" +
           "&javax.faces.ViewState=$([Uri]::EscapeDataString($vs))" +
           "&javax.faces.partial.ajax=true" +
           "&javax.faces.partial.event=valueChange" +
           "&javax.faces.source=xmlExtractionsControllerForm%3ArememberMe" +
           "&javax.faces.partial.execute=xmlExtractionsControllerForm%3ArememberMe" +
           "&javax.faces.partial.render=xmlExtractionsControllerForm%3AdownloadBtn") `
    -UseBasicParsing -WebSession $sess -MaximumRedirection 5 `
    -Headers @{ "Faces-Request" = "partial/ajax"; "X-Requested-With" = "XMLHttpRequest" }

if ($ajaxResp.Content -match '<update id="j_id1:javax\.faces\.ViewState[^"]*"><!\[CDATA\[(.+?)\]\]></update>') {
    $vs2 = $matches[1]
} else {
    throw "Could not extract updated ViewState from checkbox AJAX response"
}

# Step 3: AJAX POST — click download button; server streams ZIP as response
Write-Host "Requesting startup file download (this takes a few minutes — generating 7+ GB XML on-the-fly)..."
$tmpFile = Join-Path $OutputFolder "isztar4-base.zip.tmp"
Invoke-WebRequest -Uri $postUrl -Method POST -ContentType "application/x-www-form-urlencoded" `
    -Body ("xmlExtractionsControllerForm=xmlExtractionsControllerForm" +
           "&xmlExtractionsControllerForm%3ArememberMe_input=on" +
           "&xmlExtractionsControllerForm%3AdownloadBtn=xmlExtractionsControllerForm%3AdownloadBtn" +
           "&javax.faces.ViewState=$([Uri]::EscapeDataString($vs2))" +
           "&javax.faces.partial.ajax=true" +
           "&javax.faces.partial.event=action" +
           "&javax.faces.source=xmlExtractionsControllerForm%3AdownloadBtn" +
           "&javax.faces.partial.execute=xmlExtractionsControllerForm" +
           "&javax.faces.partial.render=xmlExtractionsControllerForm%3AdownloadBtn") `
    -UseBasicParsing -WebSession $sess -MaximumRedirection 5 `
    -Headers @{ "Faces-Request" = "partial/ajax"; "X-Requested-With" = "XMLHttpRequest" } `
    -OutFile $tmpFile -TimeoutSec 600

$tmpSz = (Get-Item $tmpFile).Length
if ($tmpSz -lt 1MB) { Remove-Item $tmpFile; throw "Download looks too small ($tmpSz bytes) — probably an error response" }

# Verify it starts with the ZIP magic bytes (PK\x03\x04)
$magic = [System.IO.File]::ReadAllBytes($tmpFile)[0..3]
if ($magic[0] -ne 0x50 -or $magic[1] -ne 0x4B) {
    Remove-Item $tmpFile; throw "Downloaded file is not a ZIP (magic: $($magic -join ' '))"
}

# Change detection: compare SHA256 with previously stored hash
$newHash = (Get-FileHash $tmpFile -Algorithm SHA256).Hash
$needsUpload = $true
if (-not $Force -and (Test-Path $HashFile)) {
    $storedHash = (Get-Content $HashFile -Raw).Trim()
    if ($storedHash -eq $newHash) {
        Write-Host "Startup file unchanged (SHA256 match) — skipping"
        Remove-Item $tmpFile
        $needsUpload = $false
    }
}

if ($needsUpload) {
    if (Test-Path $OutFile) { Remove-Item $OutFile }
    Move-Item $tmpFile $OutFile
    $newHash | Set-Content $HashFile
    Write-Host "Saved: $([math]::Round((Get-Item $OutFile).Length / 1MB, 1)) MB → $OutFile"
}
