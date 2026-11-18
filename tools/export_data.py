"""Export the Data Sheet (.xlsx) to data/<tab>.json for the game to load.

Usage (from the project root):
    python3 -I tools/export_data.py [path/to/Data Sheet.xlsx]

Without an argument it reads docs/Data Sheet.xlsx.
Each tab except "Read Me" becomes data/<tab_name>.json: an array of row objects
keyed by the header row. Empty cells are left out of the row object, so a missing
key means "not set" (for example a Parameter that a Request does not ask for).

Stdlib only: an .xlsx file is a zip archive of XML parts.
"""

from __future__ import annotations  # lets "str | None" hints work on Python 3.9 (macOS's python3)

import json
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SHEET = ROOT / "docs" / "Data Sheet.xlsx"
OUT_DIR = ROOT / "data"
SKIP_TABS = {"Read Me"}

# Request target columns (param_01_target …) must each hold a State or the word "any".
# "any" means the Request does not ask for that Parameter; it is left out of the JSON.
TARGET_SUFFIX = "_target"
ANY_STATE = "any"
VALID_STATES = (0, 1, 2)  # GDD 4.1: every Parameter has 3 States, counted from 0

NS_MAIN = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
NS_REL = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
NS_PKG_REL = "{http://schemas.openxmlformats.org/package/2006/relationships}"


class ExportError(Exception):
    pass


def read_shared_strings(archive: zipfile.ZipFile) -> list[str]:
    """Text cells are stored once in sharedStrings.xml and referenced by index."""
    if "xl/sharedStrings.xml" not in archive.namelist():
        return []
    root = ET.fromstring(archive.read("xl/sharedStrings.xml"))
    strings = []
    for item in root.findall(NS_MAIN + "si"):
        # A string is either one <t> or several rich-text runs <r><t>; skip phonetic hints <rPh>.
        phonetic = {t for rph in item.iter(NS_MAIN + "rPh") for t in rph.iter(NS_MAIN + "t")}
        parts = [t.text or "" for t in item.iter(NS_MAIN + "t") if t not in phonetic]
        strings.append("".join(parts))
    return strings


def list_tabs(archive: zipfile.ZipFile) -> list[tuple[str, str]]:
    """Return (tab name, worksheet XML path) in workbook order."""
    rels_root = ET.fromstring(archive.read("xl/_rels/workbook.xml.rels"))
    targets = {rel.get("Id"): rel.get("Target") for rel in rels_root.iter(NS_PKG_REL + "Relationship")}
    workbook = ET.fromstring(archive.read("xl/workbook.xml"))
    tabs = []
    for sheet in workbook.find(NS_MAIN + "sheets"):
        target = targets[sheet.get(NS_REL + "id")]
        # Targets are relative to xl/ ("worksheets/sheet1.xml") or absolute ("/xl/worksheets/sheet1.xml").
        path = target.lstrip("/") if target.startswith("/") else "xl/" + target
        tabs.append((sheet.get("name"), path))
    return tabs


def raw_cell(cell: ET.Element, shared: list[str]) -> tuple[str | None, str]:
    """Return (raw text, Excel cell type). Raw text is None for an empty cell."""
    cell_type = cell.get("t", "n")
    if cell_type == "inlineStr":
        node = cell.find(NS_MAIN + "is")
        text = "".join(t.text or "" for t in node.iter(NS_MAIN + "t")) if node is not None else None
        return text, "s"
    value = cell.find(NS_MAIN + "v")
    if value is None or value.text is None:
        return None, cell_type
    if cell_type == "s":
        return shared[int(value.text)], "s"
    return value.text, cell_type  # "n" number, "b" boolean, "str" formula text, "e" error


