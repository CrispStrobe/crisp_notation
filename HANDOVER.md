# HANDOVER: Build `neume` — a music notation rendering library for Dart/Flutter

You are an autonomous engineering agent. Your task is to implement **neume**, an
MIT-licensed music notation rendering library for Dart/Flutter, in this
repository. This document is your complete contract: scope, architecture,
public API, licensing rules, quality gates, and acceptance criteria. Where this
document is silent, use your judgment; where it is explicit, follow it.

---

## 1. Mission

Build the library the Flutter ecosystem is missing: a **VexFlow-class notation
renderer with first-class interactivity**, in pure Dart/Flutter. It will be:

1. Published to pub.dev under the names `neume_core` and `neume` (names are
   verified free as of 2026-07-10 — do not rename).
2. Consumed immediately by **KlangUniversum** (working title), a children's
   (6+) music-learning app living at `../mus`, built from interactive
   minigames (drag a note onto a staff, tap the correct rest, build a triad,
   fill a measure so the durations sum to the time signature).
3. Offered to the community as a general-purpose package.

The differentiator over VexFlow/OSMD/abcjs is **interaction**: every rendered
element is identifiable, hit-testable, highlightable, and draggable. Education
apps fight static SVG renderers; neume treats interactivity as a core layer,
not an afterthought.

### Explicit non-goals (v0.x)

Do NOT build these. If you finish everything else, stop and report rather than
starting any of these:

- Full engraving: multi-voice collision avoidance, slurs/ties with Bézier
  shaping, tuplets, grace notes, cross-staff beaming, lyrics, dynamics,
  articulations, page/line breaking and justification across systems.
- MusicXML import/export (a later minor version may add a subset; not now).
- Audio/playback of any kind. neume renders; it never makes sound.
- Grand staff / multiple simultaneous staves (v0.2 candidate; design so it
  isn't precluded, but don't implement).
- Transposing instruments, percussion notation, tablature.

---

## 2. Licensing contract (hard constraints)

- All code you write: **MIT**. The root `LICENSE` file is already in place.
- Runtime dependencies: **none** beyond the Dart and Flutter SDKs.
  `neume_core` must not depend on Flutter at all (pure Dart). Dev dependencies
  (`test`, `flutter_test`, `flutter_lints`) are fine.
- Do NOT add `music_notes` (BSD-3) or any other theory package as a
  dependency — we own the theory core (it's small at our scope, and we shape
  it for pedagogy).
- Fonts: **Bravura** (SMuFL reference font) is bundled under **SIL OFL 1.1**.
  This is the industry-standard arrangement (VexFlow does the same). The
  font's OFL license text must ship in `packages/neume/assets/fonts/OFL.txt`
  and be mentioned in the README's license section. Never convert, subset, or
  rename the font (OFL "Reserved Font Name" clause).
- Anything LGPL/GPL is forbidden anywhere in the dependency tree, including
  dev tooling that gets redistributed.

---

## 3. Repository layout (already scaffolded — keep it)

Pub workspace (Dart ≥ 3.5 native workspaces, no melos):

```
neume/
├── pubspec.yaml              # workspace root
├── HANDOVER.md               # this contract
├── LICENSE                   # MIT
├── README.md                 # top-level readme, keep updated
├── analysis_options.yaml     # strict lints, shared
├── docs/
│   └── DESIGN.md             # you maintain this: decisions + rationale
└── packages/
    ├── neume_core/           # pure Dart: theory, document model, layout
    │   ├── lib/
    │   │   ├── neume_core.dart          # single public entrypoint
    │   │   └── src/
    │   │       ├── theory/    # pitch, duration, key, time, interval, scale, chord
    │   │       ├── model/     # score, measure, elements
    │   │       ├── layout/    # layout engine (unit: staff spaces)
    │   │       └── smufl/     # glyph name→codepoint table, metadata types
    │   └── test/
    └── neume/                # Flutter: rendering + interaction
        ├── lib/
        │   ├── neume.dart               # re-exports neume_core + widgets
        │   └── src/
        │       ├── rendering/ # painters, glyph painting, theme
        │       └── interaction/ # hit testing, drag, controllers
        ├── assets/
        │   ├── fonts/Bravura.otf, OFL.txt
        │   └── smufl/bravura_metadata.json
        ├── example/          # runnable Flutter demo app
        └── test/             # widget + golden tests (test/goldens/)
```

