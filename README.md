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

Deliberately *not* a full engraver: no multi-voice collision avoidance, slurs,
tuplets or page justification. Single staff, both clefs, notes/rests to
sixteenths, dots, accidentals, key/time signatures, triads, simple beaming.

## License

Code: [MIT](LICENSE). Bundled Bravura font: SIL OFL 1.1 (© Steinberg Media
Technologies GmbH), see [OFL.txt](packages/partitura/assets/fonts/OFL.txt).

## Development

Pub workspace (Dart ≥ 3.5): `dart pub get` at the repo root resolves both
packages. Gates: `dart format .`, `flutter analyze`, `flutter test` in each
package.
