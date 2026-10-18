# Changelog

## 0.11.0 (2026-10-18)

Spacing measured against LilyPond (25 songs: 286 systems on 97 pages, where
LilyPond takes 294 on 95), no voice collisions left in the corpus, the
LilyPond reader agreeing with LilyPond's MIDI on 314 of 374 files (152),
MusicXML timing against Verovio on 1709 of 1745, endings in every format,
dynamics and hairpins above a vocal line, and the maxima.

- **LilyPond: string numbers in a chord.** `<g\3 b\2 e\1>` is three
  pitches; each `\N` was read as a pitch of its own, adding a C to the chord
  and throwing `\relative` off for what followed.
- **LilyPond: `e'd` is two notes.** An octave mark or a forced accidental
  ends a note as a duration does, so `c[ e'd c]` is four notes; the word was
  read as none and `\relative` drifted from there (Carcassi's study op. 60
  no. 1 played a tenth low, Contrapunctus VIII and a Horetzky study had
  wrong octaves). Lyrics keep their elisions (`d'a`).
- **LilyPond: a percent repeat takes its time.** `\repeat percent 4 { … }`
  was read as its body once, so the repeats' time was lost and the music
  after it came early. LilyPond's MIDI plays the body once and is silent
  for the repeats; the reader now does the same: a repeated whole bar is a
  measure-repeat bar, a shorter body is followed by hidden rests.
- **LilyPond: a tremolo lasts its repeats.** `\repeat tremolo 8 e32` is
  `e4:32`, a quarter with three slashes; it was read as one 32nd, and every
  later note came early. Each note of a tremolo now lasts its written value
  times the count (a one-note tremolo keeps its slashes); one no note value
  can spell is written out.
- **LilyPond: `\unfoldRepeats` anywhere.** It was honoured only written in a
  `\score`; Schubert's songs and quartet movement put it in the variables
  their MIDI score plays (`midiPiano = { \unfoldRepeats \piano }`), and
  their repeats and tremolos sounded once. Any `\unfoldRepeats` now unfolds
  the music it is given.
- **LilyPond: `\unfoldRepeats` writes tremolos out.** Under it LilyPond
  plays `\repeat tremolo 4 e16` as four sixteenths; the reader kept one.
- **LilyPond: a repeat body need not be braced.** `\repeat unfold 16 f8`
  repeats the one note after it; only a `{ … }` body was taken, so the note
  sounded once and the bar ran fifteen eighths short.
- **LilyPond: `\grace s8` and `\grace <c e>8` take no time.** A grace
  spacer (written to make room against a grace in another staff) was read
  as a real spacer and a grace chord as a real chord, so every later note
  of the voice came late (three Matiegka and Monferrina guitar pieces). A
  grace chord in `\relative` now also hands on its first note, as any
  chord does.