---

## 4. Architecture: four layers, strictly ordered

Dependencies point downward only. A layer never imports from a layer above it.

```
4. interaction   (neume)       taps, drags, selection, input controllers
3. rendering     (neume)       CustomPainter/RenderObject, theme, px conversion
2. layout        (neume_core)  positions in STAFF SPACES, pure & deterministic
1. theory+model  (neume_core)  pitch/duration/key/... + score document tree
```

### Layer 1: Theory + document model

Value types, immutable, `==`/`hashCode` correct (implement by hand or with
records; no `equatable` dependency). This is the pedagogical vocabulary:

```dart
enum Step { c, d, e, f, g, a, b }

class Pitch {
  final Step step;
  final int alter;        // -2..2 (bb, b, natural, #, ##)
  final int octave;       // scientific pitch notation; middle C = C4
  const Pitch(this.step, {this.alter = 0, this.octave = 4});

  int get midiNumber;                       // C4 == 60
  /// Diatonic staff position for [clef]: 0 = bottom line, 1 = first space,
  /// counting upward. Negative/large values imply ledger lines.
  int staffPosition(Clef clef);
  Pitch transposeBy(Interval interval);
  bool isEnharmonicWith(Pitch other);
}

enum Clef { treble, bass }                  // alto/tenor: v0.2

enum DurationBase { whole, half, quarter, eighth, sixteenth }

class NoteDuration {
  final DurationBase base;
  final int dots;                           // 0..2
  const NoteDuration(this.base, {this.dots = 0});
  /// Fraction of a whole note, exact rational (implement a tiny Fraction
  /// class — no dependency): quarter == 1/4, dotted quarter == 3/8.
  (int num, int den) get fraction;
}

class KeySignature {
  final int fifths;                         // -7..7; -1 = F major/D minor
  const KeySignature(this.fifths);
  List<Step> get alteredSteps;              // which steps carry the ♯/♭
  int alterFor(Step step);                  // -1/0/1 from the signature
}

class TimeSignature {
  final int beats; final int beatUnit;      // 3/4 -> beats:3, beatUnit:4
  (int, int) get measureCapacity;           // as fraction of whole note
}

class Interval { /* quality + number; enough for P1..P8, M/m 2,3,6,7, A4/d5 */ }

enum ScaleType { major, naturalMinor, harmonicMinor, melodicMinor }
class Scale {
  final Pitch tonic; final ScaleType type;
  List<Pitch> get pitches;                  // one octave ascending
}

enum ChordQuality { major, minor, diminished, augmented }
class Triad {
  final Pitch root; final ChordQuality quality;
  final int inversion;                      // 0, 1, 2
  List<Pitch> get pitches;
}

/// Functional harmony, the pedagogy target (Tonika/Subdominante/Dominante).
enum HarmonicFunction { tonic, subdominant, dominant }
class Key {
  final Pitch tonic; final bool isMajor;
  KeySignature get signature;
  Triad triadFor(HarmonicFunction f);       // e.g. C major: T=C, S=F, D=G
}
```

Document model — a shallow tree, every element optionally tagged with an `id`
for the interaction layer:

```dart
class Score {
  final Clef clef;
  final KeySignature keySignature;
  final TimeSignature? timeSignature;       // null = unmetered snippet
  final List<Measure> measures;
}

class Measure { final List<MusicElement> elements; }

sealed class MusicElement { final String? id; }
class NoteElement extends MusicElement {
  final List<Pitch> pitches;                // length 1 = note, >1 = chord
  final NoteDuration duration;
  final bool showAccidental;                // force/hide courtesy accidental
}
class RestElement extends MusicElement { final NoteDuration duration; }
```

