# partitura

Music notation rendering for Dart & Flutter, with first-class interactivity.

**Status: 0.4.0-dev, pre-publication.** Well past the original five-milestone
contract ([HANDOVER.md](HANDOVER.md), amended by
[HANDOVER_PARTITURA.md](HANDOVER_PARTITURA.md)); active development now follows
[PLAN.md](PLAN.md). API guarantees consumers may rely on are in
[docs/CONTRACT.md](docs/CONTRACT.md); design decisions are logged in
[docs/DESIGN.md](docs/DESIGN.md); the running feature log is
[packages/partitura_core/CHANGELOG.md](packages/partitura_core/CHANGELOG.md).

![partitura rendering](packages/partitura/doc/hero.png)

| Package | Contents | Depends on |
|---|---|---|
| [`partitura_core`](packages/partitura_core) | Music theory model (pitch, duration, key, scale, chord, harmonic function), score document model, deterministic layout engine. Pure Dart. | Dart SDK only |
| [`partitura`](packages/partitura) | Flutter rendering (`StaffView`) and interaction (`InteractiveStaff`): hit-testing, selection, drag-to-staff. Bundles the Bravura SMuFL font. | Flutter, `partitura_core` |
| [`partitura_cli`](packages/partitura_cli) | Command-line tool: inspect scores, convert between MusicXML / `.mxl` / MIDI / MuseScore / `.gp` / ABC, render to SVG (notation or tab). Pure Dart. | `partitura_core` |

## Why another notation library?

VexFlow, OpenSheetMusicDisplay and abcjs are JavaScript and render statically.
partitura targets Flutter apps that need **interactive** notation — education
games, ear-training, theory drills — where every notehead must be tappable,
draggable and highlightable.

Not (yet) a full engraver, but closing in — see [PLAN.md](PLAN.md).

**Engraving.** Notes/rests breve→64th with dots, accidentals with measure
memory, chords, multi-level beaming (feathered, forced-slant, over rests),
tuplets, ties, slurs, articulations (incl. up/down bow), ornaments, dynamics +
hairpins, grace notes, tremolo. Key/time signatures with mid-score changes and
common/cut symbols; repeats, voltas and D.C./D.S./coda navigation.

**Structure.** N-staff systems and grand staff with brackets/braces, automatic
line-breaking into systems, pagination with margins and vertical justification,
pickup/anacrusis with measure numbering, transposing instruments with a
concert-pitch toggle. Clefs: treble/bass/alto/tenor (+ octave variants) and a
neutral percussion clef.

**Breadth.** Lyrics (verses, hyphenation, melisma), figured bass, chord
symbols, jazz articulations, breath marks, custom noteheads and per-element
coloring, and full guitar **tablature** with techniques.

**Interchange.** MusicXML (plain and compressed `.mxl`), MEI, Humdrum `**kern`,
MIDI, MuseScore (`.mscx`/`.mscz`), the `.gp3`–`.gp5`/`.gpx`/`.gp` tablature
family (with GPIF), and ABC — all importing and (where applicable) exporting
through the one `Score` model, so any pair round-trips for shared data; plus
LilyPond `.ly` export.

**Optical music recognition.** A staff-notation image imports to a `GrandStaff`
score via the [CrispEmbed](https://github.com/CrispStrobe/CrispEmbed) Sheet Music
Transformer — the engine emits `bekern` tokens that map into the one `Score`
model, so a scan then exports like any other input (image → MusicXML/`**kern`/…).
The `bekern`→score conversion is pure Dart; the recognition engine is loaded over
FFI (`partitura omr`, see the CLI).

**Beyond the category.** A renderer-free deterministic layout engine,
hit-testing, a highlight/timing pipeline, educational overlays (note names,
beat counts), SVG/PNG export, a CLI, and a WasmGC-compilable core that runs the
theory + interchange codecs in the browser (`dart compile wasm`).

Still out: full-system skyline collision avoidance and page frames/spacers
(in progress); audio synthesis (never).

## License

Code: [MIT](LICENSE). Bundled Bravura font: SIL OFL 1.1 (© Steinberg Media
Technologies GmbH), see [OFL.txt](packages/partitura/assets/fonts/OFL.txt).

## Development

Pub workspace (Dart ≥ 3.5): `dart pub get` at the repo root resolves both
packages. Gates: `dart format .`, `flutter analyze`, `flutter test` in each
package.
