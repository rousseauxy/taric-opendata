<#
.SYNOPSIS
    Retrying HTTP for the sync scripts.

.DESCRIPTION
    Publishers time out. Not often, and never predictably: Norway's CKAN sits behind Cloudflare and
    returned three 522s in one run on 2026-08-08, DDS2 has dropped both an EU and an EBTI run, and
    every one of those was a healthy endpoint a minute later.

    A single unguarded call therefore loses a day's sync for a blip, and on a pipeline that has
    already had four separate "reported success while publishing nothing" bugs, people must not
    learn to ignore a red job.

    This lives in one file because the alternative is thirteen copies. The identical helper was
    written into sync-eu.ps1 and sync-ebti.ps1 on 2026-08-08 and nowhere else, which is how twelve
    scripts and roughly thirty HTTP calls were still unguarded when Norway fell over.
#>

Set-StrictMode -Version Latest

<#
.SYNOPSIS
    Runs a scriptblock, retrying with exponential backoff, and throws on the final attempt.

.DESCRIPTION
    Four attempts with 2, 4 and 8 second waits. It rethrows rather than returning a failure: a
    publisher that is genuinely down has to fail the job loudly rather than let it publish a
    partial release.

.PARAMETER NoRetryStatus
    HTTP status codes to give up on immediately instead of retrying, because they are an answer
    rather than a failure. Backing off three times over a 404 costs 14 seconds and cannot change
    the outcome — which matters where a miss is routine: sync-eurlex-full asks EUR-Lex for
    thousands of CELEX ids knowing many have no text in a given language, and sync-tr probes for
    a year page the Ministry may not have published yet.
#>
function Invoke-WithRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$What,
        [int]$Attempts = 4,
        [int[]]$NoRetryStatus = @()
    )
    for ($try = 1; $try -le $Attempts; $try++) {
        try { return & $Action }
        catch {
            if ($NoRetryStatus.Count -gt 0) {
                $response = $_.Exception.PSObject.Properties['Response']
                if ($response -and $response.Value) {
                    $status = [int]$response.Value.StatusCode
                    if ($NoRetryStatus -contains $status) { throw }
                }
            }
            if ($try -eq $Attempts) { throw }
            Write-Host "  $What retry $try after: $($_.Exception.Message)"
            Start-Sleep -Seconds ([math]::Pow(2, $try))
        }
    }
}

<#
.SYNOPSIS
    Downloads a URL to a path, retrying, and never leaves a partial file behind.

.DESCRIPTION
    The partial is removed BEFORE each attempt, which is load-bearing. Every download loop in this
    repo skips a file that already exists, so a retry that did not delete first would "succeed"
    against its own truncated copy and the next run would skip it as present. That trap is written
    up in the TaricHive plan for the EU and EBTI scripts; it applies identically here.
#>
function Invoke-Download {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$OutFile,
        [string]$What,
        [int]$TimeoutSec = 300,
        [hashtable]$Headers,
        [string]$UserAgent,
        # PowerShell's own default is 5. Exposed because EUR-Lex resolves a CELEX through a
        # longer redirect chain than that, and silently inheriting the default would turn a
        # working download into a failure that looks like the publisher's fault.
        [int]$MaximumRedirection = 5
    )
    if (-not $What) { $What = Split-Path $OutFile -Leaf }

    Invoke-WithRetry -What $What -Action {
        if (Test-Path $OutFile) { Remove-Item $OutFile -Force }
        # Not $args: that is PowerShell's automatic argument array, and assigning to it inside a
        # scriptblock is asking for a splat that carries something nobody put there.
        $req = @{
            Uri                = $Uri
            OutFile            = $OutFile
            UseBasicParsing    = $true
            TimeoutSec         = $TimeoutSec
            MaximumRedirection = $MaximumRedirection
        }
        if ($Headers)   { $req['Headers']   = $Headers }
        if ($UserAgent) { $req['UserAgent'] = $UserAgent }
        Invoke-WebRequest @req
    } | Out-Null
}

Export-ModuleMember -Function Invoke-WithRetry, Invoke-Download