Provide a terse builder/DSL so tests and games stay readable, e.g.
`Score.simple(clef: Clef.treble, notes: 'c4:q d4:q e4:h')` — exact string
grammar is your call; document it.

### Layer 2: Layout engine (the heart — pure, deterministic, testable)

```dart
class LayoutSettings {
  // Engraving defaults seeded from bravura_metadata.json "engravingDefaults";
  // all distances in STAFF SPACES (1 space = gap between adjacent staff lines).
  final double staffLineThickness, stemThickness, legerLineExtension, ...;
}

class LayoutEngine {
  ScoreLayout layout(Score score, LayoutSettings settings);
}

/// Flat display list + hit information. Coordinates in staff spaces,
/// origin = intersection of the staff's top line with its left edge,
/// y grows downward.
class ScoreLayout {
  final double width, height;               // staff spaces
  final List<LayoutPrimitive> primitives;
  final List<ElementRegion> regions;        // hit boxes, tagged with element id
}

sealed class LayoutPrimitive { final String? elementId; }
class GlyphPrimitive extends LayoutPrimitive { final String smuflName; final Offset position; }
class LinePrimitive  extends LayoutPrimitive { final Offset from, to; final double thickness; } // staff lines, stems, ledger, barlines
class BeamPrimitive  extends LayoutPrimitive { final Offset start, end; final double thickness; } // filled parallelogram
```

Layout rules you must implement (this is the checkable core of the project;
each rule gets its own unit tests):

1. **Staff & clef**: five lines; gClef anchored on line 2 (G4), fClef on
   line 4 (F3). SMuFL anchors from the metadata, not hardcoded eyeballing.
2. **Key signature**: standard sharp order F C G D A E B / flat order
   B E A D G C F, at the conventional octaves per clef.
3. **Time signature**: stacked `timeSigN` digits centered on the staff.
4. **Noteheads**: `noteheadWhole`/`noteheadHalf`/`noteheadBlack` by duration;
   vertical position from `Pitch.staffPosition`.
5. **Stems**: down when notehead is on or above the middle line, else up;
   default length one octave (3.5 spaces), extended toward the middle line
   for notes far outside the staff. Stem attaches at the notehead's SMuFL
   stem anchor (`stemUpSE`/`stemDownNW`).
6. **Flags**: `flag8thUp`/`Down`, `flag16thUp`/`Down` when not beamed.
7. **Beaming**: group eighths/sixteenths within a beat (beat from the time
   signature; simple-meter grouping only). Straight beams, horizontal or
   with slant clamped to ±1 space. No beaming across rests or beats.
8. **Ledger lines**: for positions outside the staff, extending
   `legerLineExtension` beyond the notehead on both sides.
9. **Accidentals**: to the left of the notehead with correct clearance.
   Show when the pitch's `alter` differs from what the key signature +
   earlier accidentals in the same measure imply; `showAccidental` overrides.
   (Single-accidental chords only need naive vertical stacking.)
10. **Augmentation dots**: right of the notehead; for a notehead on a line,
    the dot sits in the space above.
11. **Chords**: shared stem; seconds resolved by offsetting the interfering
    notehead to the other side of the stem.
12. **Rests**: correct glyph, conventional vertical home (whole rest hangs
    from line 4, half rest sits on line 3, etc.).
13. **Horizontal spacing**: leading elements (clef, key, time) at fixed
    spacings, then notes/rests spaced proportionally to duration with a
    minimum gap — simple `widthFor(duration) = base + k * log2(duration)`
    style is fine; document the formula. Barlines between measures,
    `barlineFinal` at the end.