def convert_cell(raw: str, cell_type: str, where: str):
    """Turn one non-empty cell into the JSON value the game will read.

    raw        the cell text as stored: "1.0", "2", "Luk", "1" (for TRUE)
    cell_type  Excel's type code: "n" number, "s" string, "str" formula string, "b" boolean, "e" error
    where      a label like "Requests!D2", for error messages

    Return the value, or None to drop the cell. Raise ExportError to stop the export.
    """
    if cell_type == "e":
        raise ExportError(f"{where} shows the error {raw}. Fix that cell in the Data Sheet and export again.")

    if cell_type == "b":
        return raw == "1"

    if cell_type == "n":
        number = float(raw)
        if number.is_integer():
            return int(number)
        raise ExportError(f"{where} is {raw}, but every number in the Data Sheet must be a whole number.")

    text = raw.strip()
    return text or None


def column_letters(ref: str) -> str:
    """'AB12' -> 'AB'."""
    return ref.rstrip("0123456789")


def check_targets(tab: str, header: dict[str, str], record: dict, row_number: str) -> None:
    """Validate a row's *_target cells, and drop the ones marked "any".

    An empty target cell stops the export: it is impossible to tell "not requested"
    from "forgot to fill in", so the Data Sheet must say which one it means.
    """
    for col, name in header.items():
        if not name.endswith(TARGET_SUFFIX):
            continue
        where = f"{tab}!{col}{row_number}"
        if name not in record:
            raise ExportError(f"{where} is empty. Write a State (0, 1 or 2), or '{ANY_STATE}' if it is not requested.")
        value = record[name]
        if isinstance(value, str) and value.lower() == ANY_STATE:
            del record[name]
        elif type(value) is not int or value not in VALID_STATES:
            raise ExportError(f"{where} is {value!r}. A target must be a State (0, 1 or 2) or '{ANY_STATE}'.")


def read_tab(archive: zipfile.ZipFile, tab: str, path: str, shared: list[str]) -> list[dict]:
    root = ET.fromstring(archive.read(path))
    header: dict[str, str] = {}
    rows: list[dict] = []
    for row in root.iter(NS_MAIN + "row"):
        cells = {}
        for cell in row.findall(NS_MAIN + "c"):
            raw, cell_type = raw_cell(cell, shared)
            if raw is None or (cell_type == "s" and raw.strip() == ""):
                continue
            cells[column_letters(cell.get("r"))] = (raw, cell_type, f"{tab}!{cell.get('r')}")
        if not cells:
            continue  # blank row (Excel tables often keep formatted empty rows)
        if not header:
            header = {col: raw.strip() for col, (raw, _, _) in cells.items()}
            continue
        record = {}
        for col, (raw, cell_type, where) in cells.items():
            if col not in header:
                raise ExportError(f"{where} has a value but its column has no header.")
            value = convert_cell(raw, cell_type, where)
            if value is not None:
                record[header[col]] = value
        if record:
            check_targets(tab, header, record, row.get("r"))
            rows.append(record)
    return rows


def tab_file_name(tab: str) -> str:
    """'Ingredients' -> 'ingredients.json', 'Day Consequences' -> 'day_consequences.json'."""
    return re.sub(r"[^a-z0-9]+", "_", tab.lower()).strip("_") + ".json"


def main(argv: list[str]) -> int:
    try:
        source = Path(argv[1]) if len(argv) > 1 else DEFAULT_SHEET
        with zipfile.ZipFile(source) as archive:
            shared = read_shared_strings(archive)
            exported = {}
            for tab, path in list_tabs(archive):
                if tab in SKIP_TABS:
                    continue
                exported[tab_file_name(tab)] = read_tab(archive, tab, path, shared)
    except (ExportError, OSError, zipfile.BadZipFile, KeyError) as error:
        print(f"export_data: {error}", file=sys.stderr)
        return 1

    OUT_DIR.mkdir(exist_ok=True)
    for file_name, rows in exported.items():
        text = json.dumps(rows, indent=2, ensure_ascii=False) + "\n"
        (OUT_DIR / file_name).write_text(text, encoding="utf-8")
        print(f"data/{file_name}: {len(rows)} rows")
    print(f"Exported from {source.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
