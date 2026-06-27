# taric-opendata — Claude Handoff Brief

## What this repo is

`taric-opendata` mirrors customs tariff data from multiple jurisdictions as GitHub Release assets,
so CustomsHive (and others) can download them without navigating government portals.

It was modelled on `rousseauxy/tarbel-opendata`, which already does this for Belgian minfin data.

## What's already implemented

Four daily GitHub Actions workflows, each following the same pattern:
1. Run a PowerShell script that downloads from the source into `downloads/{country}/`
2. Create a `{country}-YYYY-MM` GitHub Release if it doesn't exist
3. Upload any files not already in that release

| Workflow | Script | Source | Release tag |
|---|---|---|---|
| `sync-be.yml` | `scripts/sync-be.ps1` | Mirrors from `rousseauxy/tarbel-opendata` via GitHub API | `be-YYYY-MM` |
| `sync-nl.yml` | `scripts/sync-nl.ps1` | Dutch Belastingdienst DTV manifest XML | `nl-YYYY-MM` |
| `sync-gb.yml` | `scripts/sync-gb.ps1` | UK DBT Data API (`data.api.trade.gov.uk`) | `gb-YYYY-MM` |
| `sync-no.yml` | `scripts/sync-no.ps1` | Norwegian Tolletaten CKAN (`data.toll.no`) | `no-YYYY-MM` |

Look at any existing script + workflow pair to understand the pattern before adding FR.

## The task: add France (FR)

France customs (DGDDI) publishes tariff data via **RITA** (Référentiel Intégré Tarifaire Automatisé):
- Downloads page: `https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action`
- Overview: `https://www.douane.gouv.fr/service-en-ligne/tarif-douanier-communautaire-et-national-rita`

RITA is a **JSF (JavaServer Faces) web application** — the same stack as the Belgian minfin portal.
This means it likely uses ViewState tokens and possibly AJAX form submissions, similar to `tarbel-opendata/download.ps1`.

### What we don't yet know

The RITA downloads page returned HTTP 403 from the cloud environment where this was developed,
so the exact download mechanism has not been confirmed. You need to:

1. Open `https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action`
   in a browser with **DevTools → Network tab** open
2. Observe:
   - What files are listed (names, formats)
   - Whether downloads are direct `<a href>` links or triggered by form POST
   - What endpoint is called (URL, method, headers, body)
   - Whether a session cookie or ViewState token is required
3. Write `scripts/sync-fr.ps1` based on what you see, using the JSF session handling
   pattern from `rousseauxy/tarbel-opendata/download.ps1` if ViewState is needed

### What RITA is expected to contain

- EU TARIC base + French national measures (TVA, droits d'accise, autres taxes nationales)
- Covers all goods classifications applicable to French customs clearance

### IP blocking concern

GitHub Actions runners use Azure datacenter IPs. The RITA portal may block these.
Test by manually triggering `sync-fr.yml` from the Actions tab once implemented.
If it fails with 403/connection errors, options are:

- **Self-hosted runner**: add `runs-on: self-hosted` to `sync-fr.yml`, run the runner
  on a machine with a residential/EU IP (`gh actions-runner` setup)
- **Cron on own server**: run the script on any server you control and push releases
  via `gh release upload` with a PAT

The same concern applies to `sync-nl.yml` (NL DTV manifest) — test that one first
as an early indicator of whether portal-based sources work from GH Actions.

## Files to create

- `scripts/sync-fr.ps1` — download script (see pattern in other scripts)
- `.github/workflows/sync-fr.yml` — daily cron, release tag `fr-YYYY-MM`

Copy `.github/workflows/sync-no.yml` as the starting template for the workflow —
it's the simplest one. Only change the cron time (suggest `0 5 * * *`), the tag prefix (`fr-`),
the release title/notes, and the script call.

## Reference: script pattern

```powershell
param(
    [string]$OutputFolder = "downloads/fr",
    [switch]$Force
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force -Path $OutputFolder | Out-Null

# ... download logic here ...

Write-Host "Downloaded $($downloaded.Count) new file(s)"
```

Scripts must exit 0 on success (even if nothing new to download) so the workflow
`if: hashFiles('downloads/fr/*') != ''` condition correctly skips the release step
when there is nothing to upload.

## Testing locally

```powershell
# From repo root
pwsh scripts/sync-fr.ps1 -OutputFolder ./test-fr -Force
ls ./test-fr

# Also worth testing NL to verify manifest parsing works from your IP
pwsh scripts/sync-nl.ps1 -OutputFolder ./test-nl -Force
ls ./test-nl
```

## Repo location

`https://github.com/rousseauxy/taric-opendata`

Related repo (Belgium source): `https://github.com/rousseauxy/tarbel-opendata`
