#!/usr/bin/env python3
"""
Parse the Turkish Customs Tariff (TGTC) Section/Chapter legal notes.

Input : a directory of per-chapter legacy .xls files named "Fasıl <n>.xls"
        (the "FASIL NOTLARI" folder inside the annual TGTC zip). Each file holds,
        in reading order:
          BÖLÜM <roman>            (only in the first chapter file of a section)
          <section title>
          Not / Notlar
          <section notes…>
          FASIL <n>
          <chapter title, may wrap over lines>
          Not / Notlar             (+ optional "Ek Notlar")
          <chapter notes…>

Output: a CSV with columns  Kind,Code,SectionRoman,Title,NoteText
          Kind          = "section" | "chapter"
          Code          = section roman (e.g. "I") or 2-digit chapter (e.g. "01")
          SectionRoman  = the section a chapter belongs to (HS standard mapping)
          Title         = section/chapter heading
          NoteText      = notes, wrapped lines re-joined, paragraphs split by "\n"

Usage: parse-tgtc-notes.py <input-dir> <output-csv>
"""
import csv
import os
import re
import sys

import xlrd

# HS section → chapter ranges are fixed worldwide; use them to attach each chapter
# note to its section (section headers only appear in the first file of each section).
_SECTION_RANGES = [
    ("I", 1, 5), ("II", 6, 14), ("III", 15, 15), ("IV", 16, 24), ("V", 25, 27),
    ("VI", 28, 38), ("VII", 39, 40), ("VIII", 41, 43), ("IX", 44, 46), ("X", 47, 49),
    ("XI", 50, 63), ("XII", 64, 67), ("XIII", 68, 70), ("XIV", 71, 71), ("XV", 72, 83),
    ("XVI", 84, 85), ("XVII", 86, 89), ("XVIII", 90, 92), ("XIX", 93, 93),
    ("XX", 94, 96), ("XXI", 97, 97),
]
SECTION_OF_CHAPTER = {ch: rom for rom, a, b in _SECTION_RANGES for ch in range(a, b + 1)}

BOLUM_RE = re.compile(r"^\s*B[ÖO]L[ÜU]M\s+([IVXLCDM]+)\s*$", re.IGNORECASE)
FASIL_RE = re.compile(r"^\s*FASIL\s+(\d+)\s*$", re.IGNORECASE)
# The header that separates a title from the note body ("Not", "Notlar").
NOTE_HDR_RE = re.compile(r"^\s*(Notlar|Not)\s*$", re.IGNORECASE)
# Sub-headers that live *inside* the note body and begin a fresh paragraph.
SUBHDR_RE = re.compile(r"^\s*(Ek\s*Notlar|Altpozisyon\s*Not[ıiu]?\w*)\s*$", re.IGNORECASE)
# A line that begins a new enumerated note item → new paragraph.
ENUM_RE = re.compile(r"^\s*(\(?\d{1,3}[.)]|\([a-zçğıöşü]\)|[A-ZÇĞİÖŞÜ]\.\s|[-•]\s)")


def read_lines(path):
    """Non-empty logical lines of the sheet (all columns joined per row)."""
    wb = xlrd.open_workbook(path)
    sh = wb.sheet_by_index(0)
    out = []
    for r in range(sh.nrows):
        cells = [str(sh.cell_value(r, c)).strip() for c in range(sh.ncols)]
        text = " ".join(x for x in cells if x).strip()
        text = re.sub(r"\s{2,}", " ", text)
        if text:
            out.append(text)
    return out


def split_title_notes(lines):
    """Given the lines of one block, split into (title, note_text)."""
    hdr = next((i for i, ln in enumerate(lines) if NOTE_HDR_RE.match(ln)), None)
    if hdr is None:
        return " ".join(lines).strip(), ""
    title = " ".join(lines[:hdr]).strip()
    return title, build_paragraphs(lines[hdr + 1:])


def build_paragraphs(lines):
    """Re-join wrapped lines into paragraphs; enumerators / sub-headers start new ones."""
    paras, cur = [], ""
    for ln in lines:
        starts_new = bool(ENUM_RE.match(ln) or SUBHDR_RE.match(ln))
        if starts_new and cur:
            paras.append(cur.strip())
            cur = ln
        elif starts_new:
            cur = ln
        else:
            cur = f"{cur} {ln}".strip()
    if cur.strip():
        paras.append(cur.strip())
    return "\n".join(paras)


def parse_file(path, rows):
    lines = read_lines(path)
    # Segment the file into (marker, roman/chapter, block-lines) chunks.
    markers = []  # (idx, kind, value)
    for i, ln in enumerate(lines):
        if (m := BOLUM_RE.match(ln)):
            markers.append((i, "section", m.group(1).upper()))
        elif (m := FASIL_RE.match(ln)):
            markers.append((i, "chapter", int(m.group(1))))
    for k, (idx, kind, value) in enumerate(markers):
        end = markers[k + 1][0] if k + 1 < len(markers) else len(lines)
        block = lines[idx + 1:end]
        title, note = split_title_notes(block)
        if kind == "section":
            rows.append({"Kind": "section", "Code": value, "SectionRoman": value,
                         "Title": title, "NoteText": note})
        else:
            rows.append({"Kind": "chapter", "Code": f"{value:02d}",
                         "SectionRoman": SECTION_OF_CHAPTER.get(value, ""),
                         "Title": title, "NoteText": note})


def main():
    if len(sys.argv) != 3:
        print("Usage: parse-tgtc-notes.py <input-dir> <output-csv>", file=sys.stderr)
        return 2
    in_dir, out_csv = sys.argv[1], sys.argv[2]
    files = [os.path.join(in_dir, f) for f in os.listdir(in_dir)
             if re.match(r"^Fas.+\s+\d+\.xls$", f, re.IGNORECASE)]
    files.sort()

    rows = []
    for f in files:
        try:
            parse_file(f, rows)
        except Exception as e:  # noqa: BLE001 — keep going, report per-file
            print(f"WARN {os.path.basename(f)}: {e}", file=sys.stderr)

    # De-duplicate: keep the first row per (Kind, Code) that carries note text.
    seen = {}
    for row in rows:
        key = (row["Kind"], row["Code"])
        if key not in seen or (not seen[key]["NoteText"] and row["NoteText"]):
            seen[key] = row
    final = list(seen.values())

    with open(out_csv, "w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["Kind", "Code", "SectionRoman", "Title", "NoteText"])
        w.writeheader()
        w.writerows(final)

    n_sec = sum(1 for r in final if r["Kind"] == "section")
    n_ch = sum(1 for r in final if r["Kind"] == "chapter")
    print(f"Parsed {len(files)} files -> {len(final)} notes ({n_sec} section, {n_ch} chapter).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
