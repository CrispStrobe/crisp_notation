# C6 — multi-part document model: handover

**Status: RECONCILED** (branch `feat/c6-reconcile`). The two designs below were
merged as planned: A stays the layout primitive; B's `MultiPartScore` document +
`MultiPartView` widget now sit on top of it, and per-group `BarlineGroup`
barlines landed on the primitive. B's duplicate wrapping engine
(`layoutMultiPartSystem` / `system_break.dart`) was **not** ported. See the
reconciliation summary in `PLAN.md` contract **C6**. Files:
`multi_part.dart` + `multi_part_view.dart` (new), `staff_system.dart` /
`multi_system.dart` (extended); tests `multi_part_test.dart` /
`multi_part_view_test.dart`; goldens 122/123. Remaining: increments (3)
interchange and (4) editor integration — additive, unblocked.

The original fork analysis and plan are kept below for reference.

---

**Status:** forked. Reconcile the two designs below **before** implementing more.

Workshop contract C6 asks for a *first-class multi-part document* — several
instrument parts sharing one timeline, with barlines aligned across parts, that
breaks into systems and paginates. Two agents built toward it in parallel with
**different designs**, so C6 must be reconciled first.

## What exists

### A. Public `main` — the layout primitive (increment 1)

`layoutStaffSystemSystems(StaffSystem document, LayoutSettings, {maxWidth, …})`
→ `StaffSystemSystems` (in `partitura_core/lib/src/layout/multi_system.dart`).

- Takes an N-part `StaffSystem` and breaks it into systems no wider than
  `maxWidth`, packing measures by the widest part so **barlines align across
  every part**. Draws the time signature only on the first system; justifies
  non-final systems with a shared note-spacing stretch.
- Reuses the existing `_slice` / `_stateArrays` sub-scoring helpers (same ones
  `layoutGrandStaffSystems` uses). It is the exact N-part counterpart of
  `layoutGrandStaffSystems`.
- Required additions to `layoutStaffSystem`: `spacingStretch`,
  `drawTimeSignature`, `finalBarline`.
- Tests: `staff_system_systems_test.dart` (wrap / measure-coverage / cross-part
  barline alignment / first-system-only time sig / justify / errors).
- Returns `StaffSystemSystem` per line, each with `firstMeasure` / `lastMeasure`.

This layer is **pure layout** — it has no document model and no widget.

### B. Private clone — the document + widget (not yet on public `main`)

A separate design in `partitura-private` (must be moved to public):

- `MultiPartScore` model + `MultiPartScore.fromStaffSystem` (bridges importers).
- Multi-part line-breaking + pagination.
- A `MultiPartView` widget (with `hideEmptyStaves`).

This layer is a **document type + Flutter view**, overlapping increments 2–4.

## Reconciliation plan (do this first)

The two are complementary, not competing — keep both, layered:

1. Keep **A** (`layoutStaffSystemSystems` / `StaffSystemSystems`) as the layout
   primitive. It is tested and aligned with `layoutGrandStaffSystems`.
2. Keep **B**'s `MultiPartScore` as the *document model* and `MultiPartView` as
   the *widget*, but have them **call `layoutStaffSystemSystems` underneath**
   rather than re-implementing the wrapping/justification. Concretely:
   `MultiPartScore` → build a `StaffSystem` (one `Score` per part) → feed
   `layoutStaffSystemSystems` → paginate the resulting systems.
3. Move B's commits from `partitura-private` onto public `main`, deleting any
   duplicate wrapping/justification logic in favour of A.
4. Delete whichever pagination code duplicates `layoutPages`
   (`PagedLayout` already paginates a `List<StaffSystem>` — a
   `List<StaffSystemSystem>` maps straight onto it).

## Remaining increments (after reconciliation — all additive)

2. **Paginated view.** `StaffSystemSystems` → `layoutPages` → a page widget
   mirroring `ScorePageView`, drawing each system's staves + brackets +
   barline connectors. Add a golden.
3. **Interchange.** Point `staffSystemFromMusicXml` (and the other multi-part
   importers) at the wrapped document so multi-part MusicXML round-trips to
   wrapped pages.
4. **Editor integration.** Extend the C1–C5 hit-testing / overlays
   (`elementRegions`, `rectOfElement`) across the multi-part view (cross-part).

None are blocked once A and B are merged. See PLAN.md contract **C6** for the
inline fork note.