14. **Determinism**: same input + settings → identical layout, no RNG, no
    clock, no platform dependence. (This is what makes goldens meaningful.)

### Layer 3: Rendering (Flutter)

```dart
class NeumeTheme {
  final Color staffColor, noteColor, highlightColor;
  final Map<String, Color> elementColors;   // per element-id override
  final bool kidMode;                        // thicker lines, larger hit slop
  static const NeumeTheme standard, kids;
}

/// The one widget most users touch.
class StaffView extends StatelessWidget {
  final Score score;
  final NeumeTheme theme;
  final double? staffSpace;   // px per staff space; null = fit to width
  final Set<String> highlightedIds;
  final void Function(String elementId)? onElementTap;
}
```

- Implemented as a `LeafRenderObjectWidget` (preferred) or CustomPaint;
  layout comes from `LayoutEngine`, painting converts staff spaces → px by a
  single scale factor. No layout logic in the painting code.
- Glyphs are painted via `TextPainter` using the bundled Bravura font
  (family `'Bravura'`, declared in the package pubspec so consumers get it
  automatically as `packages/neume/Bravura`). Font size for one staff space
  scaling: SMuFL fonts are designed so font-size = 4 × staff space.
- Ship a small generated table `smufl_glyphs.dart` mapping the ~60 glyph
  names we use to codepoints (from `glyphnames.json` upstream or hardcoded
  from the SMuFL spec — they are stable). Parse
  `assets/smufl/bravura_metadata.json` at first use for anchors and
  engraving defaults; cache the parsed result.

### Layer 4: Interaction (the differentiator)

```dart
/// Wraps StaffView with gesture handling.
class InteractiveStaff extends StatefulWidget {
  final Score score;
  final NeumeTheme theme;
  final void Function(String elementId)? onElementTap;
  /// Fired when the user taps/drops on an empty staff location; position is
  /// quantized to the nearest staff position (line/space, incl. ledger range).
  final void Function(StaffTarget target)? onStaffTap;
  /// Ghost note (semi-transparent preview) following a drag, quantized.
  final bool showGhostNote;
  final NoteDuration ghostDuration;
}

class StaffTarget {
  final int staffPosition;    // same convention as Pitch.staffPosition
  final int measureIndex;
  final Pitch pitchFor(Clef clef, {int preferredAlter = 0});
}
```

