# HANDOVER AMENDMENT: the project is named `partitura`, not `neume`

Read **HANDOVER.md first** — it is the full contract and remains binding.
Then apply this amendment. Where the two documents conflict, **this one
wins**. It exists because the maintainer renamed the project after the
original contract was written; HANDOVER.md is kept verbatim as the reference
document.

## 1. Renaming rules

Apply this mapping to every occurrence in HANDOVER.md:

| HANDOVER.md says | Read as |
|---|---|
| `neume` (repo, brand) | `partitura` |
| `neume_core` (package) | `partitura_core` |
| `neume` (Flutter package) | `partitura` |
| `packages/neume_core/…` | `packages/partitura_core/…` |
| `packages/neume/…` | `packages/partitura/…` |
| `lib/neume_core.dart` | `lib/partitura_core.dart` |
| `lib/neume.dart` | `lib/partitura.dart` |
| `NeumeTheme` | `PartituraTheme` |
| font family `'packages/neume/Bravura'` | `'Bravura'` with `package: 'partitura'` in the `TextStyle` |

Both `partitura` and `partitura_core` were verified free on pub.dev on
2026-07-10 (same day as the original `neume` check — the neume claim is
void). Everything else in HANDOVER.md — licensing rules (§2), architecture
and the public API contract (§4), testing (§5), documentation (§6),
milestones (§7), acceptance checklist (§8), working agreements (§10) — is
unchanged and stands as written.

Widget and type names that are not brand-derived (`StaffView`,
`InteractiveStaff`, `StaffTarget`, `Score`, `LayoutEngine`, …) are unchanged.

## 2. Scaffold state at handover (post-rename, all verified green)

The repository has been renamed and re-verified. What exists now:

- **Workspace**: root `pubspec.yaml` lists `packages/partitura_core` and
  `packages/partitura`; `dart pub get` at the root resolves cleanly.
- **Assets** (in `packages/partitura/assets/`): `fonts/Bravura.otf` (512 KB,
  verified OpenType), `fonts/OFL.txt` (Steinberg's OFL 1.1 text),
  `smufl/bravura_metadata.json` (733 KB). The font is declared in the
  package pubspec under family `Bravura` — consumers get it automatically.
- **Seed source** (compiling, tested, lint-clean under the strict
  `analysis_options.yaml` including `public_member_api_docs`):
  - `partitura_core/lib/src/theory/pitch.dart`: `Step`, `Clef`,
    `DurationBase`, `NoteDuration`, `Pitch` with `midiNumber`,
    `diatonicIndex` and `staffPosition(Clef)` implementing the binding
    conventions (C4 = 60; bottom line = position 0; treble E4 = 0,
    bass G2 = 0). 6 unit tests pass.
  - `partitura/lib/src/rendering/staff_view.dart`: placeholder `StaffView`
    drawing five staff lines and a baseline-anchored SMuFL clef glyph
    (U+E050 gClef / U+E062 fClef) via `TextPainter` at font size =
    4 x staff space. 1 widget test passes.
  - `partitura/lib/src/rendering/theme.dart`: minimal `PartituraTheme`.
- **Seed status**: per HANDOVER.md §9, the seed is replaceable scaffolding —
  except that (a) the conventions encoded in `pitch.dart` and its tests are
  binding (they match DESIGN.md and the consuming app's expectations), and
  (b) the baseline-anchoring technique in `_StaffPainter` is the intended
  glyph-positioning approach and worth carrying into the real renderer.
- **Docs**: `docs/DESIGN.md` is pre-seeded with the binding conventions and
  the naming history; `README.md` (root + per package), `CHANGELOG.md` and
  MIT `LICENSE` files are in place in both packages.
- **Gates verified at handover**: `flutter analyze` — no issues in either
  package; `dart test` / `flutter test` — all passing; `dart format` — no
  changes. Keep them that way (HANDOVER.md §5).

## 3. Consumer state

The consuming app (working title KlangUniversum, `../mus`) now depends on
`partitura` via `path: ../partitura/packages/partitura` and its `flutter pub
get` / `analyze` / `test` are green. It does **not yet import** any partitura
symbols in its source, so in this early phase you may still adjust seed API
surface freely; from M3 onward (HANDOVER.md §7) treat the public API as the
contract in §4 and avoid gratuitous breaks. If you must break something the
app plausibly uses, note it in `docs/DESIGN.md`.

## 4. Kickoff order

1. Read HANDOVER.md fully, applying §1 of this amendment.
2. Read `docs/DESIGN.md` and the seed source in both packages.
3. Start milestone M1 (theory core). Go.
