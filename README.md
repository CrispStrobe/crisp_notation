# partitura

Music notation rendering for Dart & Flutter, with first-class interactivity.

**Status: v0.1 feature-complete, pre-publication.** All five milestones of
the implementation contract ([HANDOVER.md](HANDOVER.md) as amended by
[HANDOVER_PARTITURA.md](HANDOVER_PARTITURA.md)) are implemented and tested.
The implemented feature set and the API guarantees consumers may rely on
are described in [docs/CONTRACT.md](docs/CONTRACT.md); design decisions
are logged in [docs/DESIGN.md](docs/DESIGN.md).

![partitura rendering](packages/partitura/doc/hero.png)

| Package | Contents | Depends on |
|---|---|---|
| [`partitura_core`](packages/partitura_core) | Music theory model (pitch, duration, key, scale, chord, harmonic function), score document model, deterministic layout engine. Pure Dart. | Dart SDK only |
| [`partitura`](packages/partitura) | Flutter rendering (`StaffView`) and interaction (`InteractiveStaff`): hit-testing, selection, drag-to-staff. Bundles the Bravura SMuFL font. | Flutter, `partitura_core` |

## Why another notation library?

VexFlow, OpenSheetMusicDisplay and abcjs are JavaScript and render statically.
partitura targets Flutter apps that need **interactive** notation — education
games, ear-training, theory drills — where every notehead must be tappable,
draggable and highlightable.

Not (yet) a full engraver, but closing in — see
[PLAN.md](PLAN.md)/[docs/ROADMAP.md](docs/ROADMAP.md). Today: single
staff, four clefs, notes/rests from breve to 64th with dots, accidentals
with measure memory, key/time signatures incl. mid-score changes, chords,
multi-level beaming, tuplets, ties, slurs, articulations, dynamics +
hairpins, grace notes, repeats and voltas. Still out: grand staff, line
breaking, lyrics, MusicXML (planned); audio (never).

## License

Code: [MIT](LICENSE). Bundled Bravura font: SIL OFL 1.1 (© Steinberg Media
Technologies GmbH), see [OFL.txt](packages/partitura/assets/fonts/OFL.txt).

## Development

Pub workspace (Dart ≥ 3.5): `dart pub get` at the repo root resolves both
packages. Gates: `dart format .`, `flutter analyze`, `flutter test` in each
package.
