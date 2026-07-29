# Data licences and attribution

The [MIT licence](LICENSE) in this repository covers the **code only** — the sync scripts in
[scripts/](scripts/), the parsers, and the workflows in [.github/workflows/](.github/workflows/).

The tariff data published as **GitHub Release assets is not ours**. Every asset is an unmodified
(or, where noted, mechanically reformatted) copy of a file obtained from a national or EU customs
authority, and it stays under that authority's own terms. This repository is a mirror, published to
make the same public files reachable over plain HTTP without portal navigation.

## Status of each source

`Status` says how confident we are that redistribution is permitted:

- **Open licence** — the source publishes under a named, machine-readable open licence.
- **EU reuse policy** — European Commission / Publications Office documents, covered by
  [Decision 2011/833/EU](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:32011D0833) on
  the reuse of Commission documents: reuse is authorised, attribution required, no endorsement
  implied.
- **Public domain** — not subject to copyright.
- **Not verified** — the source publishes the data openly and without authentication, but states no
  explicit reuse licence that we have confirmed. Mirrored as public-sector information. If you are
  the publisher and object, see [Takedown](#takedown).

| Code | Source | Status | Licence / basis | Required attribution |
|------|--------|--------|-----------------|----------------------|
| `gb` | [DBT Data API](https://data.api.trade.gov.uk/v1/datasets/uk-tariff-2021-01-01) — UK Department for Business and Trade | Open licence | [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) | "Contains public sector information licensed under the Open Government Licence v3.0." |
| `atar` | [GOV.UK Search for Advance Tariff Rulings](https://www.tax.service.gov.uk/search-for-advance-tariff-rulings/) — HMRC | Open licence | [Open Government Licence v3.0](https://www.nationalarchives.gov.uk/doc/open-government-licence/version/3/) | As above. |
| `no` | [data.toll.no](https://data.toll.no/dataset/customstariffstructure) — Tolletaten (Norwegian Customs) | Open licence | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) | "Tolletaten, CC BY 4.0." |
| `us` | [USITC HTS](https://hts.usitc.gov/) | Public domain | Work of the U.S. Government, [17 U.S.C. §105](https://www.law.cornell.edu/uscode/text/17/105) | None required; credit USITC as a courtesy. |
| `eu` | [CIRCABC (DG TAXUD)](https://circabc.europa.eu/) + [DDS2 TARIC daily publications](https://ec.europa.eu/taxation_customs/dds2/taric/daily_publications.jsp) | EU reuse policy | Decision 2011/833/EU | "© European Union, 1995–2026. Reuse authorised." |
| `ebti` | [DDS2 EBTI](https://ec.europa.eu/taxation_customs/dds2/ebti/) — DG TAXUD | EU reuse policy | Decision 2011/833/EU | As above. |
| `eurlex` | [CELLAR SPARQL endpoint](http://publications.europa.eu/webapi/rdf/sparql) — Publications Office of the EU | EU reuse policy | Decision 2011/833/EU | "© European Union, http://eur-lex.europa.eu, 1998–2026." Only the legislation published in the electronic Official Journal is authentic. |
| `be` | [minfin TARBEL](https://eservices.minfin.fgov.be/extTariffBrowser/XmlExtractions) — FPS Finance (Belgium) | Not verified | Belgian public-sector information; no explicit reuse licence stated on the extraction portal. | Credit "FOD Financiën / SPF Finances — TARBEL". |
| `nl` | [Belastingdienst DTV](https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml) | Not verified | Published by a Dutch public authority; Auteurswet art. 15b (works published by a public authority are freely reproducible unless copyright is expressly reserved) is believed to apply but has not been confirmed. | Credit "Belastingdienst / Douane — DTV". |
| `se` | [distr.tullverket.se](https://distr.tullverket.se/tulltaxan/xml/tot/) — Tullverket (Swedish Customs) | Not verified | Swedish authority publication; official documents are excluded from copyright under the Swedish Copyright Act §9, but the distribution service states no reuse licence. | Credit "Tullverket — Tulltaxan". |
| `ch` | [datahub.bazg.admin.ch](https://datahub.bazg.admin.ch/public-resources/) — BAZG (Swiss Customs) | Not verified | Published as a public resource without authentication; Swiss federal open data is normally "free use, attribution required", but the datahub carries no licence tag we have confirmed. | Credit "BAZG / OFDF — Tares". |
| `pl` | [ISZTAR4](https://ext-isztar4.mf.gov.pl/taryfa_celna/XmlExtractions) — Ministerstwo Finansów | Not verified | Polish public-sector information. The portal requires accepting a short acknowledgement before download (see [below](#the-isztar4-download-acknowledgement)) — it asserts ownership and informative character but imposes **no** restriction on redistribution. Data is jointly DG TAXUD (TARIC) and Ministry of Finance, so the EU half is additionally covered by Decision 2011/833/EU. | "Customs Tariff data is the property of European Commission DG TAXUD and the Ministry of Finance. The data is of informative character. Source: TARIC (DG TAXUD) and ISZTAR4 (Ministry of Finance)." |
| `fr` | [RITA](https://www.douane.gouv.fr/rita-encyclopedie/public/experts/telechargements/init.action) — DGDDI (French Customs) | Not verified | Published on douane.gouv.fr (not data.gouv.fr), so the Licence Ouverte / Etalab 2.0 that covers most French open data is not confirmed to apply here. | Credit "DGDDI — RITA". |
| `tr` | [ggm.ticaret.gov.tr](https://ggm.ticaret.gov.tr/) — Ticaret Bakanlığı (Ministry of Trade) | Not verified | Turkish official publication; no open-data licence is stated. The published `.xls` files are mechanically parsed to CSV here, so `tr-*.csv` are derived works, not verbatim copies. | Credit "T.C. Ticaret Bakanlığı — TGTC". |

### The ISZTAR4 download acknowledgement

`pl` is the only source that gates the download behind an explicit consent checkbox, which
[`sync-pl.ps1`](scripts/sync-pl.ps1) accepts programmatically. Its full text is:

> By downloading the Customs Tariff startup file, I acknowledge that:
> - Customs Tariff data is the property of European Commission DG TAXUD and Ministry of Finance.
> - The data is of informative character.
> - The source of information for startup file are TARIC (DG-TAXUD) and ISZTAR4 (Ministry of
>   Finance) systems.

It grants no licence, but it also asks for nothing beyond acknowledging ownership, informative
character, and provenance — all three of which this document and the disclaimer below carry
forward to anyone consuming the `pl` release.

## Derived files

Most assets are byte-for-byte copies of the upstream file. These are **not** — they are parsed or
reshaped by the scripts in this repo, so treat them as derived works of the upstream data (the
upstream terms still apply; the parsing logic is MIT):

- `tr-nomenclature.csv`, `tr-notes.csv`, `tr-measures.csv` — parsed from the TGTC and Import Regime
  `.xls` files ([`parse-tgtc.py`](scripts/parse-tgtc.py), [`parse-tgtc-notes.py`](scripts/parse-tgtc-notes.py), [`parse-regime.py`](scripts/parse-regime.py)).
- `atar.csv` — assembled from individual GOV.UK ruling pages.
- `eurlex-manifest.csv`, `cn-notes.csv` — assembled from CELLAR SPARQL results and parsed
  consolidated HTML.
- `hts-us.json` / `hts-us.csv` — as served by the USITC API, per chapter, concatenated.
- `se` `.xml.gz` — unpacked from the upstream PGP-armored (unencrypted, DEFLATE) container.

## Not authentic, no warranty

These mirrors are a convenience for machine access. They are **not** an official or authentic
source of tariff law. Files can be stale, partial, or wrong — a sync can fail, an upstream format
can change, and change-detection sentinels can miss an update. Do not rely on anything here for a
customs declaration, a duty calculation, or any legal or commercial decision without verifying
against the official source linked above. For EU legislation, only the electronic Official Journal
is authentic.

## Takedown

If you publish one of these sources and want the mirror removed, restricted, or corrected, open an
issue on this repository and it will be actioned — no argument, no delay.
