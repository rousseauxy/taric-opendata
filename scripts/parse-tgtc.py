#!/usr/bin/env python3
"""
Parses the Turkish Customs Tariff (TGTC) chapter .xls files into a single tr-nomenclature.csv.

The Ministry of Trade (ggm.ticaret.gov.tr) publishes the annual "Istatistik Pozisyonlarina
Bolunmus Turk Gumruk Tarife Cetveli" as a zip of per-chapter old-format .xls files
("NN fasil YYYY.xls") under "<year> TGTC/<year> TGTC/". Each has 4 columns:
  POZISYON NO (GTIP code) | ESYANIN TANIMI (description) | OLCU BIRIMI (unit) | 474 VERGI HADDI (base duty)

Codes are dotted (22.01, 2201.10, 2201.10.11.00.00); descriptions span continuation rows
(empty code cell). Output columns: CnCode (digits only), DescriptionTR, Unit, BaseDutyRate,
IndentLevel. Requires xlrd (reads legacy .xls).

Usage: parse-tgtc.py <input-dir-with-xls> <output-csv>
"""
import csv
import glob
import os
import re
import sys

import xlrd

CODE_RE = re.compile(r"^\d{2}\.\d{2}$|^\d{4}(\.\d{2})+$")  # 22.01 / 2201.10 / 2201.10.11.00.00


def norm_duty(d):
    d = (d or "").strip()
    if not d:
        return ""
    try:
        f = float(d)
        return str(int(f)) if f == int(f) else str(f)
    except ValueError:
        return d


def parse_dir(in_dir):
    rows = []
    for fp in sorted(glob.glob(os.path.join(in_dir, "*.xls"))):
        try:
            sh = xlrd.open_workbook(fp).sheet_by_index(0)
        except Exception as ex:  # noqa: BLE001
            print(f"  skip {os.path.basename(fp)}: {ex}", file=sys.stderr)
            continue
        cur = None
        for r in range(sh.nrows):
            def cell(c):
                return str(sh.cell_value(r, c)).replace("\n", " ").strip() if c < sh.ncols else ""
            code_raw = cell(0).replace(" ", "")
            desc_raw = cell(1)
            unit, duty = cell(2), cell(3)
            if CODE_RE.match(code_raw):
                if cur:
                    rows.append(cur)
                indent = re.match(r"^[-\s]*", desc_raw).group(0).count("-")
                cur = {
                    "code": code_raw.replace(".", ""),
                    "desc": desc_raw.lstrip("- ").strip(),
                    "unit": unit,
                    "duty": duty,
                    "indent": indent,
                }
            elif cur and desc_raw and not code_raw:
                cur["desc"] = (cur["desc"] + " " + desc_raw.lstrip("- ").strip()).strip()
                if not cur["unit"] and unit:
                    cur["unit"] = unit
                if not cur["duty"] and duty:
                    cur["duty"] = duty
        if cur:
            rows.append(cur)
    return rows


def main():
    in_dir, out_csv = sys.argv[1], sys.argv[2]
    rows = parse_dir(in_dir)
    with open(out_csv, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["CnCode", "DescriptionTR", "Unit", "BaseDutyRate", "IndentLevel"])
        for x in rows:
            w.writerow([x["code"], x["desc"], x["unit"], norm_duty(x["duty"]), x["indent"]])
    print(f"parsed {len(rows)} nomenclature rows -> {out_csv}")


if __name__ == "__main__":
    main()
