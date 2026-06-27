# taric-opendata

Automated mirrors of customs tariff data from multiple jurisdictions, published as GitHub Release assets for machine-readable HTTP access without portal navigation.

## Countries

| Code | Jurisdiction | Source | Format | Update Frequency | Release Tag |
|------|-------------|--------|--------|-----------------|-------------|
| `be` | Belgium | [minfin Tarbel](https://github.com/rousseauxy/tarbel-opendata) | ZIP/XML | Daily | `be-YYYY-MM` |
| `nl` | Netherlands | [Belastingdienst DTV](https://download.belastingdienst.nl/douane_sw/tariff/download_bestanden.xml) | XML | Daily | `nl-YYYY-MM` |
| `gb` | United Kingdom | [data.api.trade.gov.uk](https://data.api.trade.gov.uk/) | CSV | Daily | `gb-YYYY-MM` |
| `no` | Norway | [data.toll.no](https://data.toll.no/dataset/customstariffstructure) | XML/JSON | Daily | `no-YYYY-MM` |

## Data Contents

### Belgium (`be`)
EU TARIC + Belgian national measures (BTW, RBT, accijnzen). Sourced via [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata).
- `export-{date}-{date}.zip` — full monthly extraction
- `export-{date}_{date}-{date}.zip` — daily delta

### Netherlands (`nl`)
EU TARIC + Dutch national measures (BTW, accijns). Sourced from Belastingdienst DTV bulk download manifest.
- Full download (complete dataset)
- Incremental download (daily changes)

### United Kingdom (`gb`)
UK Global Tariff (post-Brexit). Three CSV tables per version:
- `commodities-{version}.csv` — goods nomenclature and descriptions
- `measures-on-declarable-commodities-{version}.csv` — duties and restrictions per commodity
- `measures-as-defined-{version}.csv` — measures as defined in the tariff hierarchy

### Norway (`no`)
Norwegian customs tariff structure and quotas. CC BY 4.0 licence.
- `customstariffstructure.xml` / `.json` — commodity numbers, descriptions, duty rates
- `tollkvote.xml` / `.json` — customs quotas

## Usage

```bash
# Download current month's Belgium release
gh release download "be-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --dir ./be

# Download current month's UK CSVs
gh release download "gb-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --pattern "commodities-*.csv" --dir ./gb

# Download Norway tariff structure
gh release download "no-$(date +%Y-%m)" --repo rousseauxy/taric-opendata --pattern "customstariffstructure.*" --dir ./no
```

## Relationship to tarbel-opendata

Belgian data (`be`) is sourced from [tarbel-opendata](https://github.com/rousseauxy/tarbel-opendata), which handles the complex minfin portal scraping. This repo adds NL, GB, and NO alongside it under a unified `{country}-YYYY-MM` release scheme.
