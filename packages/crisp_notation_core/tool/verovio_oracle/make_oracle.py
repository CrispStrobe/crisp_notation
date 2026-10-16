#!/usr/bin/env python3
"""
Verovio onset oracle for crisp_notation.

For each MusicXML file under the corpus, uses Verovio (6.3) to render
a timemap with repeats NOT expanded and extracts note onsets in quarter
notes for the first part's first staff (staff n=1). Reports all parts
with staff numbers so the Dart harness can filter to staff 1.

Input:
  every *.mxl under raw/Lieder and openewld
  and every *.xml / *.musicxml under musicxml-testsuite/lilypond and .../w3c
  Skip files under any ly-src directory. Skip raw/StringQuartets entirely.

Output:
  $CRISP_NOTATION_CORPUS/verovio-oracle/oracle.json
  {relative_path: [[qstamp, pitch, staff], ...]} sorted by qstamp.

Robust: each file wrapped in try/except, logs failures, never crashes.
"""

import json
import os
import re
import sys
import traceback
import xml.etree.ElementTree as ET
from pathlib import Path

CORPUS_ROOT = Path(os.environ.get("CRISP_NOTATION_CORPUS",
                                  "/mnt/volume1/notation-corpus"))
OUTPUT_PATH = CORPUS_ROOT / "verovio-oracle" / "oracle.json"

# pip install verovio (built against 6.3).
try:
    import verovio
except ImportError as e:
    print(f"Failed to import verovio: {e}", file=sys.stderr)
    sys.exit(1)


def find_files():
    """Collect input files per spec."""
    bases = [
        (CORPUS_ROOT / "raw" / "Lieder", [".mxl"]),
        (CORPUS_ROOT / "openewld", [".mxl"]),
        (CORPUS_ROOT / "musicxml-testsuite" / "lilypond", [".xml", ".musicxml"]),
        (CORPUS_ROOT / "musicxml-testsuite" / "w3c", [".xml", ".musicxml"]),
    ]
    files = []
    for base, exts in bases:
        if not base.exists():
            print(f"Base missing: {base}", file=sys.stderr)
            continue
        for root, dirs, fnames in os.walk(base):
            # Skip ly-src anywhere in path
            parts = Path(root).parts
            if "ly-src" in parts:
                continue
            if "StringQuartets" in parts:
                continue
            # Also skip hidden .git dirs to save time
            # Filter dirs in-place to avoid walking into them
            dirs[:] = [d for d in dirs if d not in (".git",)]
            # Double check root string for ly-src and StringQuartets
            if "/ly-src/" in root:
                continue
            if "StringQuartets" in root:
                continue
            for fname in fnames:
                lower = fname.lower()
                if not any(lower.endswith(ext) for ext in exts):
                    continue
                full = os.path.join(root, fname)
                if "/ly-src/" in full:
                    continue
                if "StringQuartets" in full:
                    continue
                files.append(Path(full))
    # Sort for determinism
    files.sort(key=lambda p: str(p))
    return files


def staff_map_from_mei(mei_str):
    """Map Verovio MEI note xml:id -> staff n (int).

    Walks MEI <staff> elements and collects descendant <note> ids.
    Returns dict id -> staff number. On failure returns empty.
    """
    try:
        root = ET.fromstring(mei_str)
    except Exception:
        return {}
    ns = {"mei": "http://www.music-encoding.org/ns/mei"}
    # MEI uses default namespace http://www.music-encoding.org/ns/mei
    # ElementTree requires namespace handling.
    try:
        staffs = root.findall(".//mei:staff", ns)
    except Exception:
        return {}
    id_to_staff = {}
    for staff in staffs:
        n_str = staff.attrib.get("n")
        if n_str is None:
            continue
        try:
            n = int(n_str)
        except ValueError:
            continue
        # Find all note elements under this staff
        try:
            notes = staff.findall(".//mei:note", ns)
        except Exception:
            continue
        for note in notes:
            nid = note.attrib.get("{http://www.w3.org/XML/1998/namespace}id")
            if nid:
                id_to_staff[nid] = n
    return id_to_staff


