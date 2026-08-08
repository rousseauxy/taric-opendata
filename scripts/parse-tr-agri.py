#!/usr/bin/env python3
"""
Transcribes the Turkish Import Regime Decree's agricultural-component tables — "Tablo I Bileşim
Tablosu.xls" and "Tablo 2.doc" inside "rejim YYYY.zip" — into tr-agri-components.csv.

These are what the T1/T2 markers in List III point at. 607 Turkish measures of type TPY (tarım
payı, the agricultural component) currently carry no duty component at all: the rate cell says
"T1" or "T2" and nothing said what either meant, so the page rendered the commodity, the country
group, and a blank.

  Tablo I   a four-axis composition grid — süt yağı (milk fat) x süt proteini (milk protein) x
            nişasta/glikoz (starch/glucose) x sakkaroz/invert şeker/izoglikoz (sucrose) — whose
            cells are code numbers 7000-7899. This is the Meursing table, in the same numbering
            Belgium publishes as additional-code type 7.
  Tablo 2   "Tablo 2- III Sayılı Listeye Ait Tarım Payı Tablosu": per code, two rates in
            EURO/100 KG/NET, headed "Tarım Payı (T 1)" and "Tarım Payı (T 2)" — which is exactly
            the T1/T2 the rate cells carry.

This script does NOT interpret either. It transcribes, for the same reason parse-gsp-sectors.py
does: the files are formats TaricHive's importer cannot open — Tablo I is legacy BIFF and Tablo 2
is an OLE Word 97 document — while it reads the rest of the same archive directly. Deriving here
would put the semantics a layer above where the rest of TR's live, which is the arrangement that
hid TR's losses for as long as it did.

Two shapes worth knowing before touching this:

  * The starch/glucose heading is CENTRED over its group of columns rather than repeated on each,
    so it cannot be carried forward. The group boundaries are recovered from the sucrose axis
    instead: a new starch band begins wherever the sucrose lower bound resets to ">=0". That is
    read off the sheet rather than hard-coded, so an added band does not silently merge into its
    neighbour.
  * Tablo 2's body text is CP1254 while its headings are UTF-16. A single-encoding scan finds the
    title and none of the numbers, which is why this file was written off as unreadable.

Cells reading "XXX" are compositions that cannot occur and are skipped, not emitted as codes.

Requires xlrd (legacy .xls). Usage: parse-tr-agri.py <rejim-zip> <output-csv>
"""
import csv
import re
import sys
import zipfile

import xlrd

COMPOSITION_ENTRY = "Tablo I Bileşim Tablosu.xls"
RATE_ENTRY = "Tablo 2.doc"

# The grid's own marker for "this combination cannot occur".
IMPOSSIBLE = "XXX"


def _norm(s):
    """Collapse the sheet's irregular inner spacing so bands compare and read cleanly."""
    return re.sub(r"\s+", " ", str(s or "").strip())


def _entry(zf, wanted):
    """
    Locate an entry by name. These zips do not set the UTF-8 name flag, so both ZipArchive and
    zipfile decode the Turkish characters as CP437; matching on the decoded form is what makes
    the lookup survive that.
    """
    for name in zf.namelist():
        try:
            decoded = name.encode("cp437").decode("utf-8")
        except (UnicodeEncodeError, UnicodeDecodeError):
            decoded = name
        if decoded == wanted or name == wanted:
            return name
    raise SystemExit(f"{wanted} is not in the archive — the decree's layout changed.")


