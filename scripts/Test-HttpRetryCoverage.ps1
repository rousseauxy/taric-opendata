<#
.SYNOPSIS
    Fails if any sync script makes an HTTP call that is not wrapped in a retry.

.DESCRIPTION
    This check exists because the sweep has already been done by hand twice and missed things
    both times.

    98240ca wrote a retry helper into sync-eu.ps1 and sync-ebti.ps1 and nowhere else. f29764b then
    moved it into lib/Http.psm1 and wired up ch, gb, no, tr and us — its own commit message says
    twelve scripts were unguarded, and it reached five of them. sync-fr was one of the seven left
    behind, and on 2026-08-09 and 2026-08-10 it failed three times: twice because RITA timed out
    on the one call with no try/catch, once leaving the release holding two files from one day and
    eight from another.

    Nothing detected any of that. A missing retry is invisible until a publisher blips, and by
    then the cost is a red job people learn to ignore or, worse, a part-published release.

    It walks the AST rather than grepping, because grep is what got the count wrong when this was
    last measured: a script with its own inline retry loop looks unguarded to a pattern searching
    for the helper's name, and a call inside a -Action scriptblock looks unguarded to a pattern
    matching line by line. The parent chain answers it exactly.
#>
[CmdletBinding()]
param(
    [string]$ScriptDirectory = (Join-Path $PSScriptRoot '.')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$httpCommands  = @('Invoke-WebRequest', 'Invoke-RestMethod')
$retryCommands = @('Invoke-WithRetry', 'Invoke-Download')

$failures = [System.Collections.Generic.List[string]]::new()
$checked  = 0
$guarded  = 0

# @() because a single match comes back as a scalar FileInfo, and under Set-StrictMode reading
# .Count off one of those is a terminating error — which is how the first run of this check
# failed, on the very case it was written to catch.
$files = @(Get-ChildItem -Path $ScriptDirectory -Filter 'sync-*.ps1' -File | Sort-Object Name)

if ($files.Count -eq 0) { throw "No sync-*.ps1 found under $ScriptDirectory — wrong path?" }

foreach ($file in $files) {
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$null, [ref]$parseErrors)

    # A script that does not parse cannot be reasoned about, and would otherwise pass this check
    # silently by having no findable commands at all.
    if (@($parseErrors).Count -gt 0) {
        foreach ($e in $parseErrors) {
            $failures.Add("$($file.Name):$($e.Extent.StartLineNumber) does not parse — $($e.Message)")
        }
        continue
    }

    $calls = $ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    foreach ($call in $calls) {
        $name = $call.GetCommandName()
        if (-not $name -or $name -notin $httpCommands) { continue }
        $checked++

        # Walk outward. A guarded call sits inside the scriptblock passed to the helper, so the
        # helper's own CommandAst is an ancestor of it.
        $isGuarded = $false
        $parent = $call.Parent
        while ($parent) {
            if ($parent -is [System.Management.Automation.Language.CommandAst]) {
                $parentName = $parent.GetCommandName()
                if ($parentName -and $parentName -in $retryCommands) { $isGuarded = $true; break }
            }
            $parent = $parent.Parent
        }

        if ($isGuarded) { $guarded++ }
        else {
            $failures.Add(
                "$($file.Name):$($call.Extent.StartLineNumber) bare $name — wrap it in " +
                "Invoke-WithRetry, or use Invoke-Download if it writes a file")
        }
    }
}

Write-Host "Checked $checked HTTP call(s) across $($files.Count) sync script(s); $guarded guarded."

if ($failures.Count -gt 0) {
    Write-Host ''
    foreach ($f in $failures) { Write-Host "  $f" }
    Write-Host ''
    throw "$($failures.Count) unguarded HTTP call(s). Every publisher blips; a single unretried call loses a day's sync."
}

Write-Host 'All HTTP calls in the sync scripts are retried.'
