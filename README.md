# taric-opendata

Automated mirrors of customs tariff data from multiple jurisdictions, published as GitHub Release assets for machine-readable HTTP access without portal navigation.

## Countries

| Code | Jurisdiction | Source | Format | Release Tag |
|------|-------------|--------|--------|-------------|
| `be` | Belgium | [minfin Tarbel](https://github.com/rousseauxy/tarbel-opendata) | ZIP/XML | `be-YYYY-MM` |
| `nl` | Netherlands | [Belastingdienst DTV](https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml) | ZIP/XML | `nl-YYYY-MM` |
| `gb` | United Kingdom | [data.api.trade.gov.uk](https://data.api.trade.gov.uk/) | CSV | `gb-YYYY-MM` |
| `no` | Norway | [data.toll.no](https://data.toll.no/dataset/customstariffstructure) | XML/JSON | `no-YYYY-MM` |
| `eu` | European Union | [CIRCABC (DG TAXUD)](https://circabc.europa.eu/) | ZIP/XML | `eu-YYYY-MM` |
| `se` | Sweden | [Tullverket Tulltaxan](https://www.tullverket.se/) | ZIP/XML | `se-YYYY-MM` |
| `ch` | Switzerland | [BAZG datahub](https://www.bazg.admin.ch/) | ZIP/XML | `ch-YYYY-MM` |
| `pl` | Poland | [ISZTAR4](https://www.podatki.gov.pl/) | ZIP | `pl-YYYY` |
| `fr` | France | [RITA (Douane FR)](https://www.douane.gouv.fr/) | ZIP/XML | `fr-YYYY-MM` |
| `us` | United States | [USITC HTS](https://hts.usitc.gov/) | JSON/CSV | `us-YYYY` |

## Data Contents

### Belgium (`be`)
EU TARIC + Belgian national measures (BTW, RBT, accijnzen). Sourced via [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata).
- `export-{date}-{date}.zip` — full monthly extraction
- `export-{date}_{date}-{date}.zip` — daily delta

### Netherlands (`nl`)
EU TARIC + Dutch national measures (BTW, accijns). Sourced from the Belastingdienst DTV bulk download manifest. Arctic Group Tariff XML format.
- Full download (complete dataset)
- Incremental download (daily changes)

### United Kingdom (`gb`)
UK Global Tariff (post-Brexit). Three CSV tables per version from the UK Department for Business and Trade:
- `commodities-{version}.csv` — goods nomenclature and descriptions
- `measures-on-declarable-commodities-{version}.csv` — duties and restrictions per commodity
- `measures-as-defined-{version}.csv` — measures as defined in the tariff hierarchy

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

Belgian data (`be`) is sourced from [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata), which handles the complex minfin portal scraping. This repo mirrors it alongside all other jurisdictions under a unified `{country}-YYYY-MM` release scheme.

## Related projects

- [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata) — Belgian minfin data source
- TaricHive — multi-country tariff database that consumes these releases (SQL Server + .NET API)