def read_composition(zf):
    """Tablo I → {code: (milk fat, milk protein, starch/glucose, sucrose)}."""
    book = xlrd.open_workbook(file_contents=zf.read(_entry(zf, COMPOSITION_ENTRY)))
    sheet = book.sheet_by_index(0)

    # The header block is the rows above the first one whose second column holds a band. Located
    # rather than assumed: the sucrose lower bounds are the only row with a value in every code
    # column, which is what makes it findable without counting rows.
    lower_row = next(
        r for r in range(sheet.nrows)
        if sum(1 for c in range(2, sheet.ncols) if _norm(sheet.cell_value(r, c)).startswith(">"))
        >= sheet.ncols - 4
    )
    upper_row = lower_row + 1
    first_data = upper_row + 1

    # Starch groups: a new one starts wherever the sucrose lower bound returns to its first value.
    lowers = [_norm(sheet.cell_value(lower_row, c)) for c in range(sheet.ncols)]
    uppers = [_norm(sheet.cell_value(upper_row, c)) for c in range(sheet.ncols)]
    first_lower = lowers[2]

    starts = [c for c in range(2, sheet.ncols) if lowers[c] == first_lower]
    groups = []
    for i, start in enumerate(starts):
        end = starts[i + 1] - 1 if i + 1 < len(starts) else sheet.ncols - 1
        # The band's text is centred somewhere inside the span and may be split across two cells
        # (">= 25" and "<50" land in adjacent columns). Axis TITLES sit in the same rows and must
        # not be swept up with it — they are the cells carrying a "%", as in
        # "Sakkaroz/invert şeker/izoglikoz (% Ağırlık olarak)".
        label = " ".join(
            _norm(sheet.cell_value(r, c))
            for r in range(0, lower_row)
            for c in range(start, end + 1)
            if re.search(r"[<>]", str(sheet.cell_value(r, c)))
            and "%" not in str(sheet.cell_value(r, c))
        )
        groups.append((start, end, _norm(label)))

    if not groups:
        raise SystemExit("Tablo I: no starch/glucose groups found — the layout changed.")

    starch_of = {}
    for start, end, label in groups:
        for c in range(start, end + 1):
            starch_of[c] = label

    out = {}
    milk_fat = ""
    for r in range(first_data, sheet.nrows):
        if _norm(sheet.cell_value(r, 0)):
            milk_fat = _norm(sheet.cell_value(r, 0))
        # Protein is stated per row and is legitimately empty on the high milk-fat bands, where
        # the axis is not subdivided — so it must NOT be carried down from the row above.
        milk_protein = _norm(sheet.cell_value(r, 1))
        if not milk_fat:
            continue

        for c in range(2, sheet.ncols):
            cell = _norm(sheet.cell_value(r, c))
            if not cell or cell.upper() == IMPOSSIBLE:
                continue
            # xlrd hands back floats for the numeric cells: 7000.0 → "7000".
            try:
                code = str(int(float(cell)))
            except ValueError:
                continue
            sucrose = " ".join(p for p in (lowers[c], uppers[c]) if p)
            out[code] = (milk_fat, milk_protein, starch_of.get(c, ""), _norm(sucrose))
    return out


def read_rates(zf):
    """Tablo 2 → {code: (T1, T2)}, both EUR/100 kg net."""
    raw = zf.read(_entry(zf, RATE_ENTRY))
    if raw[:8] != b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1":
        raise SystemExit("Tablo 2 is no longer an OLE document — re-check how it is published.")

    # Word 97 "fast save" leaves the document text in pieces of MIXED encoding, and this file is
    # split straight down the middle of the table: the first eight rows are UTF-16 and the rest
    # CP1254. Measured on the live archive the two decodes yield 8 and 425 codes, overlap on none
    # and disagree on none — so both are read and unioned. Reading either alone silently loses the
    # other's rows, which is how "7000 0 0" sits in plain sight in the heading dump while the
    # parser reports it missing.
    out = {}
    for encoding in ("utf-16-le", "cp1254"):
        for code, pair in _walk_rate_tokens(raw.decode(encoding, "ignore")).items():
            out.setdefault(code, pair)
    return out


def _walk_rate_tokens(text):
    """Pull (code, T1, T2) triples out of one decoding of the document stream."""
    tokens = re.findall(r"\b\d{4}\b|\b\d{1,3},\d{2}\b|(?<![\d,])0(?![\d,])", text)
    is_code = lambda t: bool(re.fullmatch(r"7\d{3}", t))

    out = {}
    i = 0
    while i < len(tokens):
        if is_code(tokens[i]) and i + 2 < len(tokens):
            t1, t2 = tokens[i + 1], tokens[i + 2]
            if not is_code(t1) and not is_code(t2):
                out[tokens[i]] = (t1.replace(",", "."), t2.replace(",", "."))
                i += 3
                continue
        i += 1
    return out


def main(zip_path, out_path):
    with zipfile.ZipFile(zip_path) as zf:
        composition = read_composition(zf)
        rates = read_rates(zf)

    # The grid is the authority on which codes exist; a rate for a code the grid does not define
    # is a signal, not a row to emit silently.
    orphan_rates = sorted(set(rates) - set(composition))
    missing_rates = sorted(set(composition) - set(rates))

    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["CODE", "MILKFAT", "MILKPROTEIN", "STARCHGLUCOSE", "SUCROSE",
                    "TARIMPAYIT1", "TARIMPAYIT2"])
        for code in sorted(composition):
            fat, protein, starch, sucrose = composition[code]
            t1, t2 = rates.get(code, ("", ""))
            w.writerow([code, fat, protein, starch, sucrose, t1, t2])

    print(f"{out_path}: {len(composition)} composition cells, {len(rates)} priced")
    if missing_rates:
        print(f"  {len(missing_rates)} cells with no rate in Tablo 2: {missing_rates[:10]}")
    if orphan_rates:
        print(f"  {len(orphan_rates)} rates for cells not in Tablo I: {orphan_rates[:10]}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(__doc__.strip().splitlines()[-1])
    main(sys.argv[1], sys.argv[2])
