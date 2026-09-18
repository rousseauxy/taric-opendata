"""Turns the Belgian IDMS workbooks into JSON a program can read without Excel.

Two sources, both from the minfin IDMS technical-documentation page (see sync-be-idms.ps1):

  IDMS_VRE.xlsx       the validation rules IDMS applies to an import declaration -- the LIVE
                      rule set. The "Business rules" PDF on the same page stopped being updated in
                      May 2024; this workbook is where rules are added, changed and switched off.
  IDMS_codelist.xlsx  IDMS's own filtered copy of the code lists, one sheet per list.

WHY THE RULE STATUS MATTERS MORE THAN THE RULE TEXT: a rule on the "RulesInactive" sheet is not
enforced. BE0211 (a previous document on every goods item) and BE0212 (previous procedure 71
requires NMRN) both read as hard requirements in the 2024 PDF, and both are inactive in the
2026-09-08 workbook. A consumer that loads the rules without their sheet cannot tell the two apart,
so every rule here carries a "status".

Usage: python parse-be-idms.py <folder>   (reads the two .xlsx, writes the two .json beside them)
"""

import json
import sys
from pathlib import Path

import openpyxl


def cell(v):
    """A cell as text, or None. Codes arrive as numbers where Excel guessed (CL093's 22, 43…)."""
    if v is None:
        return None
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    s = str(v).strip()
    return s or None


def rows(ws):
    return [[cell(c) for c in r] for r in ws.iter_rows(values_only=True)]


# ─── Rules ────────────────────────────────────────────────────────────────────

# The active sheet has a header row; RulesInactive does not, and repeats the same column order.
# Keyed by the header text so a reordered sheet fails loudly below rather than shifting fields.
RULE_FIELDS = {
    "ID": "id",
    "R/C Code": "code",
    "Precondition": "precondition",
    "Functional Description": "functionalDescription",
    "Technical Description": "technicalDescription",
    "Error code": "errorCode",
    "Error reason": "errorReason",
    "Error FR": "errorFr",
    "Error NL": "errorNl",
    "Error DE": "errorDe",
    "Error EN": "errorEn",
}

SHEET_STATUS = {
    "Feuil1": "active",
    "RulesInactive": "inactive",
    "TemporaryBlockingRules": "temporary-blocking",
}


def parse_rules(path):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)
    active = rows(wb["Feuil1"])
    header = active[0]
    missing = [h for h in ("ID", "R/C Code", "Technical Description") if h not in header]
    if missing:
        raise SystemExit(f"VRE active sheet lost its header columns {missing}: got {header}")

    columns = [(i, RULE_FIELDS.get(h) or h) for i, h in enumerate(header) if h]

    rules = []
    for sheet, status in SHEET_STATUS.items():
        if sheet not in wb.sheetnames:
            raise SystemExit(f"VRE has no '{sheet}' sheet: {wb.sheetnames}")
        body = rows(wb[sheet])
        if body and body[0][:2] == header[:2]:
            body = body[1:]
        for r in body:
            if not any(r) or len(r) < 2 or not r[1]:
                continue
            rule = {"status": status}
            for i, name in columns:
                rule[name] = r[i] if i < len(r) else None
            rules.append(rule)

    changes = []
    if "Changes" in wb.sheetnames:
        for r in rows(wb["Changes"])[1:]:
            if r and r[0]:
                changes.append({"code": r[0], "change": r[1] if len(r) > 1 else None})

    counts = {s: sum(1 for r in rules if r["status"] == s) for s in SHEET_STATUS.values()}
    if counts["active"] < 100:
        raise SystemExit(f"VRE yielded only {counts['active']} active rules -- not the workbook we expect")
    return {"counts": counts, "changes": changes, "rules": rules}


# ─── Code lists ───────────────────────────────────────────────────────────────

DESCRIPTION_LANG = {"Description EN": "en", "Description FR": "fr", "Description NL": "nl",
                    "DescriptionNL": "nl", "Description DE": "de", "Description": "en"}


def parse_codelists(path):
    wb = openpyxl.load_workbook(path, read_only=True, data_only=True)

    # The index sheet: which lists IDMS uses, and whether national values extend them.
    index = {}
    for r in rows(wb["Code list"])[1:]:
        if r and r[0]:
            index[r[0].strip()] = {
                "name": r[1] if len(r) > 1 else None,
                "cciFilter": r[2] if len(r) > 2 else None,
                "nationalValue": r[3] if len(r) > 3 else None,
            }

    lists = {}
    for ws in wb.worksheets:
        if ws.title == "Code list":
            continue
        body = rows(ws)
        code = (body[0][0] if body and body[0] else ws.title).strip()

        # Above the header: the list code, "Home", and the data elements it serves, possibly over
        # several rows. The header is the first row that names a "Value" column.
        head_at = next((i for i, r in enumerate(body) if "Value" in r), None)
        if head_at is None:
            continue
        data_elements = [c for r in body[:head_at] for c in r[1:]
                         if c and c != "Home" and c[:1].isdigit()]
        header = body[head_at]
        value_col = header.index("Value")

        entries, section = [], None
        for r in body[head_at + 1:]:
            filled = [c for c in r if c]
            if not filled:
                continue
            value = r[value_col] if value_col < len(r) else None
            if not value:
                # A one-cell row between entries is a heading ("Codes union", "national codes").
                if len(filled) == 1:
                    section = filled[0]
                continue
            entry = {"value": value}
            for i, h in enumerate(header):
                if not h or i == value_col or i >= len(r) or r[i] is None:
                    continue
                lang = DESCRIPTION_LANG.get(h)
                if lang:
                    entry.setdefault("descriptions", {})[lang] = r[i]
                elif h == "Name":
                    continue            # the list's own name, repeated on every row
                elif h == "CCI filter":
                    entry["cciFilter"] = r[i]
                elif h.startswith("Appendice") or h.startswith("Appendix"):
                    entry["appendix"] = r[i]
                else:
                    entry[h] = r[i]
            if section:
                entry["section"] = section
            entries.append(entry)

        lists[code] = {**index.get(code, {}), "dataElements": data_elements, "entries": entries}

    if len(lists) < 20:
        raise SystemExit(f"Code list workbook yielded only {len(lists)} lists -- not the workbook we expect")
    return {"lists": lists}


def main():
    folder = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    rules = parse_rules(folder / "IDMS_VRE.xlsx")
    lists = parse_codelists(folder / "IDMS_codelist.xlsx")

    (folder / "idms-rules.json").write_text(json.dumps(rules, ensure_ascii=False, indent=1), encoding="utf-8")
    (folder / "idms-codelists.json").write_text(json.dumps(lists, ensure_ascii=False, indent=1), encoding="utf-8")

    c = rules["counts"]
    print(f"Rules: {c['active']} active, {c['inactive']} inactive, {c['temporary-blocking']} temporarily blocking; "
          f"{len(rules['changes'])} change note(s)")
    print(f"Code lists: {len(lists['lists'])}, {sum(len(v['entries']) for v in lists['lists'].values())} entries")


if __name__ == "__main__":
    main()