def process_file(path: Path):
    """Process one MusicXML file via Verovio.

    Returns list of [qstamp, pitch, staff] or raises.
    """
    tk = verovio.toolkit()
    # Ensure repeats are NOT expanded. Input is MusicXML.
    tk.setOptions({"inputFrom": "musicxml", "expandNever": True})
    # loadFile handles both .xml and .mxl (zip)
    ok = tk.loadFile(str(path))
    if not ok:
        log = tk.getLog()
        raise RuntimeError(f"loadFile failed: {log[:500]}")
    # Render timemap: returns list (in 6.3) or JSON string in older.
    tm_raw = tk.renderToTimemap()
    if isinstance(tm_raw, str):
        import json as js
        timemap = js.loads(tm_raw)
    else:
        timemap = tm_raw

    if not isinstance(timemap, list):
        raise RuntimeError(f"unexpected timemap type {type(timemap)}")

    # Build staff map from MEI
    mei = tk.getMEI()
    id_to_staff = staff_map_from_mei(mei)

    events = []
    for entry in timemap:
        if not isinstance(entry, dict):
            continue
        if "on" not in entry:
            continue
        qstamp = entry.get("qstamp")
        if qstamp is None:
            continue
        # Ensure numeric
        try:
            q = float(qstamp)
        except Exception:
            continue
        on_ids = entry["on"]
        if not isinstance(on_ids, list):
            continue
        for nid in on_ids:
            # Filter grace notes: Verovio marks them with dur.ppq 0 and grace attr
            try:
                attr = tk.getElementAttr(nid)
            except Exception:
                attr = None
            if attr is None:
                continue
            # Grace notes have 'grace' key
            if "grace" in attr:
                continue
            # Also check dur attribute: grace often has dur but dur.ppq 0; we already filtered via grace key
            try:
                midi = tk.getMIDIValuesForElement(nid)
            except Exception:
                continue
            if not midi or "pitch" not in midi:
                continue
            pitch = midi["pitch"]
            # Ensure pitch is int
            try:
                pitch_int = int(pitch)
            except Exception:
                continue
            staff = id_to_staff.get(nid)
            if staff is None:
                # Unmapped notes are left out rather than guessed.
                continue
            events.append([q, pitch_int, staff])

    # Sort by qstamp, then pitch, then staff for determinism
    events.sort(key=lambda x: (x[0], x[1], x[2]))
    return events


def main():
    files = find_files()
    print(f"Discovered {len(files)} input files")
    for f in files:
        print(f"  {f.relative_to(CORPUS_ROOT)}")

    oracle = {}
    failures = []
    success = 0

    for idx, path in enumerate(files, 1):
        rel = str(path.relative_to(CORPUS_ROOT))
        try:
            events = process_file(path)
            oracle[rel] = events
            success += 1
            if idx % 200 == 0 or idx == len(files):
                print(f"[{idx}/{len(files)}] {rel}: {len(events)} events")
        except Exception as e:
            # Log failure, never crash
            msg = f"{rel}: {e}"
            failures.append(msg)
            # Also capture traceback for debugging
            tb = traceback.format_exc()
            print(f"FAIL [{idx}/{len(files)}] {msg}", file=sys.stderr)
            # Optionally print traceback for first few
            if len(failures) <= 5:
                print(tb, file=sys.stderr)

    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    # Ensure deterministic order: sort keys
    sorted_oracle = {k: oracle[k] for k in sorted(oracle.keys())}
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(sorted_oracle, f, ensure_ascii=False)

    print("\n=== Summary ===")
    print(f"Total discovered: {len(files)}")
    print(f"Succeeded: {success}")
    print(f"Failed: {len(failures)}")
    if failures:
        print("Failures (first 20):")
        for msg in failures[:20]:
            print(f"  {msg}")
    print(f"Wrote {OUTPUT_PATH} with {len(sorted_oracle)} entries")
    # Also report total events
    total_events = sum(len(v) for v in sorted_oracle.values())
    print(f"Total note-on events: {total_events}")
    # Count staff breakdown
    staff_counts = {}
    for evts in sorted_oracle.values():
        for _, _, st in evts:
            staff_counts[st] = staff_counts.get(st, 0) + 1
    print(f"Events per staff: {staff_counts}")


if __name__ == "__main__":
    main()
