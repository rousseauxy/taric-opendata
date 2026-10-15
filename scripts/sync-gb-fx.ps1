# Fetches HMRC's monthly exchange rates (the rates used to convert a value to sterling for customs
# and VAT) for the last two years and the coming month, and writes them as one CSV:
# downloads/gb-fx/hmrc-exchange-rates.csv (release asset consumed by TaricHive's GbImporter, B-63).
#
# SOURCE: the UK Trade Tariff service publishes one CSV per month at
# /api/v2/exchange_rates/files/monthly_csv_YYYY-MM.csv ("Currency Units per £1", start and end
# date per row). Open Government Licence. The month ahead is usually published late in the month
# before; a 404 for it is expected and skipped, a 404 for a past month is an error.
#
# One combined file under a constant name, published with --replace: the newest month changes it
# every month, and the consumer replaces all of its GB rates on each import.
param(
    [string]$OutputFolder = "downloads/gb-fx",
    [int]   $Months       = 24
)

$ErrorActionPreference = "Stop"
Import-Module (Join-Path $PSScriptRoot 'lib/Http.psm1') -Force
$OutputFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputFolder)
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

$Base = "https://www.trade-tariff.service.gov.uk/api/v2/exchange_rates/files"
$UA   = "taric-opendata/1.0 (+https://github.com/rousseauxy/taric-opendata)"
$tmp  = Join-Path $OutputFolder "_month.csv"

$first = (Get-Date -Day 1).Date.AddMonths(-$Months + 1)
$last  = (Get-Date -Day 1).Date.AddMonths(1)
$rows  = [System.Collections.Generic.List[object]]::new()
$monthsRead = 0

for ($m = $first; $m -le $last; $m = $m.AddMonths(1)) {
    $ym  = $m.ToString('yyyy-MM')
    $url = "$Base/monthly_csv_$ym.csv"
    try {
        Invoke-WithRetry -What "HMRC rates $ym" -NoRetryStatus @(404) -Action {
            Invoke-WebRequest -Uri $url -UserAgent $UA -UseBasicParsing -TimeoutSec 60 -OutFile $tmp
        } | Out-Null
    } catch {
        $response = $_.Exception.PSObject.Properties['Response']
        $status = if ($response -and $response.Value) { [int]$response.Value.StatusCode } else { 0 }
        if ($status -eq 404 -and $m -eq $last) { Write-Host "HMRC rates ${ym}: not published yet"; continue }
        throw "HMRC rates ${ym}: $($_.Exception.Message)"
    }

    $parsed = Import-Csv $tmp
    if (-not $parsed -or -not ($parsed[0].PSObject.Properties.Name -contains 'Currency Code')) {
        throw "HMRC rates ${ym}: unexpected file (no 'Currency Code' column)"
    }
    foreach ($r in $parsed) {
        $start = [datetime]::ParseExact($r.'Start date'.Trim(), 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $end   = [datetime]::ParseExact($r.'End date'.Trim(), 'dd/MM/yyyy', [Globalization.CultureInfo]::InvariantCulture)
        $rows.Add([pscustomobject]@{
            CurrencyCode    = $r.'Currency Code'.Trim()
            Currency        = $r.Currency.Trim()
            Country         = $r.'Country/Territories'.Trim()
            UnitsPerGbp     = $r.'Currency Units per £1'.Trim()
            StartDate       = $start.ToString('yyyy-MM-dd')
            EndDate         = $end.ToString('yyyy-MM-dd')
        })
    }
    $monthsRead++
    Write-Host "HMRC rates ${ym}: $($parsed.Count) rows"
}
Remove-Item $tmp -ErrorAction SilentlyContinue

if ($monthsRead -lt $Months) { throw "Only $monthsRead of at least $Months months read." }
$out = Join-Path $OutputFolder "hmrc-exchange-rates.csv"
$rows | Export-Csv -Path $out -NoTypeInformation -Encoding utf8
Write-Host "Wrote $($rows.Count) rows over $monthsRead months to $out"
