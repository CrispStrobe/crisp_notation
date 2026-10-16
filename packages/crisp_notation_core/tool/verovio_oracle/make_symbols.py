#!/usr/bin/env python3
"""
Per-bar symbol counts against Verovio (Task 2).

For each MusicXML file, loads with Verovio (inputFrom musicxml, expandNever True),
takes tk.getMEI(), and for each <measure> in document order, inside <staff n="1">
only, counts:
  rests: <rest> + <mRest> + <multiRest> (NOT <space>, NOT <mSpace>)
  accidentals: <accid> with accid attr, plus <note> with accid attr (written,
    not accid.ges), excluding notes inside <graceGrp> or with grace attr.

Output $CRISP_NOTATION_CORPUS/verovio-oracle/symbols.json:
  {relative_path: [[rests, accidentals], ...one per measure...]}

Robust: each file in try/except, log failures, never crash.
Reuses find_files from make_oracle.py.
"""

import json
import os
import sys
import traceback
import xml.etree.ElementTree as ET
from pathlib import Path

# Reuse find_files from the existing oracle builder if available.
# The previous task's file lives outside the repo; import it if present,
# otherwise copy the logic.
try:
    # When running from repo, the outside file is at /mnt/volume1/notation-corpus/verovio-oracle/make_oracle.py
    import importlib.util as _ilu
    _spec = _ilu.spec_from_file_location("make_oracle", "/mnt/volume1/notation-corpus/verovio-oracle/make_oracle.py")
    if _spec and _spec.loader:
        _mod = _ilu.module_from_spec(_spec)
        _spec.loader.exec_module(_mod)
        find_files = _mod.find_files
        CORPUS_ROOT = _mod.CORPUS_ROOT
    else:
        raise ImportError
except Exception:
    # Fallback: copy of find_files
    CORPUS_ROOT = Path(os.environ.get("CRISP_NOTATION_CORPUS", "/mnt/volume1/notation-corpus"))
    def find_files():
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
                parts = Path(root).parts
                if "ly-src" in parts:
                    continue
                if "StringQuartets" in parts:
                    continue
                dirs[:] = [d for d in dirs if d not in (".git",)]
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
        files.sort(key=lambda p: str(p))
        return files

# Output path respects env var as spec says $CRISP_NOTATION_CORPUS/verovio-oracle/symbols.json
OUTPUT_PATH = Path(os.environ.get("CRISP_NOTATION_CORPUS", str(CORPUS_ROOT))) / "verovio-oracle" / "symbols.json"

try:
    import verovio
except ImportError as e:
    print(f"Failed to import verovio: {e}", file=sys.stderr)
    sys.exit(1)


def count_symbols_for_measure(measure_elem, staff_elem, ns):
    """
    Count rests and accidentals for one <measure> and its <staff n="1">.

    measure_elem: ET element for <measure>
    staff_elem: ET element for <staff n="1"> inside measure (or None)
    Returns (rests, accidentals).

    We need to handle grace exclusion. For accidentals, we need to exclude
    notes inside graceGrp or with grace attr. To do that we need parent
    tracking, so we do a manual traversal of the staff subtree.
    """
    if staff_elem is None:
        return (0, 0)

    # Helper to check if element is inside grace context
    # We will do iterative DFS with stack of (elem, inside_grace)
    # inside_grace true if any ancestor is graceGrp or ancestor note has grace attr
    rests = 0
    accidentals = 0

    # Use stack for DFS: each entry is (elem, inside_grace, parent_tag)
    # We need to know if current elem is inside a graceGrp or its ancestor note is grace
    # For simplicity, we push children with updated inside_grace flag.
    # inside_grace flag is true if:
    #   - current elem is <graceGrp>
    #   - or ancestor is graceGrp
    #   - or ancestor is <note> with grace attr
    # But spec for accidentals says: exclude <note> elements with accid attr if they are
    # inside <graceGrp> or with grace attr. So for counting note@accid, we check
    # if note itself has grace attr or is inside graceGrp.
    # For <accid> we count if it has accid attr, but should we also exclude if its
    # parent note is grace? Probably yes to be consistent, but spec only mentions
    # excluding notes, not accid. We'll exclude accid if its ancestor note is grace
    # or inside graceGrp as well, to avoid counting grace accidentals.

    # Build stack: start with staff_elem, not inside grace
    stack = [(staff_elem, False)]

    while stack:
        elem, inside_grace = stack.pop()
        # Determine tag without namespace
        tag = elem.tag
        if "}" in tag:
            tag = tag.split("}", 1)[1]

        # Update inside_grace for children based on current elem
        # If current is graceGrp, then children are inside grace
        # If current is note with grace attr, then its descendants (accid) are also grace
        new_inside_grace = inside_grace
        if tag == "graceGrp":
            new_inside_grace = True
        if tag == "note" and "grace" in elem.attrib:
            # This note itself is grace; its children (like accid) are also grace
            # But for counting note@accid, we need to know if note itself is grace,
            # so we should not count this note's accid attr.
            # We'll handle counting before updating flag for children, but for
            # children we set flag.
            new_inside_grace = True

        # Count rests: <rest>, <mRest>, <multiRest> anywhere under staff
        if tag in ("rest", "mRest", "multiRest"):
            rests += 1
        # Count accidentals
        if tag == "accid" and "accid" in elem.attrib:
            # Only count if not inside grace (if parent is grace)
            if not inside_grace:
                accidentals += 1
        if tag == "note" and "accid" in elem.attrib:
            # This is a note with accid attr (written). Check not inside grace and not grace itself
            # inside_grace is flag from ancestors; also need to check if this note itself has grace attr
            # (which we already handled as new_inside_grace, but for this note we should check original inside_grace flag
            # plus its own grace attr)
            is_grace_note = "grace" in elem.attrib
            if not inside_grace and not is_grace_note:
                # Also need to ensure it's not inside graceGrp (covered by inside_grace)
                accidentals += 1
            # Note: spec says "not accid.ges" – meaning we should not count if accid attribute is actually accid.ges.
            # But in MEI, accid.ges is a different attribute name, not "accid". So checking "accid" in attrib correctly excludes accid.ges.
            # However, some notes may have both accid and accid.ges? We count only if accid present.

        # Push children onto stack (reverse order to keep document order, but order not important for counts)
        # Need to handle that Element's children are in elem (iterable)
        # We push in reverse to maintain order
        children = list(elem)
        for child in reversed(children):
            stack.append((child, new_inside_grace))

    return (rests, accidentals)


