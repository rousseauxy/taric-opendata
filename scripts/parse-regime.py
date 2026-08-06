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

# Annex files this parser recognises as a list but cannot yet read, with why. They are known
# gaps, not surprises, so they must not fail the sync — but anything NOT on this list producing
# zero rows is a layout change and does fail, which is the guard that was missing.
#
# Every one of these needs a decision in TaricHive's TrImporter before it can be emitted,
# because the CSV's Group column becomes a synthetic GeographicalArea and MeasureTypeCode is
# derived from it (DÜ -> 103 third-country, anything else -> 142 preference). None of the three
# fits that shape:
#
#   V   (2,106 codes) duty suspensions. Code column is headed "GTP", not "GTİP", and the layout
#       is a single GV(%) column rather than a country-group matrix — a suspension applies
#       regardless of origin, so it is neither 103 nor 142.
#   VI  (39 codes) end-use relief. Code sits in column 3 and the layout is again single-rate.
#   II 86-89 (483 codes: vehicles, aircraft, ships) the group labels are the numbers 1-5 on the
#       row ABOVE the GTİP header, referencing a legend, so they are neither on the row this
#       parser reads nor usable as area names.
# Keyed on the annex identity, not the filename. Python's zipfile decodes non-UTF-8 entry names
# as CP437 exactly as .NET's ZipArchive does, and these zips do not set the UTF-8 flag — so the
# Turkish characters cannot be relied on. The leading roman numeral and the chapter range are
# ASCII and survive. Keep this in step with TrRegimeParser.KnownUnreadable in TaricHive while
# both implementations exist.
KNOWN_UNREADABLE = {"V", "VI", "II:86-89"}

RANGE_RE = re.compile(r"(\d{2})\s*-\s*(\d{2})")


def annex_key(filename):
    """'II Sayılı Liste 86-89. Fasıllar.xlsx' -> 'II:86-89'; 'V Sayìlì Liste.xlsx' -> 'V'."""
    lid = list_no(filename)
    if lid is None:
        return ""
    m = RANGE_RE.search(filename)
    return f"{lid}:{m.group(1)}-{m.group(2)}" if m else lid


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
    unmatched = []      # in the zip, never looked at
    empty = []          # matched a list, produced nothing

    for name in sorted(z.namelist()):
        base = name.rsplit("/", 1)[-1]
        if base.startswith("__") or base.endswith("/"):
            continue

        lid = list_no(base) if base.lower().endswith(".xlsx") else None
        if lid is None:
            unmatched.append(base)
            continue

        before = len(rows)
        wb = openpyxl.load_workbook(io.BytesIO(z.read(name)), read_only=True, data_only=True)
        for ws in wb.worksheets:
            parse_sheet(ws, lid, rows)
        gained = len(rows) - before
        if gained == 0 and annex_key(base) not in KNOWN_UNREADABLE:
            empty.append(base)
        note = "  [known gap]" if annex_key(base) in KNOWN_UNREADABLE else ""
        print(f"  {base}: +{gained} rows (cumulative {len(rows)}){note}", file=sys.stderr)

    # Both of these used to be silent, and both were hiding real data. "V Sayılı Liste.xlsx"
    # matched its list and contributed nothing for as long as this parser has existed, because
    # its code column is headed GTP rather than GTİP; "EK-1.xlsx" was never opened at all. A
    # count of rows written cannot distinguish "the annex is empty" from "the layout moved",
    # so say which files fell out and treat a matched-but-empty list as a failure.
    if unmatched:
        print(f"WARNING: {len(unmatched)} file(s) in the zip were not parsed: "
              + ", ".join(sorted(unmatched)), file=sys.stderr)
    known = sorted({annex_key(n.rsplit('/', 1)[-1]) for n in z.namelist()}
                   & KNOWN_UNREADABLE)
    if known:
        print(f"WARNING: {len(known)} known-unreadable annex(es) skipped "
              f"(~2,628 codes; see KNOWN_UNREADABLE): " + ", ".join(known), file=sys.stderr)
    if empty:
        raise SystemExit(
            f"ERROR: {len(empty)} list file(s) matched but yielded no rows: "
            + ", ".join(sorted(empty))
            + " — the sheet layout has changed (check the code-column header and its position). "
              "If this is a permanent new shape, add it to KNOWN_UNREADABLE with the reason."
        )

    with open(out_csv, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=["Code", "Group", "Rate", "List"])
        w.writeheader()
        w.writerows(rows)

    by_list = {}
    for r in rows:
        by_list[r["List"]] = by_list.get(r["List"], 0) + 1
    print(f"tr-measures.csv: {len(rows)} rows  "
          + " ".join(f"{k}={v}" for k, v in sorted(by_list.items())), file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: parse-regime.py <rejim-zip> <output-csv>")
    main(sys.argv[1], sys.argv[2])
