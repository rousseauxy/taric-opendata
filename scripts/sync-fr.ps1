# Downloads French RITA (Référentiel Intégré Tarifaire Automatisé) tariff data.
# Source: https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action
# RITA is a JSF (PrimeFaces) application — downloads require ViewState + AJAX + form POST,
# same pattern as rousseauxy/tarbel-opendata/download.ps1.
#
# TODO: Complete download logic after inspecting RITA network calls in browser DevTools:
#   1. GET init.action → extract ViewState + jsessionid from form action URL
#   2. POST AJAX to trigger file listing (javax.faces.partial.ajax=true)
#   3. POST non-AJAX form submission per file to trigger download
param(
    [string]$OutputFolder = "downloads/fr",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$BaseUrl   = "https://www.douane.gouv.fr/rita-encyclopedie"
$PageUrl   = "$BaseUrl/public/experts/telechargements/init.action"
$UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

function Get-JSFViewState {
    param([string]$Html, [string]$FormId = $null)
    if ($FormId) {
        $esc = [regex]::Escape($FormId)
        if ($Html -match "(?s)<form[^>]*id=`"$esc`"[^>]*>.*?<input[^>]*name=`"javax\.faces\.ViewState`"[^>]*value=`"([^`"]+)`"") {
            return $matches[1]
        }
    }
    if ($Html -match 'javax\.faces\.ViewState[^>]*value="([^"]+)"') { return $matches[1] }
    if ($Html -match '(?s)javax\.faces\.ViewState[^>]*>\s*<!\[CDATA\[(.+?)\]\]>')    { return $matches[1] }
    return $null
}

Write-Host "Loading RITA downloads page..."
try {
    $page = Invoke-WebRequest -Uri $PageUrl -UserAgent $UserAgent -UseBasicParsing -SessionVariable session -MaximumRedirection 10
} catch {
    Write-Error "Failed to load RITA downloads page: $_"
    exit 1
}

$viewState = Get-JSFViewState -Html $page.Content
if (-not $viewState) {
    Write-Error "Could not extract JSF ViewState — page structure may have changed."
    exit 1
}

# Extract jsessionid-bearing form action URL (required for correct server-side routing)
$formActionUrl = $PageUrl
if ($page.Content -match 'action="(/rita-encyclopedie/[^"]+;jsessionid=[^"]+)"') {
    $formActionUrl = "https://www.douane.gouv.fr$($matches[1])"
}

Write-Host "ViewState extracted. Form action: $formActionUrl"

# TODO: Inspect RITA DevTools network tab to determine:
#
#   A) AJAX call that loads the file listing:
#      - javax.faces.source      = ??? (the PrimeFaces component ID that triggers the list)
#      - javax.faces.partial.execute = ???
#      - javax.faces.partial.render  = ??? (the results container component ID)
#
#   B) File listing pattern in the AJAX response:
#      - What HTML/component renders the file list?
#      - How to extract filename + button ID per file?
#
#   C) Download POST body per file:
#      - Form ID, button ID, any year/month/type fields
#
# Once known, implement steps 2 and 3 here following the tarbel-opendata pattern.
# Reference: https://github.com/rousseauxy/tarbel-opendata/blob/main/download.ps1

Write-Error "sync-fr.ps1: download logic not yet implemented — RITA was under outage during development. Complete TODOs above after inspecting browser DevTools on the RITA downloads page."
exit 1