- **LilyPond: a grace's duration carries on.** LilyPond's default duration
  is lexical, so in `\acciaccatura { g8 } f f d4` both f are eighths. The
  reader restored the duration from before the grace group, read them as
  quarters and ran the bar a beat long (Matiegka's Rondo no. 2 for guitar).
- **LilyPond: `d8cis` is two notes.** A duration ends a note, so LilyPond
  reads letters straight after it as the next note. The reader kept the word
  whole, matched no note, and dropped both (Contrapunctus V lost a beat in
  its bass).
- **LilyPond: a note crossing the barline is cut into tied notes.** LilyPond
  bars by the clock, so a note that starts late in a bar sounds on over the
  barline. The reader closed the bar early and put the note whole into the
  next one: harmless in one voice, but a voice beside it kept full bars, and
  from there the two voices' bars were paired wrongly and drifted apart
  ("Es ist ein' Ros"). The note (or chord, or rest) is now cut at each
  barline it crosses, the pieces tied; only the first takes a syllable.
- **LilyPond: a meter change in voice 1 bars every voice.** `\time` sets
  the Score's timing. A voice read beside voice 1 started in voice 1's last
  meter and never saw its changes, so its notes were barred to the wrong
  meter and drifted against voice 1; it now keeps voice 1's meter bar by bar.
- Notes on different staves no longer hold each other apart: two adjacent
  columns of a system clear the ink of a staff that has notes at both, not
  the widest ink of any staff on each side (a voice's dotted rhythm over a
  piano's triplets set a third wider than the triplets alone). Where a staff
  still needs more than the columns give, its bar's closing column moves out
  and the staves are laid out once more, so bars always close together.
  Against LilyPond on 25 corpus songs: 286 systems on 97 pages (LilyPond:
  294 on 95).
- Staves of a system close their bars together again. Since column ink
  left out lyrics (above), a staff whose words needed more room than the
  shared columns gave — between two of its notes, or before the barline —
  ended its bar past the others' (9,434 bars in the corpus). Each staff now
  gets at least the room its own layout keeps between successive notes, at
  the line's stretch, and the closing column clears the last onset's text.
- MusicXML: a fifth voice's note that sounds while all four slots are busy
  joins, as chord tones, a note starting with it — appended after a slot's
  notes it ran the bar long, and a round trip lengthened the bar again. A
  cross-staff chord tone no longer claims its voice's slot on the other
  staff (a piano's voice 5 was written back as voice 6).
- MEI: a direction or chord symbol on a staff that was not read is dropped
  instead of dangling (layout threw on it).
- A hairpin listed twice is drawn once even when the copies disagree on
  their side.
- Pages pack systems down to `minSystemGap` 2 (was 5) staff spaces of
  clearance before justifying, as LilyPond's system padding allows; and a
  lyric line sits below the ink over each syllable rather than the lowest
  ink anywhere on the line. With the same 15 mm margins as ours, LilyPond
  sets 25 corpus songs on 95 pages; we took 109, now 100.
- **LilyPond: a pickup times every voice.** A `\partial` set at the start of
  the first voice (from a shared `\global`, or the upper part of a
  `\partcombine`) now preloads the other voices of that `<< … >>` as well;
  they used to start on a full bar, so every alto and bass note after the
  pickup landed three beats late and the hymn ran a bar long.
- **LilyPond: a pickup stated in one staff times every staff.** `\partial`
  and its `\time` belong to the Score: a hymn writing them only in the
  soprano's music now gives the lower staff the same meter and pickup bar
  (`multiPartFromLilyPond`), instead of reading it in 4/4 with no anacrusis.
- **LilyPond: `s1*0` takes no time.** A zero-length skip, the usual way to
  hang a `^\markup` on the first beat, was read as a whole-bar `s1` and put
  a bar of silence in front of the music after it.
- **LilyPond: a voice's own inner voices survive a second voice beside it.**
  In `<< \new Voice { … << {a} \\ {b} >> … } \new Voice { … } >>` (every
  guitar study with a bass voice, a piano hand with a passing split) the
  second voice was written over voice 1's inner voice, and an inner voice
  still open at the end of the split was dropped. Each now takes the first
  free voice of the bar, and a branch's own inner voices come along too.
- **LilyPond: `playback:` reads the score LilyPond plays.**
  `scoreFromLilyPond` and `multiPartFromLilyPond` take `playback: true` to
  read a source's separate `\midi`-only `\score` (repeats unfolded, a
  lead-in silence, other voicings) instead of the engraved one — what MIDI
  export, or a comparison with LilyPond's own MIDI, wants. The default is
  unchanged.
- **LilyPond: staves behind `\relative`.** `\relative a \new Staff { … }` is
  a staff of its own (it used to run on after the staff before it), and a
  `\relative a' << \new Staff … >>` around several staves gives them its
  octaves (they used to read as absolute pitches).
- **LilyPond: a mid-piece `\partial` starts a bar.** `\partial 8*3` before a
  short last bar now ends the bar before it; the short bar's notes used to
  be packed into that full bar, so a second voice's last bar fell late.
- **LilyPond: `\unfoldRepeats` is honoured.** A score that writes it reads
  every `\repeat volta`/`segno`/`percent` written out, each pass followed by
  its alternative (the first serving passes without one), with `\relative`
  octaves taken from the text as written — as LilyPond plays it. Kept as
  repeat signs, a repeat starting on a pickup or ending mid-bar could not be
  unfolded bar by bar.
- **LilyPond: a pitched rest is a rest.** `b4\rest` (a rest placed at a
  pitch, common in guitar and piano voices) read as a sounding note; it is
  now a rest, still anchoring `\relative` for the note after it.
- **LilyPond: `\relative { … }` without a start pitch** reckons its first
  note from f, as LilyPond does, so `\relative { a' }` is A4 (it read an
  octave low).
- **LilyPond: `\repeat unfold` keeps its octaves.** Each pass now starts
  from the written text's `\relative` reference, as LilyPond resolves it
  before unfolding; a body that ends higher than it starts used to climb an
  octave per pass. Its alternatives follow their passes in turn.
- **LilyPond: `<b,g>`.** A chord may join pitches without a space after an
  octave mark or a `!`/`?`; such a word was read as one unparsable pitch,
  which threw the following `\relative` octaves off.
- **Systems set as tightly as their notes allow.** Aligned columns across a
  system's staves (`alignedColumns`) counted every mark drawn under a note's
  id as that note's ink — a tuplet bracket, a dynamic, a pedal mark, a lyric
  — so the next column was pushed out by the mark's whole width. Only the
  ink standing in the column now counts (noteheads, accidentals, dots,
  flags, rests, stems, ledger lines). Measured against LilyPond on 25 songs
  from the corpus at the same page size: 373 systems → 317 (LilyPond: 298).
- **Squeezed lines.** A multi-part line a little over the width at natural
  spacing (up to 1/0.88) has its spacing tightened to fit — never its ink
  floors — instead of giving up a bar, at a planning cost that grows fast
  with the squeeze. With it, the 25 songs take 303 systems (LilyPond: 298).
- **First-system indent.** `layoutStaffSystemSystems` and
  `layoutMultiPartPages` take `firstSystemIndent`: the first system is that
  much narrower and starts further right (`StaffSystemSystem.indent`), the
  instrument names standing in front of it, while later systems use the full
  width. The PDF and SVG writers honour it; the CLI's PDF output uses it
  instead of reserving the names' room on every system.
- A dynamic the source places above the staff stands there
  (`DynamicMarking.above`, MusicXML `<direction placement="above">`, read and
  written): a vocal line's "mf" sat between the voice and its lyrics and
  pushed the words down. (A dynamic that is part of a hairpin run keeps the
  run's line below.)
- LilyPond: endings keep their passes, label and open end. `\repeat volta 3`
  with two alternatives reads "1., 2." and "3." (the first alternative takes
  the spare passes, as in LilyPond), `\alternative { \volta 1,2 { … } }`
  states them, and a `repeatCommands` label is read for its passes ("1.2.3.",
  "1.-3.") and kept as text when it says more ("Fine" is taken on the pass
  after the endings before it). A `repeatCommands` bracket now covers every
  bar up to `(volta #f)` rather than just its first, and `end-repeat` in the
  list is read. Ends follow LilyPond's own rule (a closing hook only at a
  repeat sign or the final barline), so a last ending is open; a
  `VoltaBracket.edge-height` override states otherwise. The writer labels
  each ending with all its passes or its text, and states an end that differs
  from LilyPond's rule with that override. A mid-piece `\partial` after a full
  bar no longer merges the two bars.
- ABC: endings keep every pass (`[1,2`, `[1-3`, `|1`, `:|2`) and text
  labels (`["last time"`, taken on the pass after the endings before it
  unless it names one). An ending runs on over plain bar lines to the `:|`
  that closes it, so a two-bar first ending is skipped on the last pass as a
  whole rather than only its first bar. Ends follow the engraving rule (hooked
  only at a repeat sign or the final bar line). The writer states an ending
  once when a `:|` closes it and restates it on each bar otherwise.
- MEI: `<ending>` keeps its passes from `@n` ("1-3", as real files write
  it; `@label`'s numbers when `@n` is absent), its `@label` as text when it
  says more than the numbers, and `@lendsym="none"` as an open end. The
  writer wraps all the bars of one ending in a single `<ending>` (a two-bar
  first ending was written as two), with `@label` for text or several passes
  and `@lendsym="none"` when open — in both `scoreToMei` and
  `multiPartToMei`.
- Humdrum `**kern`: endings are read the way the corpus writes them, as
  section labels ending in a number (`*>B1`, `*>B2`; only a bare `*>1` was
  read before) that run on over every bar until the next label (only the
  first bar was marked). Their passes come from the expansion list
  (`*>[A,A1,A,A1,A,A2]` takes A1 on passes 1 and 2); a da capo replaying the
  same sections adds none. Ends follow the engraving rule. The writer labels
  every section (`A`, a new letter at each `|:` and after each run of
  endings, `B1`/`B3` for the endings) and writes the expansion list, in
  `scoreToKern` and now also `multiPartToKern`, which wrote no endings.
- MEI: a `<score>` inside the header (an incipit under `meiHead > … >
  incip`) is no longer read as the music; `Beethoven_Hymn_to_joy.mei` came
  back as its opening phrase.
  pushed the words down. Hairpins likewise (`Hairpin.above`, read and
  written): a run of hairpins and dynamics whose hairpins all stand above
  goes over the staff together.
- MusicXML: a voice labelled past 4 (a piano's lower voices, 5-8) no longer
  takes the slot of voice 1-4 on the same staff. Labels 1-4 never claimed
  their slots, so a voice 5 crossing to the upper staff went after voice 1's
  notes and the bar ran long.
- MusicXML: a `<time-modification>` with no `<tuplet>` bracket now times its
  notes, through a new hidden `TupletSpan` (`hidden: true`: no bracket, no
  number; the MusicXML writer writes it back as a bare `<time-modification>`).
  Only bracketed groups were timed, so the two halves of a half-note tremolo
  (2:1) sounded a half each and the bar ran twice its meter.
- MusicXML: an unprinted note (`print-object="no"`) in a drawn voice keeps
  its time as a hidden spacer rest. As a gap before the next note it lost a
  bar's last beat, a tuplet it opened, or a length no rest spells. A voice
  past 4 that only unprinted rests play no longer takes a slot.
- MusicXML: a fifth voice on one staff (the model holds four) goes to a slot
  that is free at its onset, rather than after the notes of the slot it
  shares, which made the bar run long.
- MusicXML: a whole-bar rest keeps its written length in an unmetered
  (senza-misura) bar, and beside another voice when the bar's music ends with
  it; it was given a whole note, or the meter's length.
- MusicXML: a lone whole rest that lasts a whole note in a longer bar (half a
  bar of 4/2) rests a whole note, not the bar.
- MusicXML: a rest with no `<type>` that lasts the whole bar is read as the
  bar rest; a length no single rest spells (five 16ths, a bar of 15/8) was
  rounded to the nearest value, losing or adding time.
- MusicXML: an `<unpitched>` note with no display position sits on the
  middle line (it was read as a rest), and an unpitched chord tone (a snare
  with the hi-hat) is kept in the chord (it was dropped).
- MusicXML: quarter-tone alters (`<alter>-0.5</alter>`, `1.5`, …) read as
  microtonal accidentals (`Pitch.microtone`) and write back; they were
  rounded to a semitone, so a half-flat D read as D-flat.
- A measure repeat on a staff of a system closes its bar with the other
  staves, its sign centred in the wider bar. The sign's own fixed width
  closed a drum staff's bar well before the staff above it (the corpus's
  last misaligned system).
- A voice moved aside in a shared column clears every head of the chord
  beside it, including the head a second sets on the far side of the stem.
  Measured from the stem-side head only, the moved note stood on the
  far-side one, its stem through it (42 voice collisions in the corpus).
- Grace notes in a bar of several voices lead into the whole column. Drawn
  at the column, one voice's graces stood on the other voice's heads, their
  stems through them, and pushed their own note aside (195 voice collisions
  in the corpus, most of what remained). Graces in two voices stack, the
  lower voice's stems down; in three or more they stand one voice after
  another. On a shared system grid, graces in any bar stand before their
  note's accidentals: the grid read a grace head as the note's own, left no
  room for it, and the grace was drawn on the note or across the barline.
- MusicXML staff reading: a voice labelled 1-4 now claims its slot on the
  staff it visits. A piano's voice 1 crossing to the bass staff for a beat
  shared slot 0 with that staff's voice 5, the two interleaved in one list,
  and a triplet of each ended up nested in the other's span — layout threw
  "Tuplet spans overlap" on eight corpus Lieder. Voice 5 now takes the next
  free slot in such a bar.
- **Maxima.** `DurationBase.maxima` (eight whole notes). MusicXML read
  `<type>maxima</type>` as a breve (a quarter of its length) and LilyPond's
  `\maxima` and kern's `000` as a longa; all three now read it exactly, and
  MusicXML, LilyPond, MEI (`dur="maxima"`) and kern write it back. Layout
  draws the SMuFL `mensuralNoteheadMaximaWhite` head (stemless) and the
  `restMaxima` rest, and spaces it a step wider than the longa; playback
  holds it for eight wholes. MuseScore, which has no maxima, gets a longa
  rather than the old `quarter` fallback. MusicXML's non-standard `longa`
  type now reads as a longa instead of a breve.

## 0.10.0 (2026-10-17)

Stated beams, tighter vertical spacing, complete voltas, and the fixes found
by rendering real songs beside engraved editions.

- A beam over a barline under a second voice keeps voice 1's stems up, and
  otherwise follows the stem the source states: chosen by pitch alone, stated
  MusicXML beams over barlines sent stems through the other voice (166 more
  voice collisions in the corpus).
- **Tighter staff and system spacing.** Each pair of staves in a system now
  gets its own gap (`StaffSystemLayout.staffGaps`, `gapBelow`; `staffGap` is
  the widest), measured column by column from the new `ScoreLayout.inkProfile`
  rather than from each staff's extremes anywhere: a voice's lyrics no longer
  spread the piano's staves, and a low note in one bar no longer holds the
  staves apart for a high one three bars on. `layoutPages` and
  `layoutMultiPartPages` pack each page with `minSystemGap` (default 5)
  before justifying. On 59 Mutopia voice-and-piano songs: 203 pages → 139.
- LilyPond: `\skip <dur>` is read as a hidden spacer rest (`\skip 1*8` is
  eight bars), without changing the running duration. Its duration used to be
  lost, shifting later bars. In lyrics, `\skip` holds a note without a
  syllable, like `_`.
- **Stated beams.** MusicXML `<beam>` is read: a part that states any beam
  is beamed only where it says (new `Score.beamSpans`, `Score.beamsExplicit`,
  and `CrossMeasureBeam`s for a beam over a barline), so vocal lines keep
  their flagged eighths and 3+3+2 groupings stay 3+3+2. Parts without
  `<beam>` are still grouped by the meter. A group crossing to the other
  staff of a piano part is beamed per staff; a Dolet export that never
  closes its beams (`begin`/`continue` only) closes each at the next
  `begin`. The writer emits `<beam>` for such scores. System slices now keep
  their `crossMeasureBeams`, which every multi-system render used to drop.
- LilyPond: `q` (chord repetition) repeats the last chord's pitches with its
  own or the running duration (`<c e g>4 q8 q`); it was read as a stray word.
  Single notes in between don't reset it, as in LilyPond.
- LilyPond: a score-level `\transposition` inside `\midi { … }` (guitar
  duos: `\transposition c`) applies to every staff that has none of its own;
  the parts read an octave above LilyPond's MIDI. The parser now nests the
  `\midi`/`\layout` block under its command.
- New opt-in `test/lilypond_oracle_test.dart`: the Mutopia vs LilyPond-MIDI
  comparison on its own (needs `CRISP_NOTATION_CORPUS` and
  `ly-oracle/oracle.json`), with a per-file report via `CRISP_LY_REPORT`.
- MuseScore: endings written as MuseScore 3's `<Spanner type="Volta">` are
  read — every bar the spanner's `<next><location><measures>` covers gets
  the ending, with its passes (`<endings>1, 2</endings>`), its `<text>` or
  `<beginText>` label and an open end when `<endHookType>` is 0 or absent.
  MuseScore keeps them on the top staff; every staff now takes them from
  there. Only the Measure-level `<Volta>` of this package's own writer was
  read before; the writer now also records passes, label and open end.
- An ending that crosses a system break is one bracket in two parts: the
  first system's part has no closing hook, and the next system continues
  with a plain line from its left edge instead of restating the number and
  the left hook. New `Measure.voltaContinued`, set by system layout.
- A discontinued ending (MusicXML `<ending type="discontinue">`, the usual
  last ending) is drawn open, without the closing hook it used to get. New
  `Measure.voltaOpenEnd`; the MusicXML writer emits `discontinue` for it.
- An ending taken on several passes keeps them all: new `Measure.voltaNumbers`
  (with `voltaPasses`) and `Measure.voltaText` (a printed label such as
  "1.-3."; `voltaLabel` gives what is drawn). MusicXML reads and writes
  `<ending number="1, 2">` and its text content, the bracket prints
  "1., 2." or the text instead of just "1", and playback takes the ending on
  every listed pass (repeating the body as often as the endings need).
  Ending text that only restates the numbers ("1.") is not kept as a label.
- A word broken across a system break keeps its hyphen after the last
  syllable on the line ("Voy-" | "ant"); the dash was drawn only between
  two syllables of the same system.
- A dynamic clears all the ink already under it — another voice's notes
  and stems, a tuplet bracket below them — not only its own note: the "p"
  of an upper-voice chord was struck through by a lower-voice triplet
  bracket.
- PDF and SVG print a line-broken instrument name (MuseScore's
  `<part-name>Singstimme⏎Voice</part-name>`) as stacked lines, not one line
  with a missing-glyph box; the CLI sizes the name column by the widest line.
- MusicXML: an `<ending>` covers every bar up to its `stop`/`discontinue`
  (or a `:|`), not just the bar that opens it — a two-bar first ending's
  second bar no longer plays on both passes. The writer opens a multi-bar
  ending once and closes it with a `stop`. New `Measure.voltaContinuesInto`.
- An ending that spans several bars draws one volta bracket — number and
  left hook over its first bar, right hook over its last — instead of a
  numbered bracket over every bar.
- Two voices on one staff that each sing their own words (MusicXML 42a, both
  numbered verse 1) lay out as two lyric lines — voice 1's first, voice 2's
  below — instead of one merged line. A verse splits by voice only where two
  voices sing it in the same bar, and the lines are not given verse numbers.
- LilyPond: the argument of an `\incipit` music function (Mutopia's
  mensural-incipit idiom) is the staff's name, not music of the part. It was
  read as notes in front of the piece, so voices whose incipits differed in
  length came back with different bar counts and multi-part layout threw
  "all parts must have the same measure count".
- Verses whose first syllable already carries its number ("1. Gdy-") are
  not numbered a second time.
- **PDF text font embedding.** `scoreLayoutToPdf`, `pagedLayoutToPdf`,
  `scoreLinesToPdf` and `multiPartPagesToPdf` take an optional `textFont`
  (`PdfTextFont`: the regular face's file, optionally bold/italic/bold-italic
  ones, falling back to the regular). It is embedded whole (no subsetting) as
  a Type0 font — CIDFontType2 + `FontFile2` for TrueType, CIDFontType0 +
  `FontFile3 /OpenType` for CFF — with text written as Identity-H glyph ids,
  a `/W` array for the glyphs used and a `/ToUnicode` CMap, so lyrics and
  titles print past Latin-1 (no more `?`) and copy/search as Unicode. Lay out
  with `PdfTextFont.textWidth` so text is spaced and anchored for the font.
  Without `textFont` the output is byte-identical (Times).
- **MEI reads and writes cross-staff chords.** A `<chord>` (or lone `<note>`)
  whose note(s) carry `@staff` pointing at the neighbouring staff splits into
  its home half and a synthetic half on that staff, linked as a
  `StaffSystem.crossStaffChords` entry — matching real encodings in the MEI
  sample corpus (e.g. `attribute_copyof.mei`, `Brahms_WieMelodienZiehtEsMir.mei`).
  A chord with nothing left on the home staff just moves wholesale (no link).
  `multiPartToMei` writes a chord link back the same way: the lower half's
  notes join the upper half's `<chord>` with `@staff`, and its own spot
  becomes a `<space>`.
- **MuseScore reads and writes cross-staff chords.** `<staffMove>` on a
  `<Chord>`/`<Rest>` (MuseScore always moves a whole chord, never splits one
  note-by-note, unlike MEI) relocates it to the target staff; when that lands
  at the onset of another chord already in a different voice of the SAME
  home measure, the two become one `StaffSystem.crossStaffChords` link — the
  real-world idiom for a piano chord reaching across the staff gap on one
  stem. `multiPartToMscx` writes a link the same way, and now writes a
  braced pair of staves of one instrument (or a pair joined only by a
  cross-staff chord) as one `<Part>` with two `<Staff>`s, mirroring the
  MusicXML writer's own rule, instead of two separate parts.
- **`textWidthFromFont`** (`lib/src/layout/font_metrics.dart`) reads a real
  TrueType or OpenType/CFF font's own `head`/`hhea`/`hmtx`/`cmap` tables and
  returns a `LayoutSettings.textWidth` closure measuring in it — for an SVG
  that embeds a specific text font rather than leaving width to the wide
  generic estimate (kerning ignored). `FontMetrics` also exposes the font's
  family name (`name` table), for embedding it.
- **SVG text font embedding.** `scoreToSvg` and the other SVG writers take
  an optional `embeddedTextFont` (`EmbeddedTextFont`: a `data:` URI and
  family name), emitted as a second `@font-face` and put first in the text
  font stack — the lyrics/markings counterpart of the existing engraving-font
  `fontFaceDataUri`. Output is unchanged when it is not passed.
- **`timesTextWidth`** measures text in Times-Roman, the face the PDF writer
  prints; pass it as `LayoutSettings.textWidth` for PDF output and lyrics
  are spaced for the font drawn (a Debussy song: 18 systems → 13).
- **Optical spacing in systems.** The shared columns of a grand staff or a
  multi-part system take the stem-direction correction too, when every
  staff showing one stem direction at both columns agrees.
- **A voice read out of time order keeps its onsets.** The MusicXML reader
  places a note that starts inside a gap of its voice into that gap, not
  after it, so a cross-staff chord's lower half always moves to its upper
  half and keeps its link on a round trip, even after earlier notes on its
  staff.

## 0.9.0 (2026-10-17)

- **Optical spacing at beam edges.** A beamed group's stems count where the
  beam ends or begins, so the gap from a stems-up beam to a down-stemmed
  note opens like any up-then-down pair (inside a beam nothing changes).
- **A piano is one MusicXML part again.** `multiPartToMusicXml` writes a
  braced run of staves of one instrument (a piano, an organ with pedal; or
  a pair a chord crosses) as a single part with `<staves>n</staves>` — `<backup>`, `<staff>` on every
  note and direction, the lower staff's voices numbered from 5 — so other
  programs read one piano, and a cross-staff chord round-trips as chord
  tones on staff 2 (where it cannot move ahead of its staff's own music, it
  keeps its timing and loses the link). A new live check round-trips every
  multi-part score: none of 1,746 changes its timing.
- **Multi-part MusicXML round trips keep their timing.** Lower voices'
  tuplets wrote unscaled durations, and a bar rest in a bar of its own length
  (a 4-quarter bar rest in 12/8) wrote as a plain whole rest; 23 of 25
  corpus scores that drifted on a round trip now come back exact.
- **White mensural notation.** `layoutMensural` / `layoutMensuralLines`
  engrave an MEI mensural voice as printed c. 1450–1600: no barlines, the
  C/F/G mensural clefs, mensuration signs (O, C, with dot and stroke),
  maxima to fusa with dots and accidentals, rests and custodes.
- **Cross-staff chords on one stem.** `GrandStaff.crossStaffChords`
  (`CrossStaffChord(upperId, lowerId, stemsDown:)`) joins a chord's halves
  on the two staves with a single stem through the gap; the half at the
  stem's tip carries the flag. `grandStaffFromMusicXml` finds them: a
  `<chord/>` whose notes sit on both staves of a part. Multi-part scores
  too: `StaffSystem` and `MultiPartScore` carry `crossStaffChords`, drawn
  where both halves sit on neighbouring staves, and `staffSystemFromMusicXml`
  finds them in every multi-staff part.
- **Mensural ligatures and black notation.** `<ligature>` draws joined as
  printed — square heads edge to edge with connecting lines, and
  `form="obliqua"` (or `lig="obliqua"`) as oblique shapes — and
  `colored="true"` or `notationtype="mensural.black"` takes the black heads.

## 0.8.0 (2026-10-17)

- **Optical spacing.** Between unbeamed stemmed notes, an up-stem followed
  by a down-stem gets a little more room and a down-stem followed by an
  up-stem a little less (Gould), so the gaps look even rather than measure
  even. SVG goldens updated.
- **House style sheets.** `LayoutSettings.fromStyle(json)` reads a style
  sheet — a preset (`base`: default, engraved, spacious) with any setting
  overridden by name — and `toStyle()` writes one; a typo or a value of the
  wrong kind is an error naming it.
- **Square (Gregorian) notation.** `layoutChant` and `layoutChantLines`
  engrave GABC on the four-line staff: do- and fa-clefs (with the b-flat
  signature), punctum, inclinatum, virga, quilisma, oriscus, strophicus,
  liquescent and cavum, pes stacked and clivis joined as printed, flats,
  naturals and sharps, mora dots, episemata, ledger lines, the four division
  bars and the sung syllables, never overlapping. Each note has an id and a
  hit region. `scoreLinesToSvg` and `scoreLinesToPdf` stack laid-out lines
  into one SVG or onto pages.
- **Scored slurs.** A slur is chosen from candidate shapes, as LilyPond
  does: each end lifted off its note by up to two spaces, the arc up to six
  spaces deeper, its control points following the line of the ends (an end
  may rise up to four spaces, to its stem or beam). Shapes
  that touch ink are ruled out; among the rest the ends stay near their
  notes, the arc stays shallow and the slur slopes with the notes. A slur
  over a rising scale now rises with it instead of arching flat over the top.
- **A note tied over the barline does not repeat its accidental** (Gould);
  a later note on the same step in that bar restates it, and an accidental
  the source states still prints. 188 corpus songs drew one too many.
- **Verovio symbol oracle** (`test/verovio_symbols_test.dart`, opt-in, built
  by `tool/verovio_oracle/make_symbols.py`): rests and accidentals per bar
  of the first staff against Verovio; 1,681 of 1,745 files agree.
- **`Score.withMultiRests()`** prints a part as a player reads it: each run
  of two or more silent bars becomes one multi-bar rest, broken before a
  clef, key, meter or tempo change, a repeat, volta or navigation mark, and
  never swallowing a rest that carries text or a dynamic.
- **Whole-bar rests fill the bar in any meter.** `<rest measure="yes"/>`
  reads as a whole rest (a typeless one in 9/8 read as a *long*, sixteen
  quarters, and pushed every later note of the part late), and the playback
  timeline gives a voice that is one whole rest the bar's length. A bar rest
  written shorter than the meter keeps that length (`actualDuration`); the
  MusicXML writer writes bar rests with the bar's duration.
- **`<type>` wins over a `<duration>` that cannot fill the bar.** When a
  one-voice bar's durations over- or underfill the meter and the written
  note types fill it exactly, the types are read (a half rest encoded as
  three quarters no longer shifts the rest of the song).
- **Styled text survives MEI and MuseScore.** `<dir><rend>` and
  `<StaffText><text><i>` were read as no text at all; they now read, with
  italic/bold (and MuseScore's italic Expression style and `below`
  placement), and both writers write the style. MusicXML no longer drops
  italic/bold from every annotation of a score with a multi-bar rest.
- **Verovio onset oracle** (`test/verovio_oracle_test.dart`, opt-in, built by
  `tool/verovio_oracle/make_oracle.py`): the first staff's note onsets
  against Verovio's timing map for 1,745 MusicXML files; 1,685 agree.
- **Vector PDF.** `pagedLayoutToPdf`, `multiPartPagesToPdf` and
  `scoreLayoutToPdf` write print-ready PDF in pure Dart: lines, beams and
  slurs as paths, every glyph from the embedded SMuFL font (OpenType/CFF, by
  glyph id), the title block and copyright on the first page, and for
  multi-part scores the brackets, braces, joined barlines, instrument names
  and system bar numbers. Text uses the standard Times faces (Latin-1).
- **Room for the title on page one.** `layoutPages` and
  `layoutMultiPartPages` take `firstPageTop`; `titleBlockHeight(metadata)`
  says how much the title block needs. The SVG and PDF writers share one
  title-block layout.
- **No widowed last system.** Paged layouts (single staff and multi-part)
  move a system over when the last page would hold one alone and the page
  before can spare it.
- **Beam quanting.** Inside the staff a beam sits on a line, straddles it or
  hangs from it — never floats mid-space with white wedges against the lines
  (Gould); each end moves away from the heads, so stems only lengthen.
- **A displaced voice clears ledger lines** too, its own and the other's.
- **Shared rests.** Voices resting alike at the same moment draw one rest in
  place, not one above and one below.
- **A displaced voice moves a notehead's width**, heads nearly touching; it
  moved a whole-note head and more, and read as falling between beats.
- **Real text metrics.** `LayoutSettings.textWidth`: a renderer with the real
  font measures lyrics and annotations; without one the layout estimates.
- **Verse numbers.** A song with two verses or more prints "1.", "2." before
  each verse's first syllable, on the line where the lyrics begin.
- **House styles.** `LayoutSettings.engraved` (print density) and
  `LayoutSettings.spacious` (young readers, touch); the default sits between.
- **Voices with stems the same way move apart**, as a source may state them —
  one stem ran through the other voice's heads.
- **Stem directions the source states are kept.** `NoteElement.stemsDown`
  (null: the engraver decides): read and written in MusicXML (`<stem>`), MEI
  (`@stem.dir`), MuseScore (`<StemDirection>`) and kern (`/`, `\`); the
  layout honours it, a beam group following its first stated stem.
- **Line breaks are chosen for the whole piece.** Wrapped scores (single
  staff, grand staff, staff systems) no longer fill each line greedily and
  leave the leftovers to the next: the breaks minimise how underfull the lines
  are, a last line of one bar is discouraged, and a source's own line breaks
  are kept unless the lines around them come out badly.
- **The title block.** `ScoreMetadata.subtitle` and `.arranger`: a song
  within a cycle reads the cycle as title and the song as subtitle (MusicXML
  `<work-title>` + `<movement-title>`), and `<creator type="arranger">` is
  kept; all round-trip. SVG prints title, subtitle, the lyricist on the left,
  composer and arranger on the right, and the copyright as a footer — as
  LilyPond and Verovio head a song.
- **Lyrics and text take the room they need, not more.** The layout has no
  font metrics; it estimated every character at 0.62 em, so narrow letters
  were over-reserved and lyrics set a song two bars a line. A per-character
  estimate (as wide as DejaVu Sans, so no common font collides) gives a
  Debussy song 12 lines instead of 14 (LilyPond: about 10), and a row of
  chord symbols that would run off the line's end is pulled back inside it.
  `estimateTextHalfWidth` is public for apps placing text beside a layout.
- **Text keeps its style.** `Annotation.italic`/`.bold` and
  `TextPrimitive.italic`/`.bold`: MusicXML `<words font-style="italic">`
  (*dolce*) and `font-weight="bold"` are read, drawn (SVG and Flutter) and
  written back; tempo words printed with a metronome mark are bold.

## 0.7.2 (2026-10-16)

Found by rendering real scores beside LilyPond and Verovio and reading the
differences:

- **Hidden rests (spacers).** `RestElement.hidden`: a rest that takes its time
  and space but prints nothing. MusicXML `<forward>` was ignored, so in 60% of
  real MusicXML files a voice's notes after one were read too early — a bass
  note on beat 3 landed on beat 1, on the page and in playback. The reader now
  keeps a time cursor (`<duration>`/`<backup>`/`<forward>`) and fills each
  voice's gaps with spacers; `print-object="no"` rests are kept as spacers,
  hidden notes give their time to the next note. LilyPond `s`, ABC `x`, MEI
  `<space>`, kern `ryy` and MuseScore invisible rests read and write as
  spacers (LilyPond spacers printed as rests).
- **Staves close their bars together.** An inner voice's tuplet was counted
  at face value when aligning a system's staves, and a multi-voice staff
  closed its bar at its own last note: a song's three staves had their
  barlines at three different places. The live corpus now checks every
  system's staves for it.
- **A chord across the piano staves keeps both halves.** Its tones on the
  other staff were merged into the previous note; each staff now gets its half
  at the chord's time.
- **A playback-only tempo prints nothing.** `Tempo.printed`: a MusicXML
  `<sound tempo>` with no `<metronome>` times playback but draws no "♩ = 45.5".
- **Barlines join a piano's staves, not the voice above it,** as MusicXML
  defines part groups. SVG output draws braces and brackets, the system's
  opening line, and a grand staff's brace and joined barlines.
- **Two voices no longer run into each other** (28,249 noteheads crossed by
  another voice's stem in the corpus, now 2,398): the upper voice takes stems up
  whatever its slot (a piano's left hand often reads its lower voice first);
  a note inside the other voice's chord, or crossing below it, moves aside
  like a second; and a moved head is measured from the heads already placed,
  so unisons of different lengths no longer overlap.
- **Staves stay aligned bar by bar** (10,213 drifting barlines in the corpus,
  now 111): on the shared grid a chord's accidentals hang left of its column
  (they pushed the heads right), a multi-voice staff ends its bar on the
  shared closing column rather than its own spacing, and a clef, key or time
  change on one staff — at a bar's start or inside it — gets room on every
  staff instead of pushing that staff's notes and barline right.
- **A whole-bar rest is a centred whole rest** in every meter (a silent 3/4
  bar drew a dotted half rest at its start).
- **A pickup is beamed from where it falls in the meter** (PLAN.md known bug
  1); MusicXML pickups record their length.
- **A lyric on a rest or an unknown note is reported** as such rather than as
  an index overrun.

## 0.7.1 (2026-10-13)

- **A piece that ends on a repeat ends with the repeat barline (#19).** When
  the last measure has an end repeat, the end-of-piece thin+thick barline was
  also drawn after it, so the closing barline appeared twice. The repeat
  barline (dots, thin, thick) now closes the staff on its own.

Found by a new layout lint (engraving rules checked on every layout, see
`CONTRIBUTING.md`), run over the real-score corpus plus the LilyPond MusicXML
test suite and the W3C MusicXML examples:

- **The staff stops at an explicit closing barline.** A last bar with its own
  style (MusicXML `light-heavy`, as MuseScore writes on every score; a double
  bar) left a staff space of bare staff after it, in ~90% of real MusicXML
  files. A wrapped line ending on such a barline is justified to the margin.
- **A start repeat replaces the barline before it.** It was drawn after a
  plain barline, reading as `| ‖:` (1,071 bars in the corpus).
- **Empty bars keep a bar's width.** A bar with nothing in it (a hidden
  whole-bar rest, `print-object="no"`) had none, and its barlines stacked into
  one smear.
- **Accidentals in a two-voice column are drawn once.** An accidental the file
  states (`<accidental>`) was drawn by the column and again by its note.
- **Theoretical keys (8+ sharps or flats) read and draw** as their double
  sharps/flats (`KeySignature.fromFifths`); MusicXML `fifths` beyond ±7 crashed
  layout.
- **A stem-down second clears what precedes it.** Its left head was not
  reserved and touched the time signature or barline before it.
- **Each head of a dotted second gets its own dot.** Both dots landed in one
  space.
- **Justified lines keep a straight right margin.** A line the widest
  spacing cannot spread to the margin (a lone whole note) is padded the rest
  of the way, now in single-staff and grand-staff wrapping too, and its last
  bar runs on to the moved barline (the padding belonged to no bar, so a tap
  there hit nothing).
- **Justified lines keep their note names.** The stretched re-render dropped
  `showNoteNames`, so every line but the last lost them.
- **A chord or hairpin stated twice draws once.** A chord naming one pitch
  twice (a merged unison, a cross-staff chord read with its notes repeated)
  drew every head, dot, ledger line and tie twice; the model keeps both. A
  unison of two spellings (B and B♭) sets its heads side by side instead of
  one over the other.
- **Tab staves draw barline styles and repeats** (shared with the notation
  staff through one `BarlinePen`), close with the notation staff's closing
  barline, and no longer run on past it.

## 0.7.0 (2026-10-06)

Fixes for GitHub issues #8–#14, all found in one real score (Dvořák 9,
first movement). Output changes: a slur over mixed stems now goes above;
dynamics and touching hairpins share one line; metronome marks are drawn;
multi-measure rests from MusicXML count their bars once;
tuplet brackets sit outside the staff.

Also in this release, contributed by @elasticdog:
- **Staff-relative fingerings (PR #16).** `LayoutSettings.fingeringPlacement`
  takes `aboveNote` (the default, as before), `aboveStaff`, `belowStaff` or
  `outsideStaff`. `outsideStaff` puts fingerings below a bass-clef staff and
  above the others, the piano convention. Fingerings clear nearby notation and
  stack outward. A sloped beam's ink now follows its slope, so marks placed
  over it follow the beam.
- **Wrapped layouts take `spacingStretch` and `drawTimeSignature` (PR #17)**:
  `layoutMultiSystem` and `layoutGrandStaffSystems`. The last system keeps the
  stretched spacing, and the first system can leave the meter off.
- **Staff-to-staff system distance (PR #18).** An optional `systemDistance`
  sets wrapped systems a fixed distance apart, from one system's bottom staff
  line to the next system's top line, opening up only where ink would come
  closer than `systemGap`. Without it, systems stack as before.

- **#10 — no more crash on staccatissimo, or on quarter-tone accidentals.**
  The SMuFL codepoint table was a hand-kept subset. It lacked
  `articStaccatissimoAbove`/`Below` and the four Stein–Zimmermann
  accidentals, so painting one asserted in every debug build, and two of its
  entries (`dynamicSforzatoFF`, `dynamicRinforzando1`) pointed at the wrong
  glyph. It is now generated from the SMuFL glyph list, so every SMuFL name
  resolves. The Flutter painter skips an unknown name with a warning instead
  of throwing.
- **#11 — text on a multi-measure rest lays out.** "Adagio" over a part's
  opening eight bars' rest crashed layout (`unknown element id`). The
  multi-rest bar now keeps its rest as an anchor for marks, drawn as the
  H-bar. Separately, MusicXML keeps every bar a `<multiple-rest>` covers, and
  the reader kept those bars beside the multi-rest, counting the silence twice
  (playback ran long, bar numbers drifted). A single part now folds the
  covered bars into the multi-rest, and a staff of a system keeps them as
  plain bars. The writer emits the covered bars, as MusicXML requires.
- **#12 — metronome marks are drawn**: "♪ = 63" over the first bar and over
  each tempo change, joined with the tempo words at the same spot ("Adagio
  ♪ = 63"). Only the first system and a system's top staff carry them, and a
  mark on the last bar of a line ends inside the line.
  `LayoutSettings.drawTempoMarks` turns them off.
- **#13 — an extracted part keeps the score-wide tempo.**
  `scoreFromMusicXml(partIndex: n)` inherits the top part's opening tempo,
  tempo changes and tempo words, matched by bar number. Exporters write these
  only once, in the top part. Opt out with `inheritGlobalDirections: false`.
- **#8 — slur placement.**
  - `Slur.placement` (`SlurPlacement.auto`/`above`/`below`) is read from
    MusicXML `placement`, then `orientation`, then the sign of `bezier-y`
    (MuseScore writes only that). It is written back to MusicXML, and
    round-trips through MEI as `@curvedir`.
  - In `auto`, a slur over mixed stem directions goes above. The old rule
    asked which note's ink was highest, so an up-stem's top put the slur
    under the staff, far from the notes.
- **#9 — dynamics and touching hairpins share one line**, set by the lowest
  ink across the run, with each hairpin stopping short of the dynamics at its
  ends. A cresc. over stems-up notes and the dim. after it over stems-down
  notes sat at different heights.
- **#14** (item 3) **— a chord's tremolo strokes sit on its free stem**, past
  the outermost notehead on the stem side, instead of over its own noteheads.
  (Item 5) **A slur written several times over the same notes is one slur.**
  The export stacked identical copies under numbers 1–4, and each drew as
  another arc. The reader and the layout both drop the copies. Items 1, 2 and
  4 (slurs pushed under text and hairpins, crossing nested slurs) were already
  fixed in 0.6.0.
- **Tuplet numbers clear the beam and the staff.** The bracket sat 0.7 spaces
  past the stem tips. The beam was not counted, and the digit is centred on
  the line, so a stems-down triplet's "3" sat on the beam and the staff lines
  (Violini I, bars 255–256). The line now clears all ink, beams included, by
  half a digit plus a gap, and stays outside the staff. A live check covers
  all 11,743 tuplet digits in the corpus.

## 0.6.0 (2026-10-06)

New: linked parts, ossia and divisi staves, physical (millimetre) sizes,
slanted multi-level cross-staff beams, and a LilyPond reader checked against
LilyPond itself. Everything is additive except where behaviour was wrong, but
several outputs change:
- LilyPond imports, often substantially: pitches, voices and repeats now
  match LilyPond;
- MusicXML output gains an `<encoding>` block;
- cross-staff beams slant;
- hide-empty now counts notes in voices 2–4;
- `MultiPartScore` and `StaffSystem` equality include the new
  partial-staff sets.

Pin `<0.6.0` if you need the old behaviour.

### New

- **Linked parts** (`MultiPartScore.linkedPart` / `withLinkedPart`): edit one
  part on its own, written or at concert pitch, and the edit's score-wide
  structure reaches every other part. That covers inserted and deleted bars,
  meter, tempo, repeats, voltas, navigation, barlines, pickups and irregular
  bar lengths, and key changes in each instrument's own written key. Notes,
  clefs and marks stay with their part. New building blocks:
  `KeySignature.transposedBy` and `Score.atWrittenPitch` (the inverse of
  `atConcertPitch`).
- **Ossia and divisi staves** (`withOssia`, `withDivisi`): partial staves
  (`MultiPartScore.partialParts`, `StaffSystem.partialStaves`) drawn only over
  the bars where they have notes, and only on systems where they have any. An
  ossia opens with its clef and key; a divisi staff takes a part's second
  voice, with its slurs, dynamics and hairpins. They stay aligned with their
  staff, stay out of systemic barlines, and round-trip through MusicXML as
  `<staff-type>ossia</staff-type>`. Hide-empty now also counts notes in
  voices 2–4.
- **Cross-staff beams slant and stack.** A beam joining both staves follows
  the figure's contour (half of it, at most one space), sits between the two
  staves' noteheads, and draws every level the durations ask for: 16th and
  shorter beams stack toward the upper staff, with beamlets for lone short
  notes, and each stem runs to the farthest beam its note needs. A group may
  run across a barline. Mac PNG golden 94 needs regenerating.
- **Opt-in per-level beam subdivision:** `LayoutSettings.subdivideBeamsPerLevel`
  breaks 32nd beams at each eighth and 64ths at each sixteenth. The default
  keeps every level continuous within a beat.
- **`StaffSystemSystem.partIndexOf`**: a wrapped system that hides parts
  (hide-empty, partial staves) says which document part each staff shows.
- **Physical sizes:** `Spatium` (one staff space in millimetres, with the
  traditional rastral sizes 0–8), `PaperSize` (A3/A4/A5/B4, Letter, Legal,
  Tabloid, concert), `pageMetricsFor(paper, spatium)` for page layout on real
  paper, `Spatium.pixelsPerSpace(dpi)` for true-size rendering, and
  `physicalSize:` on the SVG exporters to size documents in millimetres.
- **Fix: `Score.transposedBy` (and so `atConcertPitch`) keeps every bar
  field.** It silently dropped mid-score tempo changes, inline clefs, measure-repeat signs
  and irregular bar lengths.
- **MusicXML output identifies itself** with `<encoding><software>crisp_notation</software>`,
  so a file this library wrote can be told from a third-party export.

### Layout and codecs, from the widened corpus sweep

Found by the live corpus sweep, now 4,700 real files in six formats (MusicXML,
LilyPond, kern, MuseScore, MEI and ABC), and its new curve-geometry and
mark-fidelity checks.

- **Slurs hug their notes.** A slur no longer dives under a hairpin (dynamics
  are now laid out after slurs and clear them), no longer arches over a
  barline it crosses, keeps to the upper side when the other voice only rests,
  and nested slurs are laid out inner-first so an outer slur goes around them.
  Curves register their real shape as ink, not their control polygon.
- **Ties land on their notehead** across a clef change (head to head), and in
  crossing voices a tie flips rather than run through the other voice's head.
- **Dynamics and hairpins on rests are drawn.** LilyPond writes a Dynamics
  line as spacer rests, and those marks were silently never drawn. The
  MusicXML reader anchors text and dynamics on rests too, and carries a
  dynamic that ends a bar into the next bar instead of dropping it.
- **MusicXML slur numbering.** The writer kept one slur start and one stop per
  note and numbered slurs by list position (`i % 6 + 1`), so a shared endpoint
  lost a slur and overlapping slurs could collide (~300 corpus files lost
  slurs on a round trip). Numbers are now allocated in output order (1–16) and
  a chained slur writes its stop first. The reader now also tracks slur
  numbers on chord tones, grace notes and skipped (hidden or other-staff)
  notes. Before, a stop it skipped left its start open to mis-pair with a
  later stop.
- **MEI:** a tuplet encoded twice (`<tuplet>` AND `<tupletSpan>`) is read
  once. The duplicate overlapped and failed layout (Schubert's "Lindenbaum").
- **Layout performance:** an O(ottavas × notes) scan in the ottava pass is
  gone, and the benchmark's linearity gates compare 3,200 against 800 bars,
  past the memory knee that made the old 800-vs-200 ratio noisy.

### LilyPond reader, checked against LilyPond itself

A new oracle compiles each of 442 Mutopia files to MIDI with the real LilyPond
and compares the reader's notes, pitches and length against it. Files that
agree went from 13 to 123 of 374. The rest are mostly the oracle's own
artefacts (a MIDI-only `\score` that transposes, ChordNames tracks). The
live corpus test now holds that floor. What it found:

- **`\relative` through `<< >>` follows text order**, as LilyPond does: each
  voice starts from where the previous one ended, and the music after `>>`
  continues from the last voice. Before, every voice restarted from the `<<`,
  so inner voices and the bar after a split could land an octave off.
- **`\transpose` is applied** (it read at written pitch), to keys and chord
  names too, and also when it wraps the whole score. **`\transposition`** sets
  `Score.transposition` instead of reading its pitch as a stray note, and the
  writer emits it.
- **Simultaneous music is simultaneous.** `\partcombine`, plain `<< { … } { … } >>`
  and `\new Voice` contexts are read as parallel voices. A note-less `\global`
  of spacer rests, or a `\new Voice \global`, keeps its key, meter and
  `\partial` but no longer pushes the music back. Every such SATB hymn or piano
  staff used to come back twice as long.
- **`\repeat volta` carries its repeat barlines**, and `\alternative` its volta
  brackets, so playback unfolds them. They were dropped from the model.
- **Score structure:** `\new Dynamics` lines attach their marks by onset to the
  staff above. Variables naming staves (`\upper`) are expanded, `\context` takes
  its arguments, a `Lyrics` context no longer swallows the next staff, and bare
  voices in a staff group are one staff each. A MIDI-only `\score` beside a
  layout score adds no parts, and `\parallelMusic` defines its variables.
  `scoreFromLilyPond` of a multi-staff file returns its first staff instead of
  every staff run end to end.
- **Lexing and spelling:** a Scheme list (`#(define-music-function …)`) is one
  token, identifiers may contain `_` (`guitar_staff`), `R` and `s` rests keep
  time (`R1*4` spans four bars), solfège note names (italiano, français,
  español, …) and Swedish `-iss`/`-ess` spellings are read, and `\relative`,
  `\new` and `\context` accept a command body.

## 0.5.0 (2026-10-05)

**Breaking:** `DurationBase` gained `long`, `oneHundredTwentyEighth`,
`twoHundredFiftySixth`, `fiveHundredTwelfth` and `oneThousandTwentyFourth`
(corrected after publishing: the 0.5.0 notes on pub.dev wrongly list `breve`,
which already existed, and omit `oneThousandTwentyFourth`). An exhaustive `switch` over
`DurationBase` in your code needs the new cases. Everything else in this release
is additive or a fix. Note that several fixes change output: layout geometry
(ties, slurs, beams, ottavas), playback order (lone end repeats), and what the
readers import (split MusicXML directions, text on rests). Pin `<0.5.0` if you
need the old behaviour.

This release also ships the changes listed under 0.4.6–0.4.8 below. Those were
prepared but never published to pub.dev, so 0.4.5 → 0.5.0 includes them all.

### GitHub issues #1, #2, #4 and PR #3

- **MusicXML: every `<direction-type>` is read, not just the first (#4).** A
  `<direction>` that split tempo text and its `<metronome>` (or a wedge, dynamic,
  pedal, ottava, segno/coda) across sibling `<direction-type>` blocks lost
  whichever came second. 612 of 1,686 real files in the CometBeat corpus carry
  such directions. A dangling `(` left by `Andante (` ♩=63 `)` is trimmed.
- **Playback: an end repeat with no start repeat repeats its section (#1).** A
  lone `:|` — the usual way to engrave an opening repeat — now replays from the
  end of the previous repeated section, or the top. A finished volta repeat no
  longer leaks its pass number into a later section's voltas.
- **Layout: ties and slurs keep to their voice; chord ties split (#2).** In a
  multi-voice passage ties and slurs sit on their voice's stem side and a slur
  clears only its own voice's notes (an upper-voice slur used to dive under the
  lower voice). A chord's ties now split — upper notes up, lower notes down —
  instead of all curving one way into the neighbouring noteheads.
- **Beams reach the outer stem edges (#3, thanks @elasticdog).** Beam ends extend
  by half a stem thickness along the slope; a beamlet stub extends at its stem
  end only.
- **A mid-score key change no longer crashes layout in table-less clefs.**
  Cancellation naturals indexed the hand-tuned position tables with `!`, so a
  key change in French-violin, soprano, mezzo-soprano, baritone, sub-bass or
  percussion clef threw. Found by the corpus sweep on two real string quartets.
- **Text on a rest lays out instead of throwing.** An annotation or chord
  symbol anchored on a rest ("Fine", "N.C.", tempo words) threw
  `ArgumentError`, so one such mark made the whole score unrenderable — 62 of
  442 Mutopia LilyPond files and 4 of 1,036 NIFC kern files. It is now drawn
  over the rest; only an id naming no element still throws.
- **Several text marks per note survive.** The MusicXML reader joins every
  `<words>` run of a direction ("Allegro" + italic " con brio") and keeps every
  direction before a note, each with its own placement (it kept the first text
  but the LAST placement). The MusicXML, LilyPond and MuseScore writers — and
  the MuseScore reader — kept one annotation per note; all keep every one now.
- **An ottava bracket clears its own span.** Each 8va/8vb sat at the height of
  the most extreme ottava-shifted note anywhere in the score, and the pass cost
  O(ottavas × notes).
- **Layout performance.** Skyline (ink-clearance) queries and the new per-voice
  test are indexed instead of scanning the whole score per mark/curve: a
  two-voice, tie-and-slur-heavy 800-bar score lays out ~25× faster (2.06 s →
  ~0.08 s AOT).
- **Live tests.** `crisp_notation_cli`'s live suite covers each fix through the
  compiled binary; `test/live_corpus_test.dart` sweeps a local corpus of real
  `.mxl` files when `CRISP_NOTATION_CORPUS` is set; the layout benchmark gains a
  linearity gate for the tie/slur passes in two-voice scores.

### GPIF (`.gp`) round-trip fidelity

The GPIF export/import is now a high-fidelity tablature round-trip. On top of the
pitches, chords, rhythm, per-track tunings and tab techniques it already carried,
these now survive a `scoreToGpif`/`scoreFromGpif` (or `multiPartToGpif`) round-trip
— each symmetric writer+reader with a test, and each emitted only when present so a
plain single-voice C-major score stays byte-identical:

- **Voice 2** — a bar's second voice writes as a second GPIF `<Voice>` and reads
  back into `Measure.voice2` (was collapsed to one voice).
- **Tuplets** — `<PrimaryTuplet>` per beat, regrouped on import. Previously a
  triplet's notes were read at full value, so an eighth-triplet + half bar came
  back 3.5 beats instead of 3.0 (silent timing corruption).
- **Key signature** — `<Key><AccidentalCount>` incl. mid-score changes.
- **Dynamics** — `<Dynamic>` over PPP…FFF.
- **Grace notes** — `BeforeBeat` grace beats (order preserved, not timed).
- **Articulations** — staccato / accent.
- **Lyrics** — track-level `<Lyrics>`, one `<Line>` per verse (syllables + hyphens).

### Robustness (fuzzed)

- **gp5 note reader misplaced the time-independent duration.** In GP5 a note's
  optional duration is an 8-byte double written *after* the fingering; the reader
  read it in the gp3/4 slot, so a note carrying that flag took its fret from the
  middle of the double and came back at a garbage octave (e.g. `effects.gp5`
  decoded notes at MIDI 122/108 where gp4 read 78). Fixed; gp5 now decodes
  byte-identical pitches to gp4.
- **Malformed time signatures crashed instead of rejecting.** A garbage
  denominator (not a power of two) tripped an uncatchable `_AssertionError`, and a
  GPIF `<Time>` without `/` raised a `RangeError`. Both the binary reader and the
  GPIF `_parseTime` now validate and throw a `FormatException`. Found by
  [covfuzz](https://pub.dev/packages/covfuzz) (blind + coverage-guided), each fix
  proven load-bearing with `covfuzz_mutverify`.

### Importer fixes (real-world sheets)

- **LilyPond: `\key`, `\partial` and chord tracks.** `scoreFromLilyPond`
  mis-read the common "chord track + melody + lyrics" sheet layout (e.g. the
  Ebersberger Liedersammlung): the `\key` was dropped (key came out C major), the
  `\new ChordNames { \chordmode … }` track was counted as melody notes (inflating
  the note stream), and the `\partial` pickup was ignored (wrong first-bar
  timing). The parser now consumes `\chordmode`/`\chords`/`\figuremode`/
  `\drummode` as wrapper arguments; the reader honours `\key` (circle-of-fifths
  incl. minor), pre-loads a `\partial` anacrusis, and skips the chord/figure/drum
  blocks as non-melodic.
- **MuseScore 1.x files.** `scoreFromMscx` / `staffSystemFromMscx` threw
  "No `<Score>` in document" on MuseScore 1.x files, which hang
  `<Part>`/`<Staff>` directly off `<museScore>` with no `<Score>` wrapper and
  write the meter as `<nom1>`/`<den>`. Both are now handled (pitch/spelling
  already came from `<tpc>`); the 1.x custom `<KeySym>` key signature is left
  undecoded (key defaults to 0, accidentals still render inline).
- **Guitar Pro imports keep their fingering.** The GPIF and binary GP readers
  computed pitch from (string, fret) but discarded the string, leaving
  `Score.tabVoicings` empty — so an imported tab was silently re-arranged to the
  lowest position instead of keeping the played string. Each note now records a
  `TabVoicing`, so a note voiced on a non-default string survives a round-trip on
  that string.

## 0.4.8 (2026-07-18, not published; shipped in 0.5.0)

### Codec fixes (found by audit)

- **Braille: quarter- and half-note value signs were swapped** (and their 16×
  partners, 64th/32nd). Per the Music Braille Code a quarter adds dot 6 and a
  half adds dot 3; `_valueDots` had them reversed, so every exported quarter note
  read as a half (and vice versa) on a braille display/embosser — e.g. a quarter
  C emitted ⠝ (the half-C sign) instead of ⠹. The test that "pinned" it enshrined
  the swap (with self-contradictory glyph comments); corrected to the standard.
- **GPIF import dropped every mid-score time-signature change.**
  Only the first `<Time>` was captured, so a piece that changed meter reported
  the initial meter throughout. Each `<MasterBar>` whose meter differs from the
  running one now attaches a `timeChange` to its measure.

## 0.4.7 (2026-07-18, not published; shipped in 0.5.0)

### ABC round-trip fixes (found by audit)

- **Accidentals carry within a bar only to the same pitch in the same octave**
  (ABC 2.1 / abcm2ps / abcjs), not to every octave of the letter. Both the
  reader and writer keyed the running accidental by letter alone, so `^c c,`
  imported the lower `c,` as C♯ instead of natural — a semitone off when
  importing third-party ABC.
- **Sparse lyric lines stay on their own notes.** The writer joined only the
  present syllables positionally, so a lyric on notes 1 and 3 wrote `w:la la`,
  which the reader aligned to notes 1 **and 2**. It now emits one token per note
  (aligned by id), with `*` for an unsung note.
- **A final barline (`|]`) mid-piece keeps its style.** The writer only wrote
  `|]` on the last measure and a plain `|` elsewhere, losing a mid-piece
  section-ending barline on round-trip.

## 0.4.6 (2026-07-18, not published; shipped in 0.5.0)

### MusicXML round-trip fixes (found by audit)

- **Tuplets in voice 2/3/4 no longer corrupt the score on save/reopen.** The
  writer passed a measure's *entire* tuplet list to voice 1 (and `const []` to
  the other voices), so a triplet tagged for an inner voice was stamped onto
  voice 1's notes at the same indices while the real inner-voice notes were
  written with no `<time-modification>` — reading back with BOTH voices' rhythm
  wrong (voice 1 under-fills, the inner voice over-fills). Each voice now gets
  only its own spans via `Measure.tupletsForVoice`, and the inter-voice
  `<backup>` uses each voice's tuplet-adjusted duration.
- **A tempo change in a score with no initial tempo stays on its measure.** The
  reader treated the *first* `<metronome>` it saw as the score's initial tempo,
  so a change in bar 2 of a tempo-less score was relocated to bar 1 and lost as a
  change. A metronome is now the initial tempo only when it appears in the first
  measure; a later one is that measure's change.

## 0.4.5 (2026-07-17)

- **`SeventhChord` builder** — the four-note counterpart to `Triad`: voices any
  seventh-chord `ChordType` (dominant / major / minor / half-diminished /
  fully-diminished / minor-major / augmented) on a root, in inversions 0–3,
  spelled with real intervals so accidentals engrave correctly and
  `identifyChord` / `romanNumeralOf` round-trip it (`V7`, `ii7`, `viiø7`,
  `V6/5`, `vii°7`). Adds `Interval.diminishedSeventh` (9 semitones) for the
  fully-diminished chord's seventh.

### Interchange fixes (found by round-trip / support-matrix fuzzing)

- **Roman numerals** — a chord on the raised 6th/7th of a minor key (e.g. `vii°`
  in A minor) now round-trips exactly; it kept its bare symbol but
  `pitchClassesOf` had rebuilt it on the natural degree, a semitone off.
- **MusicXML** — inline (mid-measure) clef changes are now emitted on export, and
  a mid-score key/time change back to the *initial* signature reads correctly.
- **Multi-part MusicXML** — a fully-disconnected barline layout (every part its
  own barline) is now preserved instead of collapsing to one systemic barline.
- **MuseScore** — ornament variants (invertedTurn, accidental trills) no longer
  drop on export; a slur anchored to voice 2/3/4 is no longer dropped.
- **Humdrum kern** — tuplets survive multi-voice export; the inverted turn (`$`)
  now reads back (the writer emitted it but the reader ignored it).
- **MEI** — the inverted turn (`<turn form="lower">`) now reads back as
  `invertedTurn` rather than a plain turn.
- **ABC** — grace-note style (acciaccatura vs appoggiatura) and accidental bleed
  across a round-trip are fixed.
- **GPIF** — three silently-dropped tab techniques now round-trip:
  ghost notes, wide (whammy) vibrato, and multi-point bend contours.

### Robustness — importers never crash or hang on malformed input

  Every reader now rejects a corrupt document with a `FormatException` instead of
  leaking a `RangeError`/`StateError` or hanging, verified by a mutation fuzzer:

- **MIDI** — an out-of-range time-signature meta no longer spins the note-packing
  loop forever (a denial-of-service hang); it falls back to 4/4.
- **ZIP containers** (`.mscz` / `.gp` / `.mxl`) and **`.gpx`** (BCFZ/BCFS) — the
  byte parsers are bounds-checked; a truncated/corrupt archive rejects cleanly.
- **OMR semantic** — a bare `keySignature-` token no longer overruns a substring.

### Performance

- **Span/mark layout is now O(n)** (was O(n²)). Every span/mark pass (dynamics,
  hairpins, slurs, ottavas, pedals, glissandos, …) looked its endpoint notes up
  with a linear scan per span; a one-time id→index map makes it O(1). A score
  with a dynamic on every note lays out ~8× faster (800 bars: 141 ms → 17 ms),
  with byte-identical output.

_Internal: the layout engine was split into focused part-files, and the test
suite gained property-based round-trip, reader-robustness, exporter-crash-safety,
layout-geometry, and theory-algebra fuzzers to lock all of the above in._

## 0.4.4 (2026-07-16)

- **Note names under noteheads**: `NoteNameStyle` (`letter` — C D E F G A B;
  `german` — B-natural is **H** and B-flat is **B**; `solfege` — fixed-do
  do re mi fa sol la ti) plus `showNoteNames:` / `noteNameStyle:` on
  `LayoutEngine.layout(...)` and on the staff-system, multi-system, grand-staff
  and multi-part layout entry points. Off by default; a teaching aid for
  early readers. Additive — no signature breaks.

## 0.4.3 (2026-07-15)

- **Runnable example** (`example/crisp_notation_core_example.dart`): a tour of
  the theory model and the terse score DSL. Docs-only; no API changes.

## 0.4.2 (2026-07-15)

- **Configurable staff-line count** (N-line staves): `LayoutEngine.layout(...,
  staffLineCount:)` draws staves with any number of lines — 1 for a neutral
  percussion/rhythm line, 3, 6, or more for non-standard and pedagogical staves
  — instead of assuming a 5-line staff. Every vertical reference (staff lines,
  bounding box, stem direction, stem-length clamps, ledger lines, and beam
  slant clamps) derives from the line count. The default remains 5 lines and is
  byte-for-byte identical to previous output.

## 0.4.1 (2026-07-14)

- **Imported sheet titles**: MusicXML `<credit>` title/composer text is now used
  as metadata fallback when `<work>` / `<identification>` metadata is absent,
  matching common MuseScore/Verovio exports.

- **Multi-part MusicXML writer** (Workshop C11): `multiPartToMusicXml(MultiPartScore,
  {partNames})` serializes an N-part score as one `score-partwise` document that
  round-trips through `multiPartScoreFromMusicXml` — brackets become
  `<part-group>` `<group-symbol>` (brace/bracket), connected barline groups add
  `<group-barline>yes</group-barline>`, and each part keeps its `<transpose>`.

- **Explicit system / page breaks** (Phase 2.5): `layoutSystems(..., systemBreaks:)`
  forces a line break before given measure indices; `layoutPages(...,
  systemBreaks:, pageBreaks:)` forces a new page (a page break implies a system
  break). Width-driven breaking still applies elsewhere.

- **Braille mid-score signature changes** (Phase 7.5): `scoreToBraille` reprints
  the key/time signature at a measure with a `keyChange` / `timeChange`, and the
  running key drives accidental suppression from that point.

- **Measure-repeat (simile) signs** (Phase 2.7): `Measure.measureRepeat` (1, 2
  or 4) draws the SMuFL repeat-bar glyph centred in an otherwise-empty bar —
  repeating the previous 1/2/4 bar(s). Golden 126.

- **ABC lyric alignment skips rests** (hardening G8): the ABC reader no longer
  counts rests as syllable positions, so a `w:` line aligns to notes only. Real
  vocal round-trips (Mozart songs) previously attached syllables to rests, which
  shifted the rest onto later notes and crashed the lyric layout.

- **Braille signatures + chords** (Phase 7.5): `scoreToBraille` now emits a
  leading signature header (standard key signature, then time signature as
  number-sign + upper/lower digits) and renders chords as the top note plus
  downward interval signs (2nd-octave, compound via an octave mark).

- **ABC `!invertedturn!`** (Phase 7.3): the ABC reader maps the `!invertedturn!`
  decoration to `Ornament.invertedTurn` (rounding out the ornament set).

- **Metric-aware secondary beaming** (Phase 4.7 tail): secondary (16th+) beams
  now break at the meter's pulse rather than always the quarter — in compound
  (6/8, 9/8, 12/8) and additive (3+2/8) meters they break at the base unit, so a
  run of sixteenths inside a dotted-quarter beat groups at each eighth. Simple
  and cut-time meters are unchanged (no golden churn); golden 122 shows 6/8.
- **Every-N measure numbering** (Phase 2.7): `LayoutEngine.layout(...,
  measureNumberInterval:)` labels only bar 1 and every Nth counted bar (the
  common "every 5 bars" convention); 1 = every bar (unchanged default).

- **Forte set-class numbers** (Phase 4.5 tail): `forteNumber(pcs)` names a
  pitch-class set the familiar way — a minor triad → `3-11`, a dominant seventh
  → `4-27`, the major scale → `7-35`, with `Z` on Z-related classes. Trichords
  through pentachords come from the catalogue; septachords through decachords are
  derived from their complement (Forte's shared-ordinal convention). A
  completeness test over all 2¹² subsets verifies the catalogue is exactly
  complete with the canonical per-cardinality class counts. (Hexachords return
  null for now — the prime form stays the canonical identifier.)
- **Explicit irregular-bar length** (Phase 2.4): `Measure.actualDuration` (a
  `Fraction?`) overrides the meter's capacity for a mid-piece irregular bar
  (an inserted 5/4 in 4/4, a cadenza) without a meter change; `capacityGiven(meter)`
  resolves the effective capacity and pickup auto-detection leaves an
  explicitly-sized bar alone.

- **Enharmonic chord re-reads** (Phase 4.4 tail): `chordReadings(pcs, {bassPc})`
  returns *every* tonal reading of a pitch-class set — one per root whose
  template matches — surfacing the ambiguities a single spelled reading hides:
  `{0,4,7,9}` reads as both C6 and Am7; a diminished seventh reads four ways
  (C°7 = E♭°7 = G♭°7 = A°7), an augmented triad three. `bassPc` orders the
  readings and drives inversion. (Spelling-dependent augmented sixths stay with
  `identifyChord`.)

- **Accessible score labels** (Phase 3.9): `semanticLabel(element)` gives a
  spoken, screen-reader-friendly description of a note/rest — pitch names spelled
  out and the duration named (`"C sharp 4 quarter note"`, `"C 4, E 4, G 4 chord,
  half note"`, `"quarter rest"`); `semanticLabels(score)` maps every element id
  to one. Drives the new per-note `Semantics` on `StaffView` (Flutter side).
- **Braille music export** (Phase 7.5): `scoreToBraille(Score)` renders a
  single-staff score as Unicode braille-music cells — note signs (name + value),
  rests, accidentals (only when not implied by the key signature), octave marks
  by the standard interval rule, dotted-note augmentation cells, and blank-cell
  measure separators. A first accessibility export; chords, in-accord voices,
  signatures and dynamics are follow-ups. Backed by `braille_writer_test.dart`.

- **Multi-part document wrapping** (Workshop contract C6, increment 1):
  `layoutStaffSystemSystems(StaffSystem document, …, maxWidth:)` breaks an
  N-part system into justified systems with barlines aligned across every part —
  the multi-part counterpart of `layoutGrandStaffSystems`. It packs measures by
  the widest part, draws the time signature only on the first system, closes
  non-final systems with a plain barline and stretches them to fill the width
  (shared note-spacing stretch), and returns `StaffSystemSystems`
  (`StaffSystemSystem` per line, with its measure range). `layoutStaffSystem`
  gains `spacingStretch` / `drawTimeSignature` / `finalBarline` to support it.
  Backed by `staff_system_systems_test.dart`.

- **Warped-time cursor** (Phase 3.5): `TempoMap` converts musical time
  (whole-note `Fraction`s) ↔ wall-clock seconds under piecewise-constant tempo
  (`TempoSpan`s), extending the fixed-clock `secondsFor` to scores with tempo
  changes (`secondsAt` / `timeAt`, `TempoMap.constant`). `SyncPoints` maps
  app-supplied `(musical time, seconds)` anchors with linear interpolation and
  end-extrapolation, so the cursor can follow a live or slowed-down performance.
  `Tempo.quarterBpm` normalizes any metronome mark (beat unit + dots) to
  quarter-notes-per-minute.

- **Hide empty staves** (Phase 2.3): `layoutStaffSystem(..., hideEmptyStaves:)`
  drops staves that contain only rests across the whole system (keeping at least
  one) and remaps the bracket groups to the surviving staves — a bracket that
  spanned only-hidden staves is removed. The reduced system is carried in
  `StaffSystemLayout.source`, so bracket/barline rendering follows it. Backed by
  `staff_system_test.dart`.

- **Extended-chord & augmented-sixth identification** (Phase 4.4):
  `identifyChord` / `chordSymbolFor` now recognize extended chords via
  standard-voicing templates — `add9`, `m(add9)`, `6/9`, `9`, `maj9`, `m9`,
  `11`, `m11`, `13`, `maj13`, `m13` — and the three augmented sixths
  (`It+6` / `Fr+6` / `Ger+6`), detected by the *spelled* augmented-sixth
  interval between ♭6 and ♯4 so a German sixth is not misread as its enharmonic
  dominant seventh (A♭–C–E♭–F♯ → `Ger+6`, while A♭–C–E♭–G♭ → `Ab7`).
- **`pitchesForElements(score, ids)`** (Phase 3.1): maps a set of element ids
  (e.g. the playback cursor's currently-highlighted ones) to the set of sounding
  MIDI pitch numbers — chords contribute every pitch; rests / grace notes /
  unknown ids contribute nothing; scans every voice. Drives the instrument
  visualizers.
- **Tab paired with a notation staff** (Phase 6.3): `layoutNotationTab` returns
  a `NotationTabLayout` — a notation staff over a tab staff of the same `Score`,
  laid out once for natural widths then re-laid with the column-wise maxima so
  every barline aligns. `TabLayoutEngine.layout` gains `leadingWidth` and
  absolute `barlineXs` (the notation and tab engines use different inter-measure
  gaps, so the tab barlines are pinned to the notation's canonical x rather than
  shared relative widths, which would drift). `notation_tab_test.dart` asserts
  barline alignment across guitar and bass tunings. Rendered by the new Flutter
  `NotationTabView` (golden 118).
- **Tab Tier-3 completeness tail** (Phase 6.4, fully completes 6.4): tapped /
  semi / feedback harmonics (`TabNoteStyle.tappedHarmonic` / `.semiHarmonic` /
  `.feedbackHarmonic` — angle-bracketed fret + `harmonicLabel` "T.H." / "S.H." /
  "Fbk."; round-trip through GP `HType` Tap/Semi/Feedback); named rasgueado
  strum patterns (`Rasgueado.pattern`); golpe (`Golpe` — a "×" body-tap above
  the fret); wah open/close (`Wah` — "o" / "+"); fade-in/out swells (`Fade`
  span — a growing/shrinking wedge above the staff); and instrument-specific
  chord-diagram presets (`ChordPresets` — ukulele/banjo/mandolin common chords).
  All additive and preserved through `transposedBy`; covered by
  `tab_layout_test.dart` / `chord_presets_test.dart`; golden 117.
- **`Score.barNumberAt(index)`** (Workshop contract C9): the displayed bar
  number of a measure with any pickup (anacrusis) uncounted — 1-based over
  non-pickup measures, `null` for a pickup itself. Exposes the numbering the
  measure-number overlay and the MEI writer already computed (both now route
  through it — one source of truth) for app-side bar labels / navigation.
- **System dividers** (Phase 5.6): `ScorePageView.showSystemDividers` draws a
  `//` (the SMuFL `systemDivider` glyph) in the left margin above each system
  after the first on a multi-system page — the engraver's cue that a new system
  begins. Off by default. Golden 116.

## 0.4.0 (2026-07-13)

First tagged release. Everything below shipped during the 0.4.0 cycle.

- **Lyric-driven horizontal spacing** (Phase 5.4, completing it): a lyric
  syllable wider than its note's natural advance now widens the note spacing so
  the following note clears the syllable (rather than only nudging the text).
  Only wide syllables on short notes are affected; narrow syllables leave
  spacing unchanged. Golden 68 re-rendered.
- **Interchangeable / alternating meters** (Phase 5.7): `TimeSignature.alternate` `TimeSignature.alternate`
  carries a companion signature drawn beside the primary at the start of the
  system (e.g. 3/4 with a 2/4 alternate). Display-only — `measureCapacity` and
  `beamGroups()` use the primary meter; individual bars switch via their own
  change. Round-trips through MusicXML `<interchangeable>`. Golden 115.
- **Baroque ornaments** (Phase 5.6): four new `Ornament`s — `invertedTurn` and
  the trill-with-accidental trio (`trillSharp`/`trillFlat`/`trillNatural`, drawn
  as a small standard accidental above the `tr`, so any SMuFL font works). They
  round-trip through MusicXML (`<inverted-turn>`, `<trill-mark>` +
  `<accidental-mark>`); ABC/kern/MEI/LilyPond take documented lossy fallbacks.
  Golden 114.
- **Portamento** (Phase 5.6): `Portamento(startId, endId)` draws a smooth curved
  slide line between two notes — the curved counterpart to a `Glissando`'s
  straight line. Render-only. Golden 113.
- **Tab technique tail — bend curves, whammy, slide in/out, strum** (Phase 6.4,
  completes 6.4): `Bend.curve(id, [BendPoint(offset, steps), …])` draws a
  multi-segment bend contour (bend-release, prebend, bend-release-bend) as a
  pitch-vs-time polyline with an arrow + amount label at each rise target;
  `TremoloBar.curve` is the analogous *separate* whammy system for
  dip/dive/return gestures (down-arrow + label at each trough). `TabSlide`
  (`SlideInOut.inFromBelow/inFromAbove/outUpward/outDownward`) draws a short
  diagonal sliding into or out of a single fret; `PickStroke` draws a downstroke
  (⊓) or upstroke (∨) above the fret; and `NoteElement.arpeggio` now renders on
  tab as a wavy vertical arrow rolling the chord. All additive and preserved
  through `transposedBy`; `tab_layout_test.dart` covers each; golden 115.
- **Cue / small notes** (Phase 5.1, completing it): `Score.cueNoteIds` marks
  note elements drawn small — notehead, stem, flag and augmentation dots at
  0.72× — for cue / ossia passages. Additive (existing scores are byte-identical
  at scale 1.0). Golden 112. (Beamed cue notes scale the head now; their shared
  stems/beam scale in a follow-up.)
- **Pitch-name & solfège noteheads** (Phase 5.1): two more `noteheadScheme`s —
  `NoteheadScheme.pitchName` draws the note's letter (C–G) in place of the
  notehead, and `NoteheadScheme.solfege` the movable-do syllable (do, re, mi, …)
  from the pitch's scale degree in the current key. Teaching aids that complete
  the notehead-scheme family alongside the shape-note schemes. Goldens 109/110.
- **Grace notes on the tab staff** (Phase 6.4): `NoteElement.graceNotes` now
  render on tablature as small fret digits crammed into the gap just left of the
  principal note — each on its tuning string, connected to the principal by a
  legato arc. An acciaccatura (`GraceStyle.acciaccatura`, the default) draws a
  slash through the grace digit; an appoggiatura omits it. Multiple graces stack
  in reading order. `tab_layout_test.dart` asserts the small digit, the arc, and
  the slash-vs-no-slash distinction; golden 107.
- **Extended trills** (Phase 5.6): `TrillExtension(startId, endId)` draws a `tr`
  glyph over the start note followed by a wavy line (tiled `wiggleTrill`
  segments) running to the end of the trilled note's duration. Round-trips
  through MusicXML `<wavy-line>` (a paired trill-mark on read is folded into the
  span, not a redundant single-note trill). Golden 108.
- **Shape-note noteheads** (Phase 5.1): `LayoutSettings.noteheadScheme` draws
  shape noteheads chosen per pitch by its movable-do scale degree in the current
  key — `NoteheadScheme.sacredHarp` (four-shape: fa = triangle, sol = round,
  la = square, mi = diamond; golden 105) and `NoteheadScheme.aikin` (seven-shape:
  do = triangle-up, re = moon, mi = diamond, fa = triangle, sol = round,
  la = square, ti = rounded-triangle; golden 106). The shapes shift with the key
  signature (its relative minor shares them); an explicit `NoteheadShape` still
  wins. Exposed on the Flutter view as `StaffView.noteheadScheme`.
- **ABC robustness — unequal voices are padded, not fatal**: a multi-voice ABC
  tune whose voices have different bar counts (an imperfect encoding) no longer
  crashes `layoutStaffSystem`; `staffSystemFromAbc` pads the short voices with
  trailing full-measure rests so the system still aligns and renders. Backed by
  a new end-to-end `abc_pipeline_test.dart` that drives real tunes through
  parse → single/multi-staff layout (cross-staff gridding) → MusicXML/MEI/kern
  round-trips → SVG, and asserts the two hands align at shared beats (including
  rest-vs-note, accidental-aware and pickup cases).
- **Reusable OMR library** (CLI): the OMR pipeline (CrispEmbed FFI engine + image
  decode/segmentation + model download + the pure-Dart parsers) is exposed as
  `package:crisp_notation_cli/omr.dart`, so any Dart program — the CLI and Flutter
  **desktop** (wherever `dart:ffi` works) — can drive OMR, not just the CLI. Web
  stays out of reach (no `dart:ffi` on web).
- **Additive-aware & compound beam grouping** (Phase 5.7): `TimeSignature`
  gains `beamGroups()` — the metric beam-group lengths per measure (an additive
  meter's `components`; a compound 8th/16th meter grouped in threes; otherwise
  one group per beat) — and the beam engine now groups notes by them. So 6/8,
  9/8 and 12/8 beam in threes (they previously fell back to flags) and 3+2/8
  beams by its components. Simple meters are unchanged. Golden 104 (6/8); golden
  85 re-rendered with additive beaming.
- **Palm-mute / let-ring / vibrato on the notation staff** (Phase 5.6): the
  existing `PalmMute` and `LetRing` spans now draw a "P.M."/"let ring" label
  followed by a dashed bracket (with a downward end hook) above the notation
  staff, and `Vibrato` draws a wavy line above the note — previously these
  rendered on the tab staff only. Golden 103.
- **Tick / short / reverse-final barlines** (Phase 5.6): three new
  `BarlineStyle`s — `tick` (a short stroke crossing only the top staff line),
  `short` (spanning the middle staff lines), and `reverseFinal` (thick+thin, the
  mirror of a final barline). Round-trip through MusicXML `<bar-style>`
  (`tick`/`short`/`heavy-light`). Golden 102.
- **OMR full-page / multi-system** (CLI): `crisp_notation omr --page` splits a
  full-page scan into staff systems (`segmentStaffSystems`, a pure-Dart
  horizontal-projection band splitter) and recognizes each, concatenating them
  into one score — so a scan with several lines of music transcribes end to end,
  not just one crop.
- **Lyric elision (synalepha)** (Phase 5.4): `Lyric.elidesToNext` marks two
  syllables sung on one note; the layout draws an undertie (‿) bridging them and
  MusicXML round-trips them as one `<lyric>` with `<elision>`-separated `<text>`
  runs (split back into per-syllable `Lyric`s on read). Golden 101.
- **Laissez-vibrer ("let ring") ties** (Phase 5.6): `LaissezVibrer`, keyed by
  note id on `Score`, draws a short trailing tie curve off each notehead of the
  marked element with no destination note — the ring-on notation for piano,
  harp and mallet percussion. Placed opposite the stem like an ordinary tie, or
  forced to a side via `down`. Round-trips through MusicXML
  `<tied type="let-ring">` (with over/under orientation). Golden 100.
- **OMR model auto-download** (CLI): `crisp_notation omr --model <name>`
  (`smt-grandstaff` / `tromr` / `flova`) fetches the GGUF from Hugging Face to a
  cache and reuses it, so no OMR engine needs a manually-supplied model path.
- **Figured bass: slashed figures & continuation lines** (Phase 5.3): a trailing
  `\` on a figure (e.g. `6\`) draws the SMuFL raised-digit glyph (a slash through
  the number — the engraver's alternative to a prefixed sharp), using the
  dedicated glyph for 2/4/5/6/7/9 and `figbassCombiningRaising` otherwise. A
  `'_'` figure row draws a horizontal continuation (extension) line reaching the
  next figured-bass column. Both round-trip through MusicXML — slash as
  `<suffix>slash</suffix>`, continuation as an extend-only `<figure>`. Golden 99.
- **Jazz articulations completed** (Phase 5.9): `JazzArticulation` gains `lift`,
  `flip`, `smear`, and `bend`, drawing the SMuFL brass glyphs U+E5D1/E5E1/E5E2/
  E5E3. `JazzArticulation.rises` picks above/below placement per mark. These four
  are render-only (not standard MusicXML `<articulations>`); scoop/doit/fall/plop
  still round-trip. Golden 98.
- **Third OMR engine — Flova (handwritten)** (v0.8): `scoreFromLilyNotes`
  (`src/omr/lilynotes.dart`) parses CrispEmbed's Flova/omr_transformer output —
  a monophonic LilyPond "simple notes" string (`c'2 a''8 r4 …`) from handwritten
  / whiteboard staff images — into an unmetered single-staff `Score`.
  `omrDialectOf` auto-detects it as a third dialect, so `crisp_notation omr` now
  routes all three CrispEmbed engines (SMT → grand staff, TrOMR → polyphonic
  staff, Flova → handwritten) through one command. Verified live end-to-end.
- **Tab ornaments, articulations & rasgueado** (Phase 6.4): the tab engine now
  draws ornaments (trill/mordent/turn) and articulations (staccato/accent/
  marcato/tenuto/fermata) above the fret by **reusing** `NoteElement.ornament`
  and `.articulations` (no new model — the same data the notation engine uses),
  plus a new `Rasgueado` mark (a downward strum arrow). Golden 97.
- **MuseScore slurs** (interchange enrichment): `Slur` now round-trips through
  MuseScore's location-based `<Spanner type="Slur">` (`<next>` on the start
  chord, `<prev>` on the end), paired positionally on read. This closes the last
  codec gap — `Slur` and `TupletSpan` now round-trip through every codec that
  carries the notes (MusicXML, kern, MEI, MuseScore) plus LilyPond/ABC export.
- **More tab techniques** (Phase 6.4): right-hand p-i-m-a fingering
  (`TabFingering` + `RightHandFinger`, drawn as the letter below the fret),
  slap/pop (`SlapPop` — "S"/"P" above), and tremolo picking (`TremoloPicking` —
  stacked slashes). Each is a `Score` list keyed by note id, rendered by the tab
  engine (ignored by standard notation). Golden 96.
- **Figured-bass realization** (Phase 4.6): `figuredChordPitchClasses(bass,
  figure, key)` reads a figure (`6`, `6/4`, `7`, `#`… — stacked single digits,
  per-degree accidentals, a lone accidental → the third) into the chord's pitch
  classes; `realizeFiguredBass(pairs, key)` completes it to four-part SATB,
  choosing each chord's voicing to minimise `Σ|motion| + 100·(voice-leading
  errors)` — graded by the Phase 4.2 `checkVoiceLeading` engine, so common tones
  are held and parallels avoided. Pure theory. Completes Phase 4 (theory moat).
- **Tuplets in more codecs** (interchange enrichment): `TupletSpan` now
  round-trips through MEI (`<tuplet num numbase>`) and MuseScore
  (`<Tuplet>`/`<endTuplet>`), and exports to LilyPond (`\tuplet a/n { … }`).
  Previously tuplets were carried only by MusicXML and Humdrum `**kern`.
- **Theory extras** (Phase 4.8): neo-Riemannian `parallel`/`relative`/
  `leittonwechsel` (P/L/R) transforms on major/minor `Triad`s; twelve-tone row
  forms (`transposeRow`/`retrograde`/`invertRow`/`retrogradeInversion`) and the
  12×12 `twelveToneMatrix`; and `matchingScales(pcs)` — the scales whose content
  fits a pitch-class set, ranked (rooted-in-the-set first, then major, then
  tonic). Pure theory.
- **Post-tonal set theory** (Phase 4.5): `normalForm`, Forte `primeForm`,
  `intervalClassVector` and `zRelated` for a pitch-class set (0–11), plus
  `transposeSet`/`invertSet`/`pitchClassSet` helpers — the analysis toolkit for
  atonal music. Pure theory. (The Forte set-class *number* is a naming table
  over prime forms; the prime form itself is the canonical identifier.)
- **Key finding** (Phase 4.3): Krumhansl-Schmuckler. `findKey(pcWeights)` and
  `keyOf(pitches, {durations})` correlate a pitch-class weight profile against
  the 24 rotated major/minor key profiles and return the best-matching `Key`
  (with a musically sensible tonic spelling); `localKeys(pitches, window)`
  slides that over the melody to track modulation. Pure theory.
- **Slurs in more codecs** (interchange enrichment): `Slur` now round-trips
  through Humdrum `**kern` (`(`/`)` markers) and MEI (`<slur startid endid>`
  control events, re-anchored across the reader's regenerated ids), and exports
  to LilyPond (`(`/`)`). Previously slurs were carried only by MusicXML and ABC.
  *(MuseScore, whose slur is a location-based `<Spanner>`, is the remaining
  follow-up.)*
- **Voice-leading checker** (Phase 4.2): `checkVoiceLeading(chords)` — each chord
  a list of pitches from the top voice down — flags the classic part-writing
  errors: parallel and hidden (direct) perfect fifths/octaves, voice crossing
  (within a chord), voice overlap (between chords) and upper-voice spacing over
  an octave (the bass–tenor gap is exempt). Returns typed `VoiceLeadingIssue`s
  (rule + chord index + the voice pair). Pure theory.
- **Cross-measure beaming** (Phase 1.4): `CrossMeasureBeam(startId, endId)` on
  `Score` beams a run of notes across a barline. The spanned notes are excluded
  from per-measure beaming and their stems deferred; the beam is drawn in a
  post-pass once both measures' x-positions are fixed, so it continues over the
  barline instead of each measure flagging/beaming on its own. Single-system
  only (a beam cannot cross a line break). Fully additive — scores without one
  are unchanged.
- **Cross-staff notes & beaming** (Score-model lacuna, Phase 2.2): a
  `CrossStaffBeam(noteIds)` on `GrandStaff` joins notes written on both staves
  under one beam — the keyboard figure that reaches from the bass staff up into
  the treble. Each note stays on the staff it is written on; the layout engine
  defers the joined notes' stems (a new `deferredStems` argument →
  `ScoreLayout.crossStaffStubs`, reusing the beam-deferral path so no stem/flag
  is drawn), and `layoutGrandStaff` draws the connecting beam between the staves
  where the inter-staff `staffGap` is known — appended to the upper staff's
  layout, so the existing renderer paints it with no view changes. Upper-staff
  notes stem down toward the beam, lower-staff notes stem up. Golden
  `94_cross_staff_beam`; `cross_staff_test.dart`. *Left:* slanted / multi-bar
  (16th) cross-staff beams and a MusicXML `<staff>` round-trip.
- **Fretted-instrument tunings** (Phase 6.5): preset `Tuning`s for DADGAD,
  open-G, 7- and 8-string guitar, 5-string bass, 5-string banjo (reentrant
  high-G drone), ukulele (reentrant high-G) and mandolin, alongside the existing
  standard/drop-D guitar and 4-string bass. The tab engine is already N-line
  generic, so every instrument renders directly with its own line count.
- **Microtonal accidentals** (Phase 5.10): `Pitch.microtone` (an optional
  `MicrotonalAccidental` — half/three-quarter sharp/flat, ±50/±150 cents) draws
  the Stein-Zimmermann quarter-tone glyphs and always shows (a quarter tone is
  never implied by the key signature). `Pitch.centsOffset` exposes the tuning
  for pitch-bend playback; the integer `alter` and MIDI number are unchanged, so
  this is fully additive. The glyphs are remappable for non-Western systems via
  `LayoutSettings.microtonalGlyphs`. **Contract change:** the prior "microtonal
  out" boundary is lifted — quarter-tone notation is in scope (finer
  just-intonation ratios and full non-Western theory remain out).
- **Non-standard key signatures + senza misura** (Score-model lacuna, Phase
  5.7 tail / 5.8): `KeySignature.custom([KeyAccidental(step, alter), …])`
  expresses modal/atonal signatures the circle of fifths cannot — a mixed
  B♭ + F♯, or a non-traditional accidental order. `alterFor`/`alteredSteps`
  drive both the drawn signature (each accidental placed at its own step, with
  mid-score cancellation naturals generalized to custom keys) and
  note-accidental suppression; it round-trips through MusicXML `<key>`
  `<key-step>`/`<key-alter>` pairs. A non-standard signature is left as written
  under transposition — it has no tonic to move (the notes still transpose).
  Senza-misura (unmetered) scores, already `timeSignature: null`, are now locked
  in by a round-trip test. Golden `92_custom_key_signature`.
- **Optical music recognition** (v0.8): `src/omr/` turns a CrispEmbed Sheet
  Music Transformer `bekern` recognition into the score model — `bekernToKern`
  reconstructs Humdrum, and a multi-spine, `**ekern`-aware kern reader
  (`grandStaffFromKern`/`staffSystemFromKern`) yields a `GrandStaff`/`Score`/
  `StaffSystem`. Tuplet reciprocals approximate to their written note value
  instead of throwing. A second engine — **Polyphonic-TrOMR** — is supported via
  `scoreFromSemantic` (`src/omr/semantic.dart`), which parses PrIMuS-style
  *semantic* notation (`clef-G2 note-C4_quarter …`, chords via `|`) into a
  single-staff `Score`; `omrDialectOf` auto-detects which dialect an engine
  returned. Recognition itself plugs in via the `OmrEngine` abstraction (FFI
  engine lives in `crisp_notation_cli`, `crisp_notation omr` — engine auto-detected).
  `grandStaffToSvg` renders a two-staff `GrandStaffLayout` (sharing `scoreToSvg`'s
  emitter, so `scoreToSvg` is unchanged), and `crisp_notation omr` can write `.svg`
  directly.
- **Humdrum tuplets** (interchange enrichment): the `**kern` reader now reads
  tuplet reciprocals (`6`/`12`/… — non-power-of-two) as real `TupletSpan`s over
  the written note value, and the writer emits them back (a quarter in a 3:2
  triplet → `6`), so tuplets round-trip through kern instead of being
  approximated away. Uniform tuplets (the common case, incl. optical-recognition
  output) round-trip exactly. Powers of two are unchanged.
- **Roman-numeral analysis** (Phase 4.1, bidirectional): `romanNumeralOf(pitches,
  key)` reads a chord as a `RomanNumeral` — scale degree (with a chromatic
  `b`/`#` prefix for borrowed/Neapolitan chords), quality-driven case plus
  `°`/`ø`/`+` marks, figured-bass inversion figures (`6`, `6/4`, `6/5`, `4/3`,
  `4/2`), the major-seventh `M` (`IM7`), and secondary dominants / leading-tone
  chords (`V7/V`, `vii°7/V`) with the tonicized target rendered in its own
  diatonic case. Minor keys accept the raised 6/7 as diatonic (so `V` and
  `vii°`). `pitchClassesOf(numeral, key)` realizes a numeral back to its pitch
  classes; `RomanNumeral.symbol` renders it.
- **Voices 3–4 per staff — layout** (Score-model lacuna, increment 2): the
  layout engine now engraves two to four voices per staff. The former
  two-voice `_layoutTwoVoiceMeasure` is generalized to N voices
  (`_layoutMultiVoiceMeasure`): odd voices (1, 3) stem up, even voices (2, 4)
  stem down; onsets align in shared columns; rests stagger away from the staff
  centre per voice; a note colliding (a second/unison) with a higher voice
  already placed in the column shifts rightward; and when every note in a column
  clears the others, their accidentals share one column block. The `Score.simple`
  DSL now accepts up to four `;`-separated voices. New goldens `90_three_voices`
  and `91_four_voices`.
- **Voices 3–4 per staff — representability** (Score-model lacuna, increment 1):
  `Measure` gains `voice3`/`voice4` (four voices per staff, the notation
  maximum) plus a `voices` getter. They round-trip through MusicXML (multi-voice
  `<backup>`), MEI (`<layer>`) and MuseScore (`<voice>`), and are covered by
  playback and transposition. Fully additive — a single- or two-voice measure
  is unchanged. *The layout engine still engraves voices 1–2; generalizing it to
  draw 3–4 (with new goldens) is the deep follow-up increment.*
- **Metrical-accent hierarchy** (Phase 4.7): `TimeSignature.beatStrength(pos)`
  gives the accent strength of a metric position, normalized so the downbeat is
  `1.0` and each level down the meter's hierarchy of subdivisions halves it —
  4/4 makes beat 3 `0.5` and beats 2/4 `0.25`, 3/4 makes both weak beats `0.5`,
  6/8 accents the second dotted beat, and additive meters accent each group
  start; off-grid (e.g. triplet) positions score `0.0`. Built on the exact
  `Fraction` grid (`TimeSignature.metricGrid()`), resolved to the 64th note.
- **Beam subdivision at metric points** (Phase 1.4): secondary/tertiary beams
  now break at the quarter-note metric point, so a beam group longer than a
  quarter — a half-note beat in cut time (or any x/2 meter) — keeps one
  continuous primary beam while its secondary beams break at the beat's
  sub-pulse, instead of drawing a single over-long secondary beam. Simple x/4
  meters beam per beat (≤ a quarter), so they are unchanged. Applies to both
  the notation and tablature engines.
- **Structured chord symbols** (Score-model lacuna): a `ChordSymbol` (root
  pitch + `ChordSymbolKind` quality + optional slash bass) on `Score`, replacing
  opaque text for lead-sheet harmony. Because roots are real pitches, chord
  symbols now **transpose** (`Cmaj7` → `Gmaj7` up a fifth) — the old free-text
  annotations never did. Round-trips through MusicXML `<harmony>` (structured
  root/kind/bass); text `annotations` now round-trip via `<direction><words>`,
  cleanly separating chords from rehearsal/expression text. Rendered on the
  shared above-staff row alongside annotations.
- **Appoggiatura grace notes** (Score-model lacuna): `NoteElement.graceStyle`
  distinguishes an **acciaccatura** (slashed stem — the default) from an
  **appoggiatura** (unslashed). The layout engine draws the grace-stem slash
  only for acciaccatura; MusicXML round-trips it via `<grace slash="yes|no">`.
  Existing scores/goldens are unchanged (default = acciaccatura).
- **Extended dynamics vocabulary** (Score-model lacuna): `DynamicLevel` gains
  `ppp/pppp/fff/ffff` and the sforzando family (`sf/sfz/sffz/fz/fp/rf`) on top
  of `pp…ff` — each mapped to a real SMuFL glyph (`dynamicPPP`, `dynamicSforzato`,
  …) and round-tripping through MusicXML/ABC (which name dynamics by element).
  New levels are appended, so the original indices are unchanged.
- **Structured tempo** (Score-model lacuna): a first-class `Tempo` (bpm + beat
  unit + dots) on `Score` (and `Score.simple`), replacing the "text-only /
  playback-arg" gap. Carried through MusicXML (`<metronome>`+`<sound tempo>`),
  MEI (`scoreDef @mm`/`@mm.unit`), MuseScore (`<Tempo>`), Humdrum (`*MM`) and
  LilyPond (`\tempo`). Beat unit + dots round-trip through MusicXML/MEI/LilyPond;
  kern and MuseScore store the quarter-note-per-minute equivalent, so a
  quarter-beat tempo round-trips exactly there. Layout does not draw it yet.
- **Score metadata** (first Score-model lacuna implemented): a new
  `ScoreMetadata` on `Score` — title, composer, lyricist, copyright and
  instrument name — carried through the MusicXML (`<work>`/`<identification>`),
  MEI (`<meiHead>`), MuseScore (`<metaTag>`/`<trackName>`), Humdrum (`!!!` OTL/
  COM/… records + `*I"`) and LilyPond (`\header`) headers. `Score.simple` gains
  a `metadata:` argument; empty metadata (the default) round-trips as empty
  (mandatory header fields like a part name are sentinel-nulled). Layout ignores
  it. See PLAN.md for the model-lacuna backlog this begins.
- **Interchange enrichment — articulations & ornaments** (Phase 7.3): the MEI,
  MuseScore and Humdrum `**kern` codecs now round-trip **articulations**
  (staccato/tenuto/accent/marcato/fermata + up/down-bow) and **ornaments**
  (trill/short-trill/mordent/turn), and LilyPond export emits both — closing
  that gap with the MusicXML reference. MEI ornaments use `<trill>`/`<mordent>`/
  `<turn>` control events anchored by `xml:id`; MuseScore and kern attach them
  per note. See PLAN.md "Interchange parity & Score-model lacunae" for the full
  coverage matrix, enrichment backlog and the model lacunae.
- **Humdrum `**kern` import & export** (Phase 7.3): `scoreToKern` /
  `scoreFromKern` write and read a single-spine `**kern` document — the open,
  documented representation used in computational musicology (spec is public;
  no toolkit code used). A **subset** (clef with mid-score changes, key/time
  incl. common/cut and additive, measures, notes/chords, rests, durations
  breve…64th + dots, ties), pure Dart. Enharmonic spelling and (natural)
  courtesy accidentals round-trip; pickup is detected from a short first bar.
  Two voices, slurs, tuplets and lyrics are out of scope.
- **LilyPond (`.ly`) export** (Phase 7.3): `scoreToLilyPond` emits a `.ly`
  source for the LilyPond engraver (best-in-class output). **Export only** — its
  input is a full language — generated from the documented syntax (no LilyPond
  code used), pure Dart. Covers clef (with changes), key/time, notes/chords,
  rests, durations breve…64th + dots, two voices (`<< \\ >>`), ties and pickup
  (`\partial`). Dutch note names; 4/4 · 2/2 render as C · cut-C by default.
- **MEI (Music Encoding Initiative) import & export** (Phase 7.3): `scoreToMei`
  / `scoreFromMei` write and read an `<mei>` (v5) document — the open,
  standards-body notation XML used across digital musicology (Verovio,
  music21). A **subset** codec (clef with mid-score changes as inline
  `<clef>`/`<keySig>`/`<meterSig>`, key/time signatures incl. **common/cut and
  additive**, measures, notes/chords, rests, durations breve…64th + dots, two
  voices/layers, ties, pickup via `@metcon`), pure Dart (web-safe). Pitch
  spelling round-trips through gestural accidentals (`@accid.ges`), so C♯ stays
  C♯. Slurs, tuplets, articulations, lyrics and dynamics are out of scope.
- **Compressed MusicXML (`.mxl`) import & export** (Phase 7.3): `.mxl` — the
  zipped MusicXML that Sibelius, Finale, Dorico and MuseScore all read and write
  — pairs the existing MusicXML codec with the new web-safe ZIP.
  `writeMusicXmlToMxl` / `readMusicXmlFromMxl` (the latter follows the
  `META-INF/container.xml` rootfile, falling back to the first non-`META-INF`
  `.xml`); the CLI gains `.mxl` in+out. A shared `zip.dart` (`zipArchive` /
  `readZipEntry`) now backs the container codecs. Round-trips through the shared
  `Score`; verified in the WASM smoke too.
- **Pure-Dart DEFLATE encoder**: `deflate` (RFC 1951 — greedy LZ77 over a 32 KB
  hash-chain window + fixed Huffman) completes the compression pair with
  `inflate`. The `.gp`/`.mscz` ZIP writers now emit **compressed** (method-8)
  entries instead of stored, so written archives are smaller — with no
  `dart:io`, so it works in the browser / WASM too. Validated against `dart:io`'s
  `ZLibDecoder` (its output is standard DEFLATE) and via a randomised
  deflate→inflate sweep.
- **Web-safe interchange containers** (pure-Dart DEFLATE): a from-scratch
  `inflate` (RFC 1951 — stored / fixed / dynamic Huffman) replaces `dart:io`'s
  `ZLibDecoder`, so the `.gp`/`.gpx`/`.mscz` ZIP + BCFS container reading no
  longer needs `dart:io`. The `gp_container` / `mscz_container` codecs moved
  from `crisp_notation_cli` into web-safe `crisp_notation_core`
  (`readGpifFromGp`/`readGpifFromGpx`/`writeGpFromGpif`, `readMscxFromMscz`/
  `writeMsczFromMscx`), so **reading real compressed `.gp`/`.mscz` files now
  works in the browser / WASM**, not just the CLI. `inflate` is validated
  against `dart:io`'s encoder and the real alphaTab/MuseScore fixtures; the WASM
  smoke inflates a DEFLATE stream and round-trips a `.mscz` under Node.
- **WebAssembly target**: `crisp_notation_core` compiles to and runs as a WasmGC
  module via `dart compile wasm` (dart2wasm) — it uses no
  `dart:io`/`dart:html`/`dart:ffi`/`dart:isolate` (only `dart:typed_data`), so
  the theory, layout and text-interchange codecs run in the browser or any WASM
  host. Added [`example/wasm/`](example/wasm/): an asset-free smoke entry
  (`wasm_smoke.dart`) verified both on the VM and as WASM under Node, a browser
  `dart:js_interop` demo (`main.dart` + `index.html` exposing
  `crisp_notationConvert`/`crisp_notationInfo`), a `build.sh` and a Node runner. The
  `dart:io`-based `.gp`/`.gpx`/`.mscz` container unwrapping stays in
  `crisp_notation_cli`; the `.mscx`/`.gpif` XML payloads are web-safe.
- **MuseScore (`.mscx` / `.mscz`) import & export** (Phase 7.3): `scoreToMscx`
  / `scoreFromMscx` write and read a MuseScore-4 `.mscx` document — a **subset**
  codec (clef with mid-score changes, key/time signatures, measures,
  notes/chords, rests, durations breve…64th + dots, two voices, ties, pickup
  measures), pure Dart (web-safe). Spelling round-trips via the MuseScore
  tonal-pitch-class (`tpcOf`), so C♯ stays C♯. The `.mscz` ZIP container is
  handled in `crisp_notation_cli` (`readMscxFromMscz` / `writeMsczFromMscx`, needs
  `dart:io`), which also gains `.mscx`/`.mscz` input+output. Common/cut meters
  degrade to numeric on this hop; slurs, tuplets, articulations, lyrics and
  dynamics are out of scope. The reader also accepts the shapes real MuseScore
  3/4 files use (`KeySig` as `concertKey`/`accidental`/`subtype`, whole-measure
  `durationType>measure` rests). Because every codec funnels through the one
  `Score`, `.mscx` round-trips transparently with MusicXML, MIDI, ABC and the
  `.gp` line for the data they share.
- **Per-column skyline collision avoidance** (Phase 1.2): the layout engine
  records every glyph's ink and exposes `_skylineTop`/`_skylineBottom` queries,
  so above-/below-staff marks clear only the ink in their own horizontal span
  instead of the whole system's extremes. Applied to text annotations (golden
  86), figured bass, lyrics, navigation marks and chord diagrams — each now hugs
  its own span rather than being pushed by a distant high/low note. **Slurs**
  arch above the full local skyline (interior articulations/accidentals/other
  marks), not just the spanned noteheads. Because the passes run in order
  (notes → ties → slurs → … → annotations/lyrics), each later mark clears the
  earlier ink. **Cross-voice accidentals** in a shared two-voice column are now
  laid out jointly — both voices' accidentals share one zig-zag column block and
  the noteheads align, so they never overlap (golden 88).
- **Extra clefs** (Phase 5.2): the neutral **percussion** clef
  (`Clef.percussion` → `unpitchedPercussionClef1`, no key signature; MusicXML
  `<sign>percussion</sign>` and ABC `clef=perc`, header and per-voice; golden
  83), plus the **French violin / soprano / mezzo-soprano / baritone /
  sub-bass** C- and F-clef positions (golden 84). Each has a correct bottom-line
  pitch reference and on-staff key signatures — for clefs without a hand-tuned
  accidental table, positions are derived by the standard fifth-stacking rule
  (each accidental a fifth from the last, dropping an octave to stay on the
  staff). All round-trip through MusicXML `<clef>` (sign + line).
- **Common / cut time symbols + additive meters** (Phase 5.7): `TimeSymbol`
  (numeric/common/cut) on `TimeSignature`, with `TimeSignature.commonTime` (4/4
  drawn as C) and `cutTime` (2/2 drawn as ¢) from the SMuFL `timeSigCommon`/
  `timeSigCutCommon` glyphs (golden 82). `TimeSignature.additive([3, 2], 8)`
  models a composite meter, drawn `3+2` over `8` with the `timeSigPlus` glyph
  (golden 85). All round-trip through MusicXML `<time>` (`symbol=` /
  `<beats>3+2</beats>`) and ABC `M:` (`M:C`, `M:C|`, `M:3+2/8`, `M:(2+2+3)/8`).
- **Pagination / page layout** (Phase 2.5): `layoutPages` groups the
  line-broken systems into pages of a `PageMetrics` box (page size + margins,
  in staff spaces), packing systems by content height and vertically justifying
  every page except the last (page-fill; extra space shared between systems).
  The Flutter `ScorePageView` renders a single page at its exact aspect ratio
  with margins and an optional page frame (golden 81).
- **Transposing instruments + concert-pitch toggle** (Phase 2.6): a
  `Transposition` (written→sounding interval + direction + octaves, with named
  `bFlat`/`a`/`eFlat`/`f`/`bFlatTenor` constants) on `Score.transposition`.
  `Score.atConcertPitch()` moves the written pitches **and** key signature to
  sounding pitch and clears the tag (`StaffSystem.atConcertPitch()` toggles a
  whole system); `transposedBy` keeps the tag by default (`keepTransposition:
  false` to drop it). MusicXML reads/writes `<transpose>`
  (diatonic/chromatic/octave-change).
- **Pickup / anacrusis measures** (Phase 2.4): `Measure.pickup` marks an
  intentionally incomplete opening bar. A short first bar under a known meter is
  auto-detected as a pickup (both the `Score.simple` DSL and ABC import);
  MusicXML reads/writes it as `<measure implicit="yes">` with anacrusis-aware
  renumbering (the pickup is `number="0"`, real bars count from 1). A new
  `showMeasureNumbers` layout/`StaffView` option draws bar numbers above each
  measure, skipping the pickup so the first full bar reads `1` (golden 80).
  `Measure.copyWith` added.
- **N-staff systems** (Phase 2.1): `StaffSystem` (N `Score` staves + optional
  `StaffBracket` brace/bracket groups) and `layoutStaffSystem` — generalizes
  the two-staff grand staff to any number of staves, laying each out with the
  column-wise-max leading/measure widths so barlines align across the system.
  The Flutter `StaffSystemView` stacks them with connected barlines and left
  brackets/braces, with cross-staff tap hit-testing (golden 75 — a four-staff
  SATB system). *Unblocks multi-voice ABC and tab-paired-with-notation.*
- **ABC multi-voice → staff system**: `staffSystemFromAbc` imports each `V:`
  voice as its own staff — keeping its clef (`V:… clef=…` or the `K:` header)
  and lyrics, with per-voice element-id prefixes so ids stay unique — aligned as
  a `StaffSystem` (golden 76). Both the field-line (`V:1` … `V:2` …) and inline
  (`[V:1]` …) styles are honored; `scoreFromAbc` still returns the first voice.
- **MusicXML multi-part → staff system**: `staffSystemFromMusicXml` imports
  every `<part>` (and every staff of a multi-staff part) as an aligned staff.
  `<part-group>`s from the `<part-list>` become `StaffBracket`s (bracket/brace/
  square/line), and multi-staff parts (piano) are braced; ids get disjoint
  per-staff spaces (golden 77).
- **ABC `Q:` tempo / `P:` parts / line continuation / dotted bar**: header and
  mid-tune `Q:` tempo import as a metronome annotation (`♩ = 120`, with an
  optional quoted label) above the top staff's first note; mid-tune `P:` part
  labels import as annotations; a trailing `\` line-continuation is honored; a
  dotted barline `.|` maps to `BarlineStyle.dotted` and round-trips (a lone `.`
  is still staccato).
- **Nested staff brackets** render with per-depth leftward offsets in
  `StaffSystemView`, so an outer section bracket clears an inner piano brace
  instead of painting over it (golden 78).
- **Up-bow / down-bow articulations** (`Articulation.upBow`/`downBow`): drawn
  above the staff (SMuFL `stringsUpBow`/`stringsDownBow`), imported from ABC
  (`u`/`v` shorthand and `!upbow!`/`!downbow!`) and MusicXML `<technical>`
  (`<up-bow>`/`<down-bow>`), and written back to both (golden 79). Round-trips
  through both formats, coexisting with fingerings in one `<technical>`.
- **ABC import — toward abcjs parity** (Phase 7.3): the reader now handles
  **variant endings / voltas** (`|1 |2`, `[1 [2`, `:|2` → `Measure.volta`),
  **decorations** (`!trill!`/`!fermata!`/`!accent!`… → articulations, ornaments
  and dynamics; shorthand `~ H T M P`), **inline mid-tune fields** (`[K:…]`
  `[M:…]` `[L:…]` → key/meter/unit changes, with the new key sharpening unmarked
  notes), **multi-measure rests** (`Z`/`Zn` → `Measure.multiRest`), **positioned
  annotations** (`"^…"` `"_…"`), **acciaccatura grace** (`{/…}`), and
  **navigation** (`!segno!`/`!D.C.!`/`!D.S.!`/`!fine!`… → `Measure.navigation`,
  which drives the `playbackTimeline` jumps). The writer
  round-trips voltas, decorations, inline key/meter changes and multi-rests. A
  fidelity harness imports the abcjs example tunes as regressions. (PLAN.md
  tracks the remaining ABC constructs and what's gated on Phase 2.1 / 5.10.)
- **Chord identification** (Phase 4.4): `identifyChord(pitches)` /
  `chordSymbolFor(pitches)` — the inverse of `Triad`: names a set of pitches by
  matching its pitch-class set against the common triad / seventh / sixth / sus
  templates, spelling the root from the input and reporting the inversion as a
  slash chord (`C`, `Am7`, `G7`, `Bm7b5`, `C/E`). When two roots fit (C6 vs
  Am7), the bass wins. Pure theory, part of the analysis moat.
- **ABC notation import + export** (Phase 7.3): `scoreFromAbc` /
  `scoreToAbc` — the plain-text format ubiquitous for folk/traditional tunes,
  pure Dart. The reader handles the `M`/`L`/`K` header (meter, unit length,
  key + modes → key signature, clef), then a tune body of pitched notes
  (accidentals with key + measure state, octave marks, `L`-relative and
  fractional lengths), rests, chords, **broken rhythm** (`>`/`<`), ties,
  **tuplets** (`(3`), **slurs**, **grace notes**, staccato, quoted `"C"` chord
  symbols → annotations, bar lines (repeats, double/final), `w:` **lyrics**,
  and multi-voice tunes (first voice). The writer emits the same, so a score
  round-trips through ABC for the data it shares (13 unit + round-trip tests).
  Wired into the CLI (`.abc` in/out, `--from`/`--to abc`). Validated against
  the abcjs example tune-book.
- **Note-name & rhythm-count overlays** (Phase 3.2): `showNoteNames` draws the
  pitch letter (with accidental — `C`, `F#`, `Bb`) under each note (a chord
  stacks its letters); `showBeatNumbers` draws the counting overlay above the
  staff — the beat number on each beat and `+` on the "and" (`1 + 2 + 3 + 4 +`).
  Both are layout options (so the SVG back-end renders them too) exposed as
  `StaffView.showNoteNames` / `.showBeatNumbers`; they coexist for a full
  teaching view (goldens 73, 74).
- **Per-element note coloring, end to end** (Phase 5.1 / interactivity): the
  Flutter painter already colored elements via `CrispNotationTheme.elementColors`;
  now it is also a first-class **`StaffView.elementColors`** render param
  (app-supplied, repaint-only, mirrors `highlightedIds` and takes precedence
  over the theme), and the pure-Dart **SVG exporter** honors an `elementColors`
  map too — so colored scores (out-of-range, right/wrong feedback, hand
  coloring) render consistently in both back-ends (golden 72; pixel + SVG
  tests).
- **Breath marks & caesuras** (Phase 5.6): `BreathMark(noteId, symbol)` draws a
  comma or a caesura ("railroad tracks") after a note at the top of the staff
  (golden 71). Reads and writes MusicXML `<breath-mark>` / `<caesura>`.
- **Figured bass** (Phase 5.3): `FiguredBass(noteId, figures)` stacks continuo
  figures under a bass note, drawn with the dedicated SMuFL figured-bass glyphs
  (digits + `#`/`b`/`n`/`+` alterations — so accidentals render in the
  engraving font, no text-font tofu; golden 70). Reads and writes MusicXML
  `<figured-bass>` (`<prefix>`/`<figure-number>`/`<suffix>`), so common figures
  round-trip.
- **Jazz articulations** (Phase 5.9): `JazzMark` / `JazzArticulation` — scoop,
  doit, fall (falloff) and plop — draw a brass glyph just before or after the
  notehead (golden 69). They round-trip as standard MusicXML `<articulations>`
  (`<scoop>` / `<doit>` / `<falloff>` / `<plop>`).
- **Fix — `transposedBy` dropped new note/measure fields**: transposing a score
  silently lost notehead shapes and barline styles (added earlier this cycle).
  Both are now carried through (regression-tested), along with jazz marks.
- **Multi-verse lyrics** (Phase 5.4): `Lyric.verse` (1-based) stacks verses on
  their own baselines below the staff (golden 68). Each verse de-overlaps
  independently and its hyphens/extenders align to its own syllables. Reads and
  writes the MusicXML `<lyric number="N">` attribute, so verses round-trip; a
  note may now carry several `<lyric>` children.
- **Text no longer overlaps** (Phase 1.2, first cut): lyrics and text
  annotations (chord symbols, tempo/rehearsal text) were centered over their
  note with no collision check, so wide chord symbols or long syllables on
  close notes ran together. The layout now reserves a conservative per-glyph
  width (~0.62 em, covering wide glyphs like `m`/uppercase) and nudges each
  text right of the previous by at least a word gap — guaranteeing no
  horizontal overlap within a row while keeping lyric hyphens/extenders
  aligned to the shifted syllables (golden 67; asserted in
  `layout_more_test.dart`).
- **Notehead shapes** (Phase 5.1): `NoteElement.notehead` / `NoteheadShape`
  (x, diamond, triangle-up, slash, circled-x) overrides the default oval; the
  duration still picks the filled/open/whole/double-whole variant (golden 66).
  Reads and writes the MusicXML `<notehead>` element (`x` / `diamond` /
  `triangle` / `slash` / `circle-x`), so it round-trips. SMuFL codepoints for
  the shape heads were added to the shared codepoint table.
- **Barline styles** (Phase 5.6): a measure's closing barline can now be a
  double bar, final (thin+thick), heavy, dashed, dotted, or none
  (`Measure.barline` / `BarlineStyle`; DSL `!barline=<style>`; golden 65). An
  explicit style on the last measure overrides the default final barline. Reads
  and writes MusicXML `<bar-style>` (`light-light` / `light-heavy` / `heavy` /
  `dashed` / `dotted` / `none`), so it round-trips.
- **Nested repeats** (Phase 7.4): `playbackTimeline` now expands repeat
  barlines with a stack instead of a single start/pass pair, so nested
  `|: … |: … :| … :|` structures unfold correctly — the inner repeat finishes
  each time before the outer jumps back — and two sequential repeats are
  tracked in turn. Voltas still select their bracket by the enclosing repeat's
  pass. (A volta measure that is *also* an inner repeat start remains
  ambiguous and unsupported.)
- **Beams over rests** (Phase 1.4): a rest inside a beat no longer breaks a
  beam — the beam spans the gap (golden 64), matching standard engraving (and
  now, e.g., a triplet `[8th, rest, 8th]` beams under its bracket instead of
  flagging). A rest at a beat boundary still separates, so beats stay distinct.
- **Artificial & pinch harmonics** (Phase 6.4): `TabNoteStyle` gains
  `artificialHarmonic` and `pinchHarmonic` (helper `isHarmonicStyle`). The tab
  engine draws all three harmonic variants with the angle-bracketed fret and
  adds an "A.H." / "P.H." label above the staff for the synthetic ones (golden
  63). The .gp3/.gp4/.gp5 binary readers classify the harmonic-type byte, and GPIF
  read+write carry `HarmonicType` (Natural/Artificial/Pinch), so the type
  survives a `.gp` round-trip. Confirmed on the alphaTab corpora
  (`harmonic-types.gp4`: 3 natural / 3 artificial / 1 pinch; `.gp4` and `.gp5` agree).
- **`.gp` binary import — more note effects** (Phase 7.3): the `.gp3`/`.gp4`/`.gp5`
  binary readers now surface **vibrato** (`Vibrato`; note-level in `.gp4`/`.gp5`,
  beat-level "wide" in `.gp3` and `.gp5`), and **palm mute** / **let ring**
  (per-note flags coalesced into `PalmMute` / `LetRing` bracket spans that a
  rest closes). They already rendered in the tab engine; the readers just
  weren't feeding them. Confirmed against the real alphaTab corpora, where all
  three versions agree (`vibrato.*`, `effects.*` fixtures) — except `.gp3`, which
  has no note-level palm mute.
- **`.gp3`/`.gp4` import** (Phase 7.3):
  `gp3ToScore` / `gp4ToScore` extend the `.gp5` binary reader with the older
  layout — one voice per measure, no RSE/page-setup, `.gp3`'s beat-level
  harmonics, and the narrower beat/note effect flags. Same technique coverage
  (HO/PO, slides, bends, dead, harmonic). Committed regression tests parse the
  real alphaTab `.gp3`/`.gp4` corpora and confirm the versions agree note-for-note
  (`gp_fixtures_test.dart`). The reader now lives in `gp_binary_reader.dart`.
- **`.gp5` import** (Phase 7.3): `gp5ToScore(bytes, {trackIndex})`
  — a from-scratch byte/bit-exact reader for the `.gp5` *binary* format (ported
  from a community `.gp` reader's layout): measures, time signatures, per-track tunings,
  notes as string+fret → pitch, and the note techniques (HO/PO, slides, bends,
  dead, harmonic). Pure Dart. Validated against the alphaTab `.gp5` corpus —
  `chords.gp5` renders identically to `chords.gp` (v7). Wired into the CLI.
- **`.gp` technique import** (Phase 7.3): `scoreFromGpif` now reads the
  common GPIF playing techniques into crisp_notation's tab marks — hammer-on/
  pull-off → slur, slide → glissando, bend (with amount) → `Bend`, whammy
  vibrato → `Vibrato`, dead → `TabNoteMark.dead`, harmonic →
  `TabNoteMark.harmonic`. Validated against the alphaTab `.gp` (v7) corpus (e.g.
  `bends.gp` renders correct "full"/"1½" bend arrows).
- **Tab chord voicing** (fix): `TabLayoutEngine` now assigns each chord tone to
  a **distinct string** (higher pitches to higher strings, lowest fret first)
  instead of placing every pitch at its independent lowest fret — so two notes
  of a chord no longer collide on one line (visible on dense real `.gp`
  chords). Pinned `TabVoicing`s still win; hand-designed goldens are unchanged.
- **GPIF (`.gp`) import/export** (Phase 7.3): `scoreFromGpif` /
  `scoreToGpif` read and write the `score.gpif` XML of the `.gpx`/`.gp` (v6/7/8)
  formats — a subset (tuning, bars → voices → beats → string+fret notes,
  rhythms; single track/voice), pure Dart. Pitches and rhythm round-trip. The
  `.gp` ZIP container is handled in `crisp_notation_cli` (needs `dart:io`), which
  also gains `.gp`/`.gpif` input+output. Because every codec funnels through
  the one `Score` model, formats round-trip transparently for the data they
  share (see `interchange_transparency_test.dart`). Validated against real
  files: the GPIF reader reads the alphaTab .gp (v7) test corpus (incl. a 96-bar
  song) correctly, and the MusicXML/MIDI importers read real music21 corpus
  files (Bach chorales, Corelli) — verified by rendering.
- **Chord diagrams above the staff** (Phase 6.4): `Score.chordDiagrams`
  (`PlacedChordDiagram(elementId, diagram, {scale})`) places a fretboard
  diagram over a note on a shared row above the staff — the lead-sheet
  convention (multiple diagrams over notes) — drawn by **both** the notation
  and tab engines. `ChordDiagram`/`PlacedChordDiagram` moved into the model.
- **Tapping + tremolo-bar** (Phase 6.4, tab techniques): `Score.taps`
  (`Tap(noteId)` — a "T" above the fret) and `Score.tremoloBars`
  (`TremoloBar(noteId, {steps})` — a whammy-bar V with the dip amount, separate
  from string bends). Golden scene 61.
- **Chord / fretboard diagrams** (Phase 6.4): `ChordDiagram(frets, {name,
  fingers, baseFret, fretSpan, barreFret})` + `layoutChordDiagram(diagram,
  settings)` produce a standalone diagram `ScoreLayout` — string×fret grid,
  filled fingering dots, open/muted x·o markers, name, base-fret label, and an
  optional barre — rendering through the SVG/PNG pipeline. Adds an optional
  `round` cap to `LinePrimitive` (a zero-length round line is a filled dot).
- **Tab capo + tuning labels** (Phase 6.2/6.5): `TabLayoutEngine.layout` (and
  `TabStaffView`) gain `capo` (fret numbers read relative to the capo, with a
  "capo N" label) and `showTuning` (each open string's note letter in a left
  gutter). Golden scene 60.
- **Per-note tab string override** (Phase 6.2): `Score.tabVoicings`
  (`TabVoicing(noteId, strings)`) pins each pitch of a tab note to an explicit
  string (0 = top line), overriding the engine's lowest-fret placement (an
  out-of-range pin falls back). The ASCII-tab importer now emits voicings, so
  an imported tab re-renders on the strings it was written on.
- **Plain-text (ASCII) tablature import** (Phase 7.3): `asciiTabToScore(text,
  {tuning, duration})` → `Score` parses the informal web-shared guitar/bass
  tab (dashed string lines + fret numbers) into a pitched, unmetered score:
  chords from aligned columns, barlines from `|`, and techniques `h`/`p` →
  slur, `/`/`\` → glissando, `b` → bend, `~` → vibrato, `x` → dead note.
  Durations are uniform by default, or (with `inferRhythm: true`) *interpreted
  from the horizontal spacing* — smallest gap = an eighth, wider gaps scale up.
  Wired into `crisp_notation_cli` (`.tab`/`.crd`/`.txt`; `--infer-rhythm`).
- **SVG export** (Phase 7.2): `scoreToSvg(layout, {…})` renders a
  `ScoreLayout` to a standalone SVG document (works for both notation and
  tablature); optional `@font-face` embedding of the engraving font. The
  `smuflCodepoints` glyph-name→character table moved into `crisp_notation_core`
  (shared by the Flutter painter and the SVG emitter). Pure Dart.
- **MIDI import** (Phase 7.3): `scoreFromMidi(bytes)` → `Score` parses a
  Standard MIDI File (format 0/1, running status supported). Lossy single-
  staff reconstruction: sharps/treble, sixteenth-grid quantization, chords
  from simultaneous notes, measures packed by the file's time signature with
  cross-barline ties. Round-trips the pitches and quantized rhythm of an
  exported score. Zero new dependencies.
- **MIDI export** (Phase 7.1): `scoreToMidi(score, {quarterBpm,
  ticksPerQuarter})` → a Standard MIDI File (format 0) `Uint8List`, built off
  `playbackTimeline` so repeats / voltas / D.C./D.S./Coda jumps unfold into the
  MIDI. Tempo + time-signature meta, note on/off per pitch, voice 1/2 on
  channels 0/1. Contract-safe (no audio — a byte stream for a consumer's
  synth). Zero new dependencies (`dart:typed_data`).
- **Repeat unfolding — navigation jumps** (Phase 7.4): `playbackTimeline` now
  executes D.C. / D.S. / To Coda / al Fine / al Coda jumps when linearizing a
  score (in addition to repeat barlines and voltas), closing the jump
  execution deferred in v0.7.1. One level: after a D.C./D.S. return the score
  plays straight through (inner repeats not re-taken); a D.S. with no segno or
  an *al Coda* with no coda throws `ArgumentError`.
- **Guitar/bass tablature — foundation** (v0.8): `Tuning` (open-string
  pitches + `fretFor` lowest-fret assignment; standard guitar, drop D, bass
  presets) and `TabLayoutEngine`, which renders a `Score` as fret numbers on
  an N-line string staff with a TAB clef and broken string lines. Includes
  rhythm (stems, flags, per-beat beams below the staff) and playing
  techniques — slides (reuse `Score.glissandos`), hammer-on/pull-off arcs
  (reuse `Score.slurs`), string bends (`Score.bends` — `Bend(noteId,
  {steps})`), vibrato (`Score.vibratos` — `Vibrato(noteId, {wide})`, a wavy
  line above the fret) and palm mute / let ring (`Score.palmMutes` /
  `Score.letRings` — a labelled dashed bracket above the staff) and dead /
  ghost / natural-harmonic notes (`Score.tabNoteMarks` — `TabNoteMark(noteId,
  TabNoteStyle.dead | .ghost | .harmonic)`; "x", a parenthesized fret, or an
  angle-bracketed fret); more techniques land incrementally. Lifts the former
  "tablature out" scope.
- **Forced beam slant** (Phase 1.4): `Score.beamSlants`
  (`BeamSlant(startId, endId, {slant})`) — forces a note run into one beam
  group with a fixed slant (0 = horizontal). Model-only.
- **Feathered beams** (Phase 1.4, engraving quality): `Score.featheredBeams`
  (`FeatheredBeam(startId, endId, {beginBeams, endBeams})`) — forces a note
  run into one beam group and fans the beam count from start to end
  (accelerando/ritardando). Model-only.
- **Sustain-pedal marks** (v0.7.2): `Score.pedals` (`Pedal(startId, endId)`)
  — "Ped." under the start note and a release star under the end, on a line
  below the staff. Model-only; MusicXML `<pedal type=start/stop>`
  round-trips. **Completes the v0.7.2 piano/technical cluster.**
- **Tremolo** (v0.7.2): `NoteElement.tremolo` (1–5 strokes) drawn through
  the stem of a stemmed, unbeamed note. Model-only; MusicXML
  `<ornaments><tremolo type="single">` round-trips (coexists with a trill/
  mordent/turn ornament in the same `<ornaments>`).
- **Glissando / slide** (v0.7.2): `Score.glissandos`
  (`Glissando(startId, endId)`) — a straight line between two notes, same
  id/order validation as slurs. Model-only; MusicXML `<slide>` round-trips.
- **Arpeggio / rolled chord** (v0.7.2): `NoteElement.arpeggio`
  (`Arpeggio.up`/`down`) — a vertical wavy line left of the chord, tiled
  from `wiggleArpeggiatoUp` and capped with a direction arrowhead.
  Model-only (no DSL shorthand, like dynamics/hairpins); MusicXML
  `<arpeggiate direction=…>` round-trips.
- **Fingering numbers** (v0.7.2): `NoteElement.fingerings` (digits 0–9)
  stacked above the note from the notehead upward. DSL `=N` / `=1,3,5`
  suffix (may precede other markers, e.g. `c4:q=2~`); MusicXML
  `<technical><fingering>` round-trips (one per chord tone). Also fixes a
  latent bug where a chord's ornament was dropped on MusicXML import.
- **Navigation marks** (v0.7.1 long-tail parity): `Measure.navigation`
  (`NavigationMark`) — segno/coda targets and the D.C./D.S./To Coda/Fine
  instruction words (incl. *al Coda*/*al Fine*). DSL `!nav=<mark>`; drawn on
  one shared line above the staff per system (glyph targets at the measure
  start, right-aligned instruction words at its end); MusicXML `<direction>`
  (`<segno>`/`<coda>`/`<words>` + `<sound>`) round-trips. Playback timing is
  unchanged — the marks render and round-trip but the timeline does not yet
  execute the jumps.
- **Octave clefs + ottava brackets** (v0.6 polish): `Clef.treble8va`/
  `treble8vb`/`bass8vb` (staff arithmetic, key signatures, MusicXML
  `<clef-octave-change>`); `Ottava(startId, endId, down:)` spans draw
  their notes an octave off sounding pitch under a dashed 8va/8vb
  bracket, and round-trip via MusicXML `<octave-shift>`.
- **Multi-measure rests** (v0.6 polish): `Measure.multiRest` / DSL
  `!mrest=N` — H-bar with end caps on the middle line, count in
  time-signature digits above; playback advances N bars of the current
  meter; MusicXML `<measure-style><multiple-rest>` round-trips.
- **Ornaments** (v0.6 polish): `NoteElement.ornament` — trill, short
  trill (upper mordent), mordent, turn — drawn above the element
  (above a fermata when both exist). DSL markers `%`, `\$`, `&`, `?`;
  MusicXML `<ornaments>` import/export round-trips.
- **Accidental stacking** (v0.6 polish): chord accidentals pack into
  columns — zigzag order from the outside in, each accidental taking
  the rightmost column it clears by ≥ 3 spaces. Octave-apart
  accidentals now share a column; adjacent ones still fan out.
- **Transposition**: `Score.transposedBy(interval, descending:)` moves
  every pitch (chords, both voices, grace notes) plus the key signature
  and mid-score key changes; out-of-range keys wrap enharmonically
  (G♯ major → A♭ major). Ids, rhythm, spans, lyrics unchanged;
  chord-symbol text is not rewritten.
- **Playback-cursor API** (no audio, ever): `playbackTimeline(score)`
  flattens a score into `PlaybackNote`s — exact whole-note `Fraction`
  onsets/durations (tuplet-scaled), rests flagged, two voices in
  parallel, repeats/voltas expanded (`expandRepeats: false` opts out).
  `soundingAt(timeline, t)` yields the ids to highlight;
  `secondsFor(t, quarterBpm:)` maps musical time to wall-clock time.
- **MusicXML export**: `scoreToMusicXml(score)` and
  `grandStaffToMusicXml(grandStaff)` emit `score-partwise` documents
  over the same subset as the importer; every feature round-trips
  through `scoreFromMusicXml` back to a value-equal `Score` (divisions
  chosen as the LCM of all duration denominators, so tuplet durations
  stay integral).
- **MusicXML import (subset)**: `scoreFromMusicXml(xml)` and
  `grandStaffFromMusicXml(xml)` parse `score-partwise` documents —
  pitches/chords/rests, durations (breve…64th, dots), accidentals,
  ties, slurs, tuplets, articulations, grace notes, dynamics, wedges,
  lyrics, `<harmony>` chord symbols, key/time/clef with mid-score
  changes, repeats/voltas, two voices, two-staff parts. Ships its own
  minimal XML reader — the package stays dependency-free. Unsupported
  markup is ignored; unrepresentable documents throw `FormatException`.

- **Chord symbols / annotations**: `Annotation(elementId, text)` on
  `Score.annotations`; DSL `annotations:` parameter (`*` skips a note).
  Text on a shared baseline above all other ink, centered over the
  note; element hit regions grow upward.
- **Lyrics**: `Lyric` (elementId, text, `hyphenToNext`, `extender`) on
  `Score.lyrics`; DSL `lyrics:` parameter (`*` skips a note, trailing
  `-` hyphenates, trailing `_` starts a melisma extender). Layout puts
  all syllables on one baseline below the lowest ink (`TextPrimitive`,
  center-baseline anchored; core estimates widths at 0.5 em/char),
  draws hyphen dashes and extender lines, and grows element hit
  regions. Systems keep their own syllables under line breaking.
- **Line breaking + justification**: `layoutSystems(score, settings,
  maxWidth: …)` breaks a score into `MultiSystemLayout`/`SystemLayout`
  lines — greedy measure packing, clef/key restated per system, the time
  signature only on the first system (but still governing beaming),
  mid-score changes threaded across breaks, slurs/dynamics/hairpins
  spanning a break dropped, non-final systems justified to `maxWidth` by
  binary-searched spacing stretch, thin closing barlines on continuing
  systems. `LayoutEngine.layout` gained `spacingStretch`,
  `drawTimeSignature` and `finalBarline` knobs.
- **Grand staff**: `GrandStaff` + `layoutGrandStaff` — two-pass layout
  aligning leading widths and per-measure widths across staves;
  `LayoutEngine.layout` gained optional `leadingWidth`/`measureWidths`
  minimums.
- **Two voices per staff**: `Measure.voice2` (DSL `;` separator) — voice 1
  stems up, voice 2 stems down; elements sharing an onset align in one
  column (union of both voices' onsets), rests displace vertically,
  cross-voice unisons/seconds shift voice 2 rightward, beams stay per
  voice, ties bind within their voice, accidental state is shared.

## 0.3.0-dev.1


- **Mid-score changes, repeats, voltas**: per-measure `clefChange` /
  `keyChange` (cancellation naturals) / `timeChange` — layout threads the
  current state so positions, accidentals and beam windows follow; repeat
  barlines (`!repeat` / `!endrepeat`), volta brackets (`!volta=n`); DSL
  measure directives.
- **32nd/64th notes and the breve**: new `DurationBase` values (DSL
  letters `t`, `x`, `b`); flags to four hooks, multi-level beams with
  per-level runs and beamlets, extended stems, breve notehead/rest,
  exact 2/1 breve fractions.
- **Grace notes**: `NoteElement.graceNotes` (DSL `{g4}a4:q`), rendered
  as 0.6× slashed eighths before the host; `GlyphPrimitive` gained a
  `scale` field.
- **Dynamics & hairpins**: `Score.dynamics` (pp…ff SMuFL glyphs
  centered under their element) and `Score.hairpins`
  (crescendo/diminuendo wedges), on a shared dynamics line below the
  staff.
- **Articulations**: `NoteElement.articulations` (staccato, tenuto,
  accent, marcato, fermata; DSL markers `' _ > ^ @`), drawn on the
  notehead side opposite the stem, stacked outward; fermatas always
  above and outside the staff.
- **Tuplets**: `TupletSpan` on `Measure` (DSL `3[…]` / `5:4[…]`);
  exact effective durations (`Measure.effectiveDurationAt`), tuplet-aware
  spacing and beam windows (beams never cross a tuplet boundary), ratio
  digit + bracket on the stem side.
- **Slurs**: `Score.slurs` (`Slur(startId, endId)`, DSL `(`/`)` token
  suffixes); the curve goes above unless every spanned note stems up and
  arcs clear of the spanned elements' ink.
- **Ties**: `NoteElement.tieToNext` (DSL suffix `~`) draws tie curves to
  identically-pitched noteheads of the next note element, also across
  barlines; sits opposite the stem. New `CurvePrimitive` (cubic Bézier)
  in the display list — the foundation slurs reuse.

## 0.2.0-dev.1

- **Alto and tenor clefs**: `Clef.alto` (C clef on the middle line, bottom
  line F3) and `Clef.tenor` (C clef on the fourth line, bottom line D3).
  Staff positions, `pitchAt`, layout anchoring and per-clef key-signature
  placement (incl. the tenor sharp pattern) are fully supported; beaming,
  stems, accidentals and interaction generalize unchanged.

## 0.1.0-dev.1

Initial release.

- **Theory**: `Pitch` (MIDI numbers, staff positions per clef, diatonic
  transposition, enharmonics, parsing), `Interval` (P1..P8, d/m/M/A,
  `Interval.between`), `NoteDuration` with exact `Fraction` arithmetic,
  `KeySignature` (−7..7), `TimeSignature`, `Scale` (major, natural/
  harmonic/melodic minor), `Triad` (four qualities, inversions), `Key`
  with `HarmonicFunction` primary triads.
- **Model**: `Score`/`Measure`/`NoteElement`/`RestElement` value types and
  the `Score.simple` string DSL (sticky durations, chords via `+`,
  measures via `|`, auto element ids).
- **Layout**: deterministic `LayoutEngine` producing a `ScoreLayout`
  display list (glyphs, lines, beams) plus element hit regions and measure
  regions, in staff spaces: clefs, key/time signatures, noteheads, stems
  with middle-line extension, flags, beat-based beaming with secondary
  beams and beamlets, ledger lines, accidentals with measure memory,
  augmentation dots, chord clustering, rests, proportional spacing,
  barlines.
- **SMuFL**: `SmuflMetadata` parser for SMuFL font metadata (engraving
  defaults, glyph bounding boxes, stem anchors) and glyph-name constants.
