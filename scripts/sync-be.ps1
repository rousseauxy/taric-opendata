# Downloads Belgian TARBEL tariff extractions directly from the Federal Public Service
# Finance portal (minfin). This is a direct scraper — taric-opendata no longer mirrors
# rousseauxy/tarbel-opendata; the same JSF scraping logic lives in both repos.
#
# Source: https://eservices.minfin.fgov.be/extTariffBrowser/XmlExtractions
# The portal is a JavaServer Faces (JSF/PrimeFaces) app requiring stateful, multi-step
# form submissions: (1) load page + extract ViewState + jsessionid, (2) AJAX POST to
# populate the results datatable for the current year/month, (3) a browser-style
# navigation POST per file to trigger the actual download.
#
# Per run it fetches: this month's export ZIPs (full on the 1st + daily deltas),
# plus the static XML-Document.zip (schema docs) and listed_currencies.xlsx.
# Files already present in the release (passed via -SkipFiles) or on disk are skipped
# unless -Force.

param(
    [string]   $OutputFolder = "downloads/be",
    [string]   $BaseUrl      = "https://eservices.minfin.fgov.be/extTariffBrowser",
    [string[]] $SkipFiles    = @(),
    [switch]   $Force,
    [switch]   $Debug
)

$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$UA   = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36"
$Host_ = "https://eservices.minfin.fgov.be"

Write-Host "=== TARBEL XML Downloader ===" -ForegroundColor Cyan
Write-Host "Target: $BaseUrl/XmlExtractions`n" -ForegroundColor Gray

# Extract ViewState from a JSF page (full HTML or AJAX partial). Optionally scoped to a form id.
function Get-JSFViewState {
    param([string]$HtmlContent, [string]$FormId = $null)
    if ($FormId) {
        $escapedFormId = [regex]::Escape($FormId)
        if ($HtmlContent -match "(?s)<form[^>]*id=`"$escapedFormId`"[^>]*>.*?<input[^>]*name=`"javax\.faces\.ViewState`"[^>]*value=`"([^`"]+)`"[^>]*/>") {
            return $matches[1]
        }
    }
    if ($HtmlContent -match 'javax\.faces\.ViewState[^>]*value="([^"]+)"') { return $matches[1] }
    if ($HtmlContent -match '(?s)javax\.faces\.ViewState[^>]*>\s*<!\[CDATA\[(.+?)\]\]>') { return $matches[1] }
    return $null
}

# Download a static portal file (documentation / currencies), honouring SkipFiles/Force.
function Get-StaticFile {
    param([string]$FileName, [string]$Url)
    $outPath = Join-Path $OutputFolder $FileName
    if (-not $Force -and ($SkipFiles -contains $FileName)) { Write-Host "  $FileName already in release, skipping" -ForegroundColor Gray; return }
    if (-not $Force -and (Test-Path $outPath))            { Write-Host "  $FileName already on disk, skipping"  -ForegroundColor Yellow; return }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $outPath -UseBasicParsing -UserAgent $UA -ErrorAction Stop
        Write-Host ("  Downloaded {0}: {1:N2} KB" -f $FileName, ((Get-Item $outPath).Length / 1KB)) -ForegroundColor Green
    } catch {
        Write-Host "  Failed $FileName : $($_.Exception.Message)" -ForegroundColor Red
    }
}

