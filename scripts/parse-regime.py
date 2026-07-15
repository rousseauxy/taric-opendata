#!/usr/bin/env python3
"""
Parses the Turkish Import Regime Decree annex lists (Karar 3350, "rejim YYYY.zip")
into tr-measures.csv: the applied customs duty per GTİP code and country group.

The zip ships one xlsx per list (I sayılı Liste, II Sayılı Liste (NN. Fasıllar),
III-VII). Each sheet repeats per-chapter blocks:

    GTİP | DİPNOT | GÜMRÜK VERGİSİ ORANI (%)          <- header row
         |        | AB, BK | GÜR | ... | DÜ           <- group-label row
    10121000000 |  | 0 | 0 | ... | 0                  <- data (leading zero lost!)

Output columns: Code (12-digit zero-padded), Group (column label, e.g. "DÜ"),
Rate (as published: number, "T1"/"T2" composition markers, "M" etc.), List.
Footnote markers in the DİPNOT column are ignored. Requires openpyxl.

Usage: parse-regime.py <rejim-zip> <output-csv>
"""
import csv
import io
import re
import sys
import zipfile

import openpyxl

LIST_RE = re.compile(r"^(I{1,3}|IV|V|VI|VII)\b", re.IGNORECASE)


def list_no(filename):
    m = LIST_RE.match(filename.strip())
    return m.group(1).upper() if m else None


def parse_sheet(ws, list_id, rows_out):
    groups = {}          # column index -> group label
    pending_header = False
    for row in ws.iter_rows(values_only=True):
        cells = list(row)
        first = str(cells[0]).strip() if cells and cells[0] is not None else ""

        if first.upper().startswith("GTİP") or first.upper().startswith("GTIP"):
            pending_header = True
            continue
        if pending_header:
            # group-label row: labels from col 2 onward (col 1 = DİPNOT). Country-group
            # labels always contain letters — numeric cells mean this sheet block has a
            # different layout (Liste IV/V annotations), which we skip.
            new_groups = {}
            for i, c in enumerate(cells[2:], start=2):
                label = str(c).strip() if c is not None else ""
                if label and re.search(r"[A-Za-zÇĞİÖŞÜçğıöşü]", label):
                    new_groups[i] = re.sub(r"\s+", " ", label)
            groups = new_groups          # empty -> block ignored until next header
            pending_header = False
            continue

        code_digits = re.sub(r"\D", "", first)
        if len(code_digits) < 10 or not groups:
            continue
        code = code_digits.zfill(12)

        for i, label in groups.items():
            if i >= len(cells) or cells[i] is None:
                continue
            rate = str(cells[i]).strip()
            if rate == "":
                continue
            rows_out.append({"Code": code, "Group": label, "Rate": rate, "List": list_id})


def main(zip_path, out_csv):
    z = zipfile.ZipFile(zip_path)
    rows = []
    for name in sorted(z.namelist()):
        base = name.rsplit("/", 1)[-1]
        if not base.lower().endswith(".xlsx"):
            continue
        lid = list_no(base)
        if lid is None:
            continue
        wb = openpyxl.load_workbook(io.BytesIO(z.read(name)), read_only=True, data_only=True)
        for ws in wb.worksheets:
            parse_sheet(ws, lid, rows)
        print(f"  {base}: cumulative {len(rows)} rows", file=sys.stderr)

    with open(out_csv, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["Code", "Group", "Rate", "List"])
        w.writeheader()
        w.writerows(rows)
    print(f"tr-measures.csv: {len(rows)} rows", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: parse-regime.py <rejim-zip> <output-csv>")
    main(sys.argv[1], sys.argv[2])
