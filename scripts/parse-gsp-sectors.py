#!/usr/bin/env python3
"""
Transcribes the Turkish Import Regime Decree's GSP product-group annexes (EK-2, EK-3, EK-4
inside "rejim YYYY.zip") into tr-gsp-sectors.csv.

These annexes are what the "HARİÇ SEKTÖRLER" column of EK-1 points at. EK-1 says Pakistan is
excluded from S-8b, S-11a and S-11b; these say what those sections contain. Without them the
country lists are unusable — a GSP membership with no exclusions overstates the preference.

  EK-2  GELİŞME YOLUNDAKİ ÜLKELER ÜRÜN GRUBU LİSTESİ            (GYÜ, developing countries)
  EK-3  ÖZEL TEŞVİK DÜZENLEMESİ KAPSAMINDAKİ ÜLKELER ...        (ÖTDÜ, special incentive)
  EK-4  EN AZ GELİŞMİŞ ÜLKELER ÜRÜN GRUBU LİSTESİ               (EAGÜ, least developed)

Columns: BÖLÜM (section, carried down over its rows) | FASIL | G.T.İ.P | EŞYA TANIMI | ÜRÜN GRUBU.
The scope cell is written three ways — "50. Fasıl" (a whole chapter), "42.02" (a heading),
"39.01 ila 39.21" (a range of headings) and "4418.21.10.00.11" (a full GTİP) — and this script
does NOT interpret any of them. It transcribes.

That is deliberate. This only exists because the annexes are legacy .xls (BIFF) and TaricHive's
importer, which reads every other part of the same archive directly, cannot open them. Deriving
here would put the semantics a layer above where the rest of TR's live, which is exactly the
arrangement that hid TR's losses for as long as it did. See parse-tgtc.py for the same rule
applied to the nomenclature.

Requires xlrd (legacy .xls). Usage: parse-gsp-sectors.py <rejim-zip> <output-csv>
"""
import csv
import io
import re
import sys
import zipfile

import xlrd

# Annex → the arrangement whose beneficiaries it applies to, as EK-1 names them.
ANNEXES = {
    "EK-2.xls": "GYÜ",
    "EK-3.xls": "ÖTDÜ",
    "EK-4.xls": "EAGÜ",
}

SECTION_RE = re.compile(r"^S-\d+[a-z]?$", re.IGNORECASE)


def cell(sheet, row, col):
    if col >= sheet.ncols:
        return ""
    v = sheet.cell_value(row, col)
    # xlrd hands back every number as a float, so the chapter column arrives as "50.0".
    if isinstance(v, float) and v == int(v):
        v = int(v)
    return re.sub(r"\s+", " ", str(v)).strip()


def header_row(sheet):
    for r in range(min(20, sheet.nrows)):
        if cell(sheet, r, 0).upper().startswith("BÖLÜM"):
            return r
    return None


def parse(sheet, annex, arrangement, out):
    head = header_row(sheet)
    if head is None:
        raise SystemExit(f"{annex}: no BÖLÜM header row found — the layout has changed.")

    section = None
    rows = 0
    for r in range(head + 1, sheet.nrows):
        first = cell(sheet, r, 0)
        if SECTION_RE.match(first):
            section = first
        scope = cell(sheet, r, 2)
        if not section or not scope:
            continue
        group = cell(sheet, r, 4)
        out.append({
            "Annex": annex,
            "Arrangement": arrangement,
            "Section": section,
            "Chapter": cell(sheet, r, 1),
            "Scope": scope,
            # H = "hassas" (sensitive), HO = non-sensitive; only EK-2 carries it, and the same
            # column in EK-4 holds working notes, so anything else is dropped rather than guessed.
            "ProductGroup": group if group in ("H", "HO") else "",
        })
        rows += 1
    return rows


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: parse-gsp-sectors.py <rejim-zip> <output-csv>")
    zip_path, out_path = sys.argv[1], sys.argv[2]

    out = []
    with zipfile.ZipFile(zip_path) as z:
        # Entry names in these zips are mangled (no UTF-8 flag, so CP437), but EK-N.xls is ASCII
        # and survives — which is exactly why the annex key is what everything here matches on.
        names = {n.rsplit("/", 1)[-1]: n for n in z.namelist()}
        for annex, arrangement in ANNEXES.items():
            if annex not in names:
                raise SystemExit(f"{annex} is not in {zip_path} — the archive layout has changed.")
            book = xlrd.open_workbook(file_contents=z.read(names[annex]))
            n = parse(book.sheet_by_index(0), annex, arrangement, out)
            print(f"  {annex} ({arrangement}): {n} rows")
            if n == 0:
                raise SystemExit(f"{annex} produced no rows — the layout has changed.")

    with io.open(out_path, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, ["Annex", "Arrangement", "Section", "Chapter", "Scope", "ProductGroup"])
        w.writeheader()
        w.writerows(out)

    sections = len({(r["Annex"], r["Section"]) for r in out})
    print(f"{out_path}: {len(out)} rows across {sections} annex/section pairs")


if __name__ == "__main__":
    main()