try {
    # ─── Step 1: initial page → ViewState + jsessionid ────────────────────────
    Write-Host "[1/3] Loading initial page and extracting form data..." -ForegroundColor Cyan
    $currentDate = Get-Date -Format "yyyyMMdd"
    $response = Invoke-WebRequest -Uri "$BaseUrl/XmlExtractions?date=$currentDate&lang=EN" `
        -UseBasicParsing -SessionVariable session -UserAgent $UA -ErrorAction Stop

    if ($Debug) { $response.Content | Out-File "$env:TEMP\initial-page.html" -Encoding UTF8 }

    $viewState = Get-JSFViewState -HtmlContent $response.Content
    if (-not $viewState) { throw "Could not extract JSF ViewState from page" }

    $formActionUrl = "$BaseUrl/XmlExtractions"
    if ($response.Content -match 'action="(/extTariffBrowser/XmlExtractions;jsessionid=[^"]+)"') {
        $formActionUrl = "$Host_$($matches[1])"
    }
    Write-Host "  Successfully extracted form state / session" -ForegroundColor Green

    # ─── Step 2: AJAX search for the current year/month ───────────────────────
    $searchYear  = (Get-Date).Year
    $monthStr    = (Get-Date).Month.ToString('00')
    Write-Host "`n[2/3] Searching for Year: $searchYear, Month: $monthStr..." -ForegroundColor Cyan

    $allDownloadLinks = @()
    try {
        Write-Host "  Searching: $searchYear-$monthStr..." -NoNewline
        $searchUrl = "$BaseUrl/XmlExtractions?date=$currentDate&lang=EN&page=1&searchMonth=$monthStr&searchYear=$searchYear"
        $searchResponse = Invoke-WebRequest -Uri $searchUrl -WebSession $session -UseBasicParsing -ErrorAction Stop

        if ($searchResponse.Content -match 'action="(/extTariffBrowser/XmlExtractions;jsessionid=[^"]+)"') {
            $formActionUrl = "$Host_$($matches[1])"
        }
        $viewState = Get-JSFViewState -HtmlContent $searchResponse.Content

        # Trigger the AJAX status form that PrimeFaces uses to populate results
        if ($searchResponse.Content -match '(j_idt\d+):ajaxStatusForm:(j_idt\d+)') {
            $ajaxSourceId = "$($matches[1]):ajaxStatusForm:$($matches[2])"
            $ajaxFormId   = "$($matches[1]):ajaxStatusForm"

            $ajaxFormViewState = Get-JSFViewState -HtmlContent $searchResponse.Content -FormId $ajaxFormId
            if (-not $ajaxFormViewState) { $ajaxFormViewState = $viewState }

            $ajaxBody = @{
                'javax.faces.partial.ajax'    = 'true'
                'javax.faces.source'          = $ajaxSourceId
                'javax.faces.partial.execute' = $ajaxSourceId
                'javax.faces.partial.render'  = 'xmlExtractionsControllerForm:resultsContainer xmlExtractionsControllerForm:downloadBtn'
                $ajaxSourceId                 = $ajaxSourceId
                $ajaxFormId                   = $ajaxFormId
                'javax.faces.ViewState'       = $ajaxFormViewState
            }
            $ajaxHeaders = @{ 'Faces-Request' = 'partial/ajax'; 'X-Requested-With' = 'XMLHttpRequest' }

            $searchResponse = Invoke-WebRequest -Uri $formActionUrl -Method Post -Body $ajaxBody `
                -Headers $ajaxHeaders -ContentType "application/x-www-form-urlencoded; charset=UTF-8" `
                -WebSession $session -UseBasicParsing -ErrorAction Stop
        }

        if ($Debug) { $searchResponse.Content | Out-File "$env:TEMP\ajax-response-$searchYear-$monthStr.html" -Encoding UTF8 }

        if ($searchResponse.Content -notmatch 'ui-datatable' -or $searchResponse.Content -match 'No search results') {
            Write-Host " No files found" -ForegroundColor Gray
        } else {
            $pattern = '<a\s+id="(xmlExtractionsControllerForm:j_idt\d+:\d+:downloadXmlBtn)"[^>]*>([^<]+\.zip)</a>'
            $found = [regex]::Matches($searchResponse.Content, $pattern)
            if ($found.Count -gt 0) {
                Write-Host " Found $($found.Count) file(s)" -ForegroundColor Green
                foreach ($m in $found) {
                    $allDownloadLinks += @{ FileName = $m.Groups[2].Value; ButtonId = $m.Groups[1].Value; Year = $searchYear; Month = $monthStr }
                }
            } else {
                Write-Host " No extraction files found" -ForegroundColor Gray
            }
        }

        $newViewState = Get-JSFViewState -HtmlContent $searchResponse.Content
        if ($newViewState) { $viewState = $newViewState }
    } catch {
        Write-Host " Error: $($_.Exception.Message)" -ForegroundColor Red
    }

    # ─── Step 3: download each extraction file (browser-style navigation POST) ─
    Write-Host "`n[3/3] Downloading extraction file(s)..." -ForegroundColor Cyan
    $downloaded = 0; $skipped = 0; $failed = 0

    foreach ($link in $allDownloadLinks) {
        $outputPath = Join-Path $OutputFolder $link.FileName
        Write-Host "`n  [$($link.Year)-$($link.Month)] $($link.FileName)" -ForegroundColor Cyan

        if (-not $Force -and ($SkipFiles -contains $link.FileName)) {
            Write-Host "    Already in release, skipping" -ForegroundColor Gray; $skipped++; continue
        }
        if ((Test-Path $outputPath) -and -not $Force) {
            Write-Host "    Already on disk (use -Force to overwrite)" -ForegroundColor Yellow; $skipped++; continue
        }

        try {
            # PrimeFaces monitorDownload sets this cookie before submitting the form
            $session.Cookies.Add((New-Object System.Net.Cookie("primefaces.download", "null", "/", "eservices.minfin.fgov.be")))

            $encodedButtonId  = [uri]::EscapeDataString($link.ButtonId)
            $encodedViewState = [uri]::EscapeDataString($viewState)
            $formBody = "xmlExtractionsControllerForm=xmlExtractionsControllerForm" `
                + "&xmlExtractionsControllerForm%3AyearField=$($link.Year)" `
                + "&xmlExtractionsControllerForm%3AmonthField=$($link.Month)" `
                + "&javax.faces.partial.ajax=false" `
                + "&javax.faces.ViewState=$encodedViewState" `
                + "&$encodedButtonId=$encodedButtonId"

            # Navigation (non-AJAX) headers — required to get the file, not an XML partial
            $downloadHeaders = @{
                'Accept'                    = 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'
                'Cache-Control'             = 'max-age=0'
                'Origin'                    = $Host_
                'Referer'                   = "$BaseUrl/XmlExtractions?date=$currentDate&lang=EN&page=1&searchMonth=$($link.Month)&searchYear=$($link.Year)"
                'Sec-Fetch-Dest'            = 'document'
                'Sec-Fetch-Mode'            = 'navigate'
                'Sec-Fetch-Site'            = 'same-origin'
                'Sec-Fetch-User'            = '?1'
                'Upgrade-Insecure-Requests' = '1'
            }
            $session.Headers.Remove('X-Requested-With') | Out-Null
            $session.Headers.Remove('Faces-Request') | Out-Null

            $tempResponse = Invoke-WebRequest -Uri $formActionUrl -Method Post -Headers $downloadHeaders `
                -ContentType 'application/x-www-form-urlencoded' -Body $formBody -WebSession $session `
                -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue

            $contentType = $tempResponse.Headers['Content-Type']
            if ($contentType -like '*application/zip*' -or $contentType -like '*application/octet-stream*') {
                [System.IO.File]::WriteAllBytes($outputPath, $tempResponse.Content)
                Write-Host ("    Downloaded: {0:N2} KB" -f ((Get-Item $outputPath).Length / 1KB)) -ForegroundColor Green
                $downloaded++
                $session.MaximumRedirection = -1
            } else {
                throw "Received '$contentType' instead of a file download"
            }
        } catch {
            Write-Host "    Failed: $($_.Exception.Message)" -ForegroundColor Red; $failed++
        }
    }

    # ─── Static files: schema docs + currency rates ───────────────────────────
    Write-Host "`n[+] Static files..." -ForegroundColor Cyan
    Get-StaticFile -FileName "XML-Document.zip"       -Url "$BaseUrl/FileResourceForHomePageServlet?fname=XML-Document.zip"
    Get-StaticFile -FileName "listed_currencies.xlsx" -Url "$BaseUrl/FileResourceForHomePageServlet?fname=listed_currencies.xlsx&lang=EN"

    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    Write-Host "Downloaded: $downloaded extraction file(s)" -ForegroundColor Green
    if ($skipped -gt 0) { Write-Host "Skipped: $skipped" -ForegroundColor Yellow }
    if ($failed  -gt 0) { Write-Host "Failed: $failed"  -ForegroundColor Red }
    Write-Host "Location: $OutputFolder" -ForegroundColor Gray
} catch {
    Write-Host "`nError: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.Exception.Response) { Write-Host "Status Code: $($_.Exception.Response.StatusCode.Value__)" -ForegroundColor Red }
    exit 1
}
