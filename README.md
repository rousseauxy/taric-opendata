# taric-opendata

Automated mirrors of customs tariff data from multiple jurisdictions, published as GitHub Release assets for machine-readable HTTP access without portal navigation.

[![Sync All Countries](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-all.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-all.yml)

## Where this lives

**GitHub is the source.** The sync workflows run there, and the release assets every consumer
reads — CustomsHive's Tarbel, BTI, EUR-Lex, ATaR and CS/RD2 importers, and TaricHive — are
GitHub releases. There is one repository and one set of releases on purpose: a second publisher
means two answers to "what is the current extract", and for a while there were two, with the
Forgejo copy carrying workflow changes GitHub did not have.

`forge.xact.cloud` is a **pull mirror**, configured on the Forgejo side to fetch this repository
on a schedule. That direction matters: a pull mirror is read-only and does not run Actions, so the
syncs cannot run twice or produce a second set of release assets that nobody reads. It mirrors the
files; the releases stay here.

The Forgejo-only experiments that predate this — running the syncs on the OCI runner, and
`scripts/release.sh`, which publishes to whichever forge the job happens to be running on — are
kept on the **`forgejo-experiment-2026-08`** tag of this repository. They were on Forgejo alone
until the mirror replaced it, which would have been the only copy.

A tag rather than a branch on purpose: a branch has GitHub offering a pull request for work that
will never be merged, every time anyone opens the repository.

## Countries

The **Status** badge shows each source's last daily run. Each source runs on its own schedule
(staggered through the 22:00–23:45 UTC window; `be` runs last, after minfin's nightly publish),
so its badge reflects a real run. **Sync All** is a manual convenience to run everything at
once. EUR-Lex full text is manual-only; `atar` runs weekly (Mondays) as it is a heavy scrape;
both are excluded from the daily window.

| Code | Jurisdiction | Source | Format | Release Tag | Status |
|------|-------------|--------|--------|-------------|--------|
| `be` | Belgium | [minfin TARBEL](https://eservices.minfin.fgov.be/extTariffBrowser/XmlExtractions) | ZIP/XML | `be-YYYY-MM` | [![be](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-be.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-be.yml) |
| `nl` | Netherlands | [Belastingdienst DTV](https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml) | ZIP/XML | `nl-YYYY-MM` | [![nl](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-nl.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-nl.yml) |
| `gb` | United Kingdom | [data.api.trade.gov.uk](https://data.api.trade.gov.uk/) | CSV | `gb-YYYY-MM` | [![gb](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-gb.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-gb.yml) |
| `no` | Norway | [data.toll.no](https://data.toll.no/dataset/customstariffstructure) | XML/JSON | `no-YYYY-MM` | [![no](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-no.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-no.yml) |
| `eu` | European Union | [CIRCABC (DG TAXUD)](https://circabc.europa.eu/) | ZIP/XML | `eu-YYYY-MM` | [![eu](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-eu.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-eu.yml) |
| `se` | Sweden | [Tullverket Tulltaxan](https://www.tullverket.se/) | ZIP/XML | `se-YYYY-MM` | [![se](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-se.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-se.yml) |
| `ch` | Switzerland | [BAZG datahub](https://www.bazg.admin.ch/) | ZIP/XML | `ch-YYYY-MM` | [![ch](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-ch.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-ch.yml) |
| `pl` | Poland | [ISZTAR4](https://www.podatki.gov.pl/) | ZIP | `pl-YYYY` | [![pl](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-pl.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-pl.yml) |
| `fr` | France | [RITA (Douane FR)](https://www.douane.gouv.fr/) | ZIP/XML | `fr-YYYY-MM` | [![fr](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-fr.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-fr.yml) |
| `us` | United States | [USITC HTS](https://hts.usitc.gov/) | JSON/CSV | `us-YYYY` | [![us](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-us.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-us.yml) |
| `ebti` | EU (BTI) | [DDS2 EBTI](https://ec.europa.eu/taxation_customs/dds2/ebti/) | ZIP/CSV | `ebti-YYYY` | [![ebti](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-ebti.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-ebti.yml) |
| `eurlex` | EU (legislation) | [CELLAR SPARQL](http://publications.europa.eu/webapi/rdf/sparql) | CSV (+ZIP) | `eurlex-YYYY-MM` | [![eurlex](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-eurlex-meta.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-eurlex-meta.yml) |
| `atar` | UK (rulings) | [GOV.UK ATaR](https://www.tax.service.gov.uk/search-for-advance-tariff-rulings/) | CSV | `atar-YYYY-MM` | [![atar](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-atar.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-atar.yml) |
| `csrd2` | EU (reference data) | [DDS2 CS/RD2](https://ec.europa.eu/taxation_customs/dds2/rd/) | ZIP/XML | `csrd2-YYYY-MM` | [![csrd2](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-csrd2.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-csrd2.yml) |
| `tr` | Türkiye | [Ticaret Bakanlığı (TGTC)](https://ggm.ticaret.gov.tr/) | XLS→CSV | `tr-YYYY` | [![tr](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-tr.yml/badge.svg)](https://github.com/rousseauxy/taric-opendata/actions/workflows/sync-tr.yml) |

## Data Contents

### Belgium (`be`)
EU TARIC + Belgian national measures (BTW, RBT, accijnzen). Scraped directly from the minfin
TARBEL JSF portal (see `scripts/sync-be.ps1`).
- `export-{date}-{date}.zip` — full monthly extraction (~1st of month)
- `export-{date}_{date}-{date}.zip` — daily delta
- `XML-Document.zip` — XML schema documentation
- `listed_currencies.xlsx` — currency rates

### Netherlands (`nl`)
EU TARIC + Dutch national measures (BTW, accijns). Sourced from the Belastingdienst DTV bulk download manifest. Arctic Group Tariff XML format.
- Full download (complete dataset)
- Incremental download (daily changes)

### United Kingdom (`gb`)
UK Global Tariff (post-Brexit). All 50 CSV tables per version from the UK Department for
Business and Trade — commodities, measures, quotas, regulations, certificates, geo areas and
footnotes (see the table list in `scripts/sync-gb.ps1`). Key files:
- `commodities-{version}.csv` — goods nomenclature and descriptions
- `measures-on-declarable-commodities-{version}.csv` — duties and restrictions per commodity
- `measures-as-defined-{version}.csv` — measures as defined in the tariff hierarchy

The DBT API mints a new version id (`v4.0.NNNN`) almost daily and each version is a **full**
~1 GB dump of all 50 tables, so the monthly release keeps only the newest
`KEEP_VERSIONS` (default 2) snapshots — older ones are pruned on each run. Every snapshot
carries the complete validity history, so point-in-time queries never need the pruned dailies.
Consumers should resolve the version from the filenames rather than pinning one.

### Norway (`no`)
Norwegian customs tariff structure and quotas (CC BY 4.0). From Tolletaten CKAN portal.
- `customstariffstructure.xml` / `.json` — commodity numbers, descriptions, duty rates
- `tollkvote.xml` / `.json` — customs quotas

### European Union (`eu`)
Official EU TARIC dataset published on CIRCABC by DG TAXUD. Authoritative source for all EU-27 member state tariffs.
- Full snapshot ZIP/XML containing measures, nomenclature, geographical areas, and reference tables

### Sweden (`se`)
Swedish customs tariff (Tulltaxan) published by Tullverket (Swedish Customs Authority).
- Full tariff ZIP in Arctic Group Tariff XML format

### Switzerland (`ch`)
Swiss customs tariff published by BAZG (Bundesamt für Zoll und Grenzsicherheit).
- Full tariff ZIP from the BAZG open data hub

### Poland (`pl`)
Polish customs tariff from ISZTAR4 (Informacyjny System Zintegrowanej Taryfy Celnej). Annual release.
- `isztar4-base.zip` — full base startup file (~7 GB)

### France (`fr`)
EU TARIC + French national measures (TVA, droits d'accise) via RITA (Référentiel Intégré Tarifaire Automatisé) published by Direction Générale des Douanes et Droits Indirects.
- Full tariff ZIP/XML export

### United States (`us`)
Harmonized Tariff Schedule of the United States published by USITC. Updated per revision (~10 revisions per year). Annual release tag.
- `hts-us.json` — full HTS in structured JSON (chapters 01–99)
- `hts-us.csv` — same data as flat CSV
- `hts-version.json` — version/revision marker

### EU legislation (`eurlex`)
EU secondary legislation sourced from the Publications Office **CELLAR** repository via its
public SPARQL endpoint (the sanctioned machine interface — `eur-lex.europa.eu`'s HTML frontend
is WAF-protected). Scope is **all of CELEX sector 3** — regulations, directives and decisions
(~233k acts). This covers every regulation a TARIC measure can reference (a
`GeneratingRegulationId` always maps to a sector-3 CELEX), so consumers join locally on CELEX
without any per-code lookup against CELLAR. Split into a daily **metadata** sync and a manual
**full-text** sync.
- `eurlex-manifest.csv` — one row per act (~233k, ~85 MB): CELEX, title, Official Journal id,
  document/entry-into-force/end-of-validity dates, in-force flag, resource type, ELI, and
  legal-act directory codes. Deep-link to EUR-Lex via
  `https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:{CELEX}`.
  Enumeration is partitioned by CELEX year to keep each SPARQL query small.
- `eurlex-version.txt` — change-detection sentinel (work count + max document date).
- `cnen-en.html` — the **consolidated CN Explanatory Notes (CNEN)**, English (CELEX
  `02019XC0329(02)`, latest consolidation resolved via CELLAR). Published by the daily metadata
  sync with its own `cnen-version.txt` sentinel, so it refreshes independently of the manifest.
  Notes are keyed by CN chapter/heading/subheading.
- `cn-notes.csv` — the **binding CN legal Section/Chapter notes** from Annex I to Regulation
  2658/87 (latest consolidation `01987R2658-YYYYMMDD` resolved via CELLAR, HTML parsed).
  Columns: `Kind` (`section`/`chapter`), `Code`, `SectionRoman`, `Title`, `NoteText`. Own
  `cn-notes-version.txt` sentinel (consolidation date). Consumed by TaricHive's EurLexImporter.
- `eurlex-text-{lang}.zip` — **manual only** (`Sync EUR-Lex legislation (full text)` workflow).
  Per-CELEX HTML full text, one language per zip. Use the `limit`/a filtered manifest — running
  full text over all ~233k acts is impractical (tens of GB). Older acts with no HTML
  manifestation (PDF/scan only) are skipped.

### EU customs reference data (`csrd2`)
DG TAXUD's **CS/RD2** — the customs office list and every reference code list, which is what
national customs applications validate declarations against. Two extracts from the same portal,
regenerated daily; the contents move only when a list actually changes, so change detection is a
SHA-256 of what came back rather than a version probe (see below).
- `COL-Generic.zip` — the **Customs Office List**: every office in the EU and the common-transit
  countries (4,283 on 2026-08-31), with country, UN/LOCODE, address, opening timetable, and the
  **roles** (`EXP` export, `EXT` exit, `DEP` departure, `DES` destination, `TRA` transit, `SCO`
  supervising) that say what each office may act as.
- `RD-Generic.zip` — **every reference code list**, as nine per-domain archives: CCI (import),
  AES (export), NCTS-P4/P5/P6 (transit), ECS-P2, ICS-P1, ICS2, and COMMON. Each is one XML of
  `RDEntity`/`RDEntry` with per-language descriptions. COMMON also carries `NationalCodes` — the
  member states' own supplements, keyed by country code.
- `csrd2-version.txt` — change-detection sentinel (snapshot date + SHA-256 of each asset).

**The date in the URL is a snapshot date, not a filename.** The service generates the extract on
demand at whatever date is asked for and answers `200` for a date that has not happened yet, so
there is nothing to `HEAD` and no listing to scrape — "has it moved" can only be answered after
downloading. That is cheap here (33 MB), and the same property is useful in reverse: a past date
returns the lists as they stood then. Pass `-SnapshotDate yyyyMMdd` to do so.

**The same list can differ between domains**, and not by rounding: `SupportingDocumentType` holds
333 codes under AES and 294 under CCI. A consumer merging blindly gets whichever domain it read
first; done properly, an export declaration is offered the AES list and an import the CCI one.

**Both extracts are a valid-at-snapshot-date view** — `ExtractValidReferenceData` — so codes that
have expired are simply absent rather than marked. A consumer that replaces its own copy wholesale
drops codes that historical declarations still reference; it needs to mark unseen entries inactive
and keep them.

### UK Advance Tariff Rulings (`atar`)
The GB analogue of EU BTIs, scraped from the GOV.UK **Search for Advance Tariff Rulings**
service (Open Government Licence). Unlike the GB tariff (`gb`, a CSV API) there is no bulk/API
feed, so the ruling pages are scraped: paginated enumeration of the search results
(`/search?page=N`, 25 rulings/page) then a per-ruling parse of each `/ruling/{id}` page. Runs
**weekly** (heavy scrape); change detection on the total ruling count makes an unchanged run a
fast no-op.
- `atar.csv` — one row per ruling: reference, commodity code, start/expiry dates, goods
  description, keywords, and grounds for classification.
- `atar-version.txt` — change-detection sentinel (total ruling count).

### Türkiye (`tr`)
The Turkish Customs Tariff (TGTC — *İstatistik Pozisyonlarına Bölünmüş Türk Gümrük Tarife
Cetveli*), published annually by the Ministry of Trade as a zip of per-chapter legacy `.xls`
files. The sync resolves the latest zip from `ggm.ticaret.gov.tr`, extracts the nomenclature
chapters and the section/chapter notes, and parses both with Python + `xlrd`
([`parse-tgtc.py`](scripts/parse-tgtc.py), [`parse-tgtc-notes.py`](scripts/parse-tgtc-notes.py)).
- `tr-nomenclature.csv` — one row per code: `CnCode` (12-digit GTİP, digits only),
  `DescriptionTR` (Turkish), `Unit`, `BaseDutyRate` (the base "474" MFN rate), `IndentLevel`.
  GTİP digits 1-8 = HS6 + EU CN, so consumers can borrow EU CN descriptions (EN/NL/FR/DE) for
  the aligned levels.
- `tr-notes.csv` — the binding Section (BÖLÜM) and Chapter (FASIL) legal notes: `Kind`
  (`section`/`chapter`), `Code` (section roman or 2-digit chapter), `SectionRoman`, `Title`,
  `NoteText` (Turkish; wrapped lines re-joined, note items split by newline). Section→chapter
  linkage uses the fixed HS mapping.
- `tr-measures.csv` — the **applied duty rates** from the Import Regime Decree annex lists
  (Karar 3350, "rejim YYYY.zip", lists I–VII; parsed with
  [`parse-regime.py`](scripts/parse-regime.py)): one row per GTİP × country-group column.
  Columns: `Code` (12-digit, zero-padded — the xlsx drops leading zeros), `Group` (column
  label, e.g. `AB, BK`, `GÜR`, `DÜ`), `Rate` (as published: number, `T1`/`T2` composition
  markers, `M`, …), `List`. The zip URL is resolved from `ggm.ticaret.gov.tr` with a pinned
  per-year fallback for CI; own `tr-regime-version.txt` sentinel.
- `tr-version.txt` — change-detection sentinel (the resolved TGTC zip URL).

## Usage

```bash
# Download current month's Belgium release
gh release download "be-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --dir ./be

# Download current month's EU TARIC
gh release download "eu-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --dir ./eu

# Download current UK tariff CSVs
gh release download "gb-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --pattern "commodities-*.csv" --dir ./gb

# Download US HTS (current year)
gh release download "us-$(date +%Y)" --repo rousseauxy/taric-opendata --dir ./us
```

## Relationship to tarbel-opendata

Belgian data (`be`) is scraped directly from the minfin TARBEL portal by `scripts/sync-be.ps1`,
which carries the same JSF scraping logic as the standalone
[tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata) repo. taric-opendata no longer
mirrors tarbel-opendata's releases — both run the same scraper independently. tarbel-opendata
remains as a Belgium-only mirror; this repo publishes `be` alongside all other jurisdictions
under the unified `{country}-YYYY-MM` release scheme.

## Licence

The **code** in this repository (sync scripts, parsers, workflows) is [MIT](LICENSE).

The **data** published as Release assets is not ours — it is mirrored from national and EU customs
authorities and stays under each source's own terms. Some sources are explicitly open (`gb`/`atar`
OGL v3.0, `no` CC BY 4.0, `us` public domain, `eu`/`ebti`/`eurlex` under the EU reuse decision);
others publish openly but state no reuse licence. Per-source status, required attribution, and a
takedown contact are in [DATA-LICENSES.md](DATA-LICENSES.md).

These mirrors are **not an authentic source of tariff law** — verify against the official source
before relying on them.

## Related projects

- [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata) — Belgian minfin data source
- TaricHive — multi-country tariff database that consumes these releases (SQL Server + .NET API)