- Hit testing uses `ScoreLayout.regions`, inflated by a `hitSlop` from the
  theme (kidMode = generous slop — children's motor precision is limited).
- Selection/highlight must not relayout — repaint only.
- This layer is what the minigames build on: "drag the quarter note onto F",
  "tap the element that doesn't fit the measure", "which note is the root?".

---

## 5. Testing contract

- **Theory**: exhaustive unit tests — every scale type from every reasonable
  tonic, all key signatures −7..7, triads incl. inversions, midi numbers,
  staff positions in both clefs, enharmonics, interval arithmetic.
- **Layout**: unit tests per rule in §4.2 asserting on `ScoreLayout`
  primitives (e.g. "B4 in treble has stem down", "F♯ major signature places
  6 sharps at these positions", "4/4 measure of 8 eighths yields 2 beams").
- **Golden tests** (`neume` package): a corpus of ~20 small scores rendered
  at fixed size, covering both clefs, all durations, dots, accidentals,
  chords, beams, rests, key/time signatures. Load Bravura in test setup with
  `FontLoader`. Run on a pinned Flutter version; note in the README that
  goldens are platform-sensitive and were generated on macOS.
- **Example app** (`packages/neume/example`): gallery screen (the golden
  corpus, scrollable) + one interactive screen (tap staff to place a note,
  tap a note to select/color it). This doubles as manual QA and pub.dev demo.
- Quality gates for every commit: `dart format` clean, `flutter analyze`
  zero warnings (strict lints are configured — do not weaken them),
  `flutter test` green in both packages.

## 6. Documentation contract

- Dartdoc on **every** public symbol; `public_member_api_docs` lint stays on.
- `README.md` per package: hero screenshot (from the example app), quickstart
  snippet (< 20 lines to first rendered staff), feature matrix (what's in,
  what's explicitly out), license section incl. the OFL font notice.
- `docs/DESIGN.md`: running log of non-obvious decisions and the reasoning
  (spacing formula, beaming approach, coordinate conventions). Terse is fine.
- Maintain `CHANGELOG.md` per package (pub.dev requires it).

## 7. Milestones — commit at least once per milestone, in this order

1. **M1 theory core**: layer 1 complete with exhaustive tests. Pure Dart.
2. **M2 layout**: layers 2 with all 14 rules + unit tests. Still pure Dart —
   `neume_core` is finished and could be released alone at this point.
3. **M3 rendering**: StaffView paints the golden corpus correctly; goldens
   committed; example gallery runs.
4. **M4 interaction**: InteractiveStaff, hit testing, ghost note; example
   interactive screen; widget tests for tap→id and tap→StaffTarget mapping.
5. **M5 release polish**: docs, CHANGELOGs, pub.dev dry-run
   (`dart pub publish --dry-run` passes for both packages, score-relevant
   metadata complete). Do NOT actually publish — the maintainer publishes.

Definition of done = M5 complete + every checkbox in §8.

## 8. Acceptance checklist

- [ ] `neume_core` has zero non-SDK dependencies; `neume` depends only on
      Flutter + `neume_core`.
- [ ] All §4.2 layout rules implemented and unit-tested.
- [ ] Golden corpus (≥ 20 scores) committed and passing.
- [ ] Example app runs on macOS + web + at least one mobile simulator.
- [ ] `InteractiveStaff` supports: element tap with id, staff-position tap
      with quantization, ghost-note drag preview, per-element highlight
      colors without relayout.
- [ ] Kid mode verified: hit targets ≥ 44×44 px at default staff size.
- [ ] `dart pub publish --dry-run` clean for both packages.
- [ ] MIT + OFL licensing intact per §2; no new dependencies added.
- [ ] All public API documented; analyze/format/test gates green.

## 9. Context you may need

- The consuming app (`../mus`, Flutter, working title KlangUniversum) targets
  children from age 6: German/English i18n, minigame modules for Notenwerte,
  Notenlesen (treble/bass), Takte, Tonleitern (Dur/Moll), Akkorde/Intervalle,
  and Harmonik (Tonika/Subdominante/Dominante). It consumes neume via a path
  dependency during development. Its games are the reason interaction (§4.4)
  and the pedagogy types (`Key.triadFor`, `Scale`, `HarmonicFunction`) exist.
  You do not need to touch that repo, but if an API feels awkward, imagine
  writing "drag the note onto the staff" with it — that's the litmus test.
- SMuFL spec: https://w3c.github.io/smufl/latest/ (glyph names, anchor
  semantics, the font-size = 4 × staff-space convention).
- Bravura assets are already vendored under `packages/neume/assets/`
  (`Bravura.otf`, `bravura_metadata.json`, `OFL.txt`). If any are missing,
  fetch from https://github.com/steinbergmedia/bravura (redist/ directory).
- Placeholder source files exist in both packages so the workspace resolves
  and analyzes cleanly. They are scaffolding, not design constraints — replace
  them freely; only the public API contract in §4 is binding.

## 10. Working agreements

- Work directly in this repository on branch `main` (it is pre-release; no
  PR ceremony needed). Small, message-ful commits; at minimum one per
  milestone. Never commit with failing gates.
- If a contract requirement turns out to be technically wrong or ambiguous
  (e.g. a SMuFL anchor doesn't exist under the documented name), document the
  deviation and your resolution in docs/DESIGN.md and proceed — don't stall.
- If you genuinely cannot proceed, write the blocker into docs/DESIGN.md
  under "## Blockers" and stop.