def process_file(path: Path):
    """Process one file, return list of [rests, accidentals] per measure."""
    tk = verovio.toolkit()
    tk.setOptions({"inputFrom": "musicxml", "expandNever": True})
    ok = tk.loadFile(str(path))
    if not ok:
        log = tk.getLog()
        raise RuntimeError(f"loadFile failed: {log[:500]}")
    mei = tk.getMEI()
    try:
        root = ET.fromstring(mei)
    except Exception as e:
        raise RuntimeError(f"MEI parse failed: {e}")

    ns = {"mei": "http://www.music-encoding.org/ns/mei"}
    # Find all measures in document order
    measures = root.findall(".//mei:measure", ns)
    if not measures:
        # Fallback: try without namespace (some MEI may not have namespace? but verovio always does)
        measures = root.findall(".//measure")

    result = []
    for m in measures:
        # Find staff n="1" inside this measure
        # Use findall to get all staff descendants with n=1, but we want only those that are direct children of this measure?
        # To be safe, find all staff with n=1 that are inside this measure element.
        # We can do m.findall("mei:staff[@n='1']", ns) but that only finds direct children.
        # Use .// to find any descendant staff with n=1 inside measure.
        staffs = m.findall(".//mei:staff[@n='1']", ns)
        # If not found, try without predicate
        if not staffs:
            # Fallback: find all staff and filter
            all_staffs = m.findall(".//mei:staff", ns)
            staffs = [s for s in all_staffs if s.attrib.get("n") == "1"]
            # Also check direct children
            if not staffs:
                all_staffs2 = m.findall("mei:staff", ns)
                staffs = [s for s in all_staffs2 if s.attrib.get("n") == "1"]

        if not staffs:
            # No staff 1 in this measure: count 0,0 but still record measure
            result.append([0, 0])
            continue

        # For this measure, there should be exactly one staff n=1 (or more if multiple layers? but we take first)
        # If multiple, we need to sum counts across all staff n=1 elements in this measure (should be one)
        # But to be safe, we sum across all found staffs with n=1 inside this measure.
        rests_total = 0
        accid_total = 0
        for staff in staffs:
            r, a = count_symbols_for_measure(m, staff, ns)
            rests_total += r
            accid_total += a
        result.append([rests_total, accid_total])

    return result


def main():
    files = find_files()
    print(f"Discovered {len(files)} input files")
    # Don't print all files here to avoid huge log; just print first few if needed
    # But spec says print summary, so we print summary at end.

    oracle = {}
    failures = []
    success = 0

    for idx, path in enumerate(files, 1):
        # Handle CORPUS_ROOT may be env var, need relative path
        try:
            rel = str(path.relative_to(CORPUS_ROOT))
        except ValueError:
            # If path not under CORPUS_ROOT (e.g., when CORPUS_ROOT is env var), use absolute but try to make relative to env var
            try:
                rel = str(path.relative_to(Path(os.environ.get("CRISP_NOTATION_CORPUS", str(CORPUS_ROOT)))))
            except Exception:
                rel = str(path)
        try:
            per_bar = process_file(path)
            oracle[rel] = per_bar
            success += 1
            if idx % 200 == 0 or idx == len(files):
                print(f"[{idx}/{len(files)}] {rel}: {len(per_bar)} bars")
        except Exception as e:
            msg = f"{rel}: {e}"
            failures.append(msg)
            tb = traceback.format_exc()
            print(f"FAIL [{idx}/{len(files)}] {msg}", file=sys.stderr)
            if len(failures) <= 5:
                print(tb, file=sys.stderr)

    # Write output
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
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
    total_bars = sum(len(v) for v in sorted_oracle.values())
    print(f"Total bars: {total_bars}")
    # Breakdown of rests/accidentals totals
    total_rests = sum(sum(r for r, a in v) for v in sorted_oracle.values())
    total_acc = sum(sum(a for r, a in v) for v in sorted_oracle.values())
    print(f"Total rests: {total_rests}, total accidentals: {total_acc}")


if __name__ == "__main__":
    main()
