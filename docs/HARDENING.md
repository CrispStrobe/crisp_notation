# Hardening — real-input gap log

Systematic robustness pass: feed partitura complicated real-world scores from
many sources (Guitar Pro, MusicXML, MIDI, …), parse + render them, and record
every gap found so they can be closed one at a time.

The guiding principle: **the renderer must never crash on real input** — an
unrecognized or malformed element should be skipped (ideally logged), not throw.

## Corpus swept so far

| Source | Files | Result |
|---|---|---|
| Guitar Pro (`.gp3/4/5/.gp/.gpx`, in-repo) | 25 | all parse + render (notation & tab) ✅ |
| MusicXML real scores (OSMD corpus: Bach, Beethoven, Mozart quartet/quintet, Brahms, Debussy, Clementi, 1.2 MB orchestral, `.mxl`) | 12 | 9 render ✅, 1 parse-fail, 2 render-crash |
| MIDI (round-trip of the above) | 3 | all parse + render ✅ |
| MEI real scores (Aguado guitar, Altenburg concerto 431 KB, Bach **Brandenburg** 1.2 MB, fughette) | 4 | all parse + render ✅ (single-part path) |
| Humdrum `**kern` (Bach chorales) | 2 | all parse + render ✅ |
| **C6 multi-part probe** (via `staffSystemFromMusicXml`) | 10 | Mozart quartet → 4 staves, Beethoven/Debussy → 3, Bach/Clementi → 2, **ActorPrelude orchestral → 23 staves / 2377 elements** ✅ (all after G6/G7) |
| **Round 4** — 10 more each: MusicXML (Gounod 7-staff, Haydn, Mozart songs), MEI (Brandenburg II/III/IV, Chopin, chorales), `**kern` (10 Bach chorales → 4-part SATB) | 30 | all parse + render ✅; multi-part probe 19/20 (1 `.mxl` = probe artifact) |
| **Round 4** — MIDI + ABC round-trips of the real XMLs | 10 + 10 | MIDI all ✅; **3 ABC (vocal) rendered a crash → G8** |
| **Round 5** — end-to-end **CLI `render` sweep** of the whole corpus (XML + MEI + kern) through the newly-wired multi-part path | 19 | 17 render ✅ (incl. MEI now multi-part: Altenburg → 8, **Brandenburg → 9**), **1 tab MusicXML crash → G9**, 1 corpus artifact (`chor150.krn` = a 0-byte "404: Not Found" failed download; rejecting it is correct) |
| **Round 6** — fresh OSMD batch (Gounod, Haydn, Joplin, Telemann, Schumann, …) swept via CLI render | 14 | 13 render ✅, **1 UTF-16 crash → G10** |
| **Round 7** — **oracle differential vs music21** over MEI (14) + new music-encoding MEI (7: Musikalisches Opfer, Beethoven quartet Op18, Hymn to Joy, …) | 21 | found + fixed **G14** (beamed notes dropped) & **G15** (only first section read); MEI oracle 0/14 → **10/14 exact**, new batch captures 100% of music21's notes (Beethoven quartet 4151, Musikalisches Opfer 850) |
| **Round 8** — grace-note fix + fresh OSMD MusicXML batch (Joplin Elite Syncopations, Telemann Allegro, Clementi, Saltarello) via oracle | 6 | 5/6 exact (Joplin 1388, Telemann 911 notes); only ActorPrelude diverges (G13, by design). MusicXML importer stays essentially correct. |
| **Round 9** — close **G12**: multi-voice export for kern (`*^` split) + ABC (`&` overlay), writer + reader | — | kern round-trip 89% → **100%**, ABC 90% → **97%**; corpus round-trip sweep now 100% for MusicXML/MEI/MuseScore/kern |
| **Round 10** — 54 more music-encoding MEI (Brahms, Hummel, Liszt, Ravel, Webern, jazz…) via oracle → **G17 voice-aware tuplets** (`TupletSpan.voice`, per-voice `effectiveDurationAt`, `<tupletSpan>` resolved by note ownership not `@staff`) | 54 | Hummel 20392-note concerto, Liszt, Borodin trio, Brahms & Weber quartets → 100%; MEI oracle 0/14 (start) → **54/69** across 75 files. Residual: Schumann cello + inner-voice tuplet bracket glyphs. |
| **Round 11** — real **KernScores** piano (Chopin mazurkas, Mozart sonatas) via oracle | 8 | 0/8 exact — **found G18**: multi-staff kern `*^` column-shift drops ~half the notes on piano scores (2 spines + splits). Confirmed pitch-level (partitura 46-89% of music21). Top priority for the next kern-reader pass. |
| **Round 12** — more KernScores piano (Beethoven/Mozart/Chopin/Scarlatti sonatas), validating G18 | 6 | 3/6 exact after G18 (Mozart sonatas + mazurka → 100%, Beethoven op2 99.5%); kern reader now reads **up to 4 sub-spine voices** per staff. Residual: Beethoven op13/2 *Pathétique* at 86% is **pitch-perfect** (1643/1643 notes) — a pure kern **tuplet-duration** edge (891 tuplet reciprocals), same class as the MEI voice-tuplet residual, not note-dropping. |
| **Round 13** — **new format/source: real ABC** (music21's own O'Neill's-1850 Irish tune corpus), 20 single tunes via oracle | 20 | 10/20 "exact" — but the divergences are **music21's** ABC-parser limits, not partitura: (a) it ignores ABC **broken rhythm** `a>b` (partitura correctly gives 0.75/0.25, music21 uniform 0.5 — tune14 is a hornpipe with 23 `>`); (b) it mis-applies the **key signature** to bare notes (tune07 K:D: partitura F#/C#/B-natural = correct D-major, music21 gives naturals + B♭). Every tune is pitch-perfect where music21 parses correctly. **Lesson: music21 is not a reliable ABC oracle** — use round-trip fidelity for ABC instead (already 100%). |
| **Rounds 14-15** — extend corpus (Scarlatti/Mozart/Chopin-prelude/Beethoven **kern**, fresh O'Neill **ABC**) + run the **`--quorum`** better-oracle-check | 8 + 20 | r11-r14: **0 consensus-bugs** (all divergences = kern tuplet-duration / ABC broken-rhythm / Verovio repeat-expansion, correctly resolved or flagged suspect). r15 ABC: 1 "consensus-bug" that is a **quorum false-positive** — see the accidental-carry note below. |
| **Round 15** — public-domain MuseTrainer MusicXML/MXL piano set + Verovio visual comparison (Bach, Canon, Satie, Mozart K545, Joplin, WTC) | 8 | Round-trip stayed 100% for notation exporters; K545 visual sweep found **G20/G21/G22/G23**. Fixed: hidden MusicXML playback notes rendered visibly, inner-voice MusicXML tuplets ignored, line-break slicing dropped voice3/4, CLI PNG rendered text/dynamics as boxes. Residual: mid-measure clef changes need a model extension; staff labels and line-start bar numbers need left-margin system SVG support. |
| **Round 16** — K545 engraving parity follow-up + Verovio oracle sweep + round-trip sweep | 8 | Fixed **G24/G25/G27/G28/G30/G31** and partially mitigated **G29**: MusicXML inline clefs now import/layout at their measure onset; staff-system SVG and Flutter PNG share left-margin instrument labels and original line-start bar numbers; cross-system slurs now render as per-line continuation segments instead of disappearing; omitted initial lower-staff clefs in two-staff MusicXML now default to bass; below-staff words and cross-voice head spacing are preserved; overwide wrapped systems are backed off after real layout; adjacent staves expand their gap when local slur/ink bounds would collide. K545 SVG/PNG now show `Piano`, line starts `5, 8, 11…`, all 101 imported slurs as visible line segments, lower-staff bass clefs where the current clef is bass, and the previously overflowing T57/T70 systems fit at `--width 120`. Text markings now use a music-style serif fallback (`Academico`/New York/Times) instead of generic sans where possible. Round-trip stayed **100%** for MusicXML/MEI/kern/ABC/MuseScore over r15. Verovio note oracle is **1/8 exact** and mostly Verovio-only, so log **G26** for the remaining visible-note under-read / oracle-mode investigation rather than treating it as a visual engraving blocker. |
| **Rounds 17-19** — `--quorum` (music21 + Verovio) over 42 fresh files: Bach 4-part chorales (kern + music21 MusicXML), music-encoding structure/lyrics MEI, Palestrina masses (kern), Monteverdi madrigals (mxl) | 42 | **0 consensus-bugs.** All confirmed correct (both-agree) or resolved-correct (Verovio over-expanded repeats). partitura validated across Bach chorales, Renaissance modal polyphony (musica ficta), and multi-section/verse MEI. Only oracle-side SKIPs (Verovio couldn't parse some Monteverdi mxl). |
| **Round 20** — Bach chorale MusicXML + essen-folksong ABC via `--quorum` (now with the **abc2midi tiebreaker**) | 27 | Bach MusicXML all correct. ABC flagged 1 "consensus-bug" (`essentune11`) — the same no-carry accidental false-positive; **abc2midi (reference) confirms partitura** (98.4% vs the oracles' 92%), so the quorum now **auto-resolves it to CHECK✓**. The quorum consults abc2midi on ABC consensus-bugs, since music21 & Verovio share the no-carry convention. |
| **Round 21** — exotic: **Schoenberg Op.19 (atonal)** + Beethoven string quartets (music21 corpus) via `--quorum` | 6 | **0 consensus-bugs.** Atonal Schoenberg (dense accidentals, no key) → resolved-correct; Beethoven quartets suspect only from Verovio repeat-expansion (partitura ≈ music21, off by 1 on op18no1-1). |

## Round-trip fidelity (import ↔ export)

Beyond "does it crash?", we measure **how much survives** a write-then-read
round-trip — this exercises the importer *and* the exporter together and
quantifies parse fidelity. Two harnesses:

* `test/oracle_validated_test.dart` — committed, self-contained: pins the
  spec-correct ABC behaviours the oracle campaign proved partitura reads right
  (accidental carry within the bar + reset, key applied to bare notes, broken
  rhythm, mid-tune key change) against buggy external parsers.
* `test/roundtrip_fidelity_test.dart` — committed, self-contained: feature-probe
  scores (stepwise, chords+rests, dotted+ties, accidentals, wide range) through
  every round-trippable format. Notation formats are held to the **full notated
  content** (pitch, rhythm, enharmonic spelling, clef, key, meter); MIDI only to
  **sounding content sampled over time** (it legitimately re-notates rhythm and
  can't encode a trailing rest). 30 cases green.
* `tool/roundtrip_sweep.dart` — diagnostic over the real corpus at
  `/Volumes/backups/ai/partitura-corpus`; compares the note multiset
  `(sorted-MIDI, duration)` across all voices. Latest run (79 imported scores):

  | format | exact | avg note-preserved |
  |---|---|---|
  | MusicXML | 100% (92/92) | 100.0% |
  | MEI | 100% (92/92) | 100.0% |
  | MuseScore | 100% (92/92) | 100.0% |
  | kern | 100% (92/92) | 100.0% |
  | ABC | 100% (92/92) | 100.0% |
  | MIDI | 28% (26/92) | 89.4% |

  (These numbers count **all four voices** — an earlier version of the sweep read
  only voice 1 and so reported a misleading kern/ABC 100%.) kern and ABC
  now round-trip all voices too — the kern writer splits the spine (`*^`) and
  the ABC writer emits `&` overlays (G12 fixed). ABC's 97% residual is G11
  resolved too (it was a key-change accidental bug, G11 — not broken
  rhythm): every notation format now round-trips at **100%**. MusicXML / MEI /
  MuseScore preserve every voice. MIDI's lower "exact" is **expected** — the multiset key includes duration, and
  MIDI re-notates dotted/tied rhythm; the committed test's sampled-sounding
  metric confirms MIDI keeps what sounds. A round-trip only proves reader+writer
  are **mutually consistent**; the external oracle (`tool/oracle_diff.*`) tests
  **correctness** against an independent parser.

## External oracle (differential vs music21)

`tool/oracle_dump.py` (music21) + `tool/oracle_diff.dart` parse the *same* file
two ways and compare the note multiset `(midi, tuplet-scaled quarterLength)`
across **all** parts (partitura via the multi-part `staffSystemFrom*`, to line
up with music21's all-parts flatten). This catches bugs a round-trip can't — a
reader+writer that are wrong in the *same* way round-trip cleanly. music21 is
"trusted" only as a mature independent parser; a confirmed divergence is
investigated, not blindly blamed on partitura.

Latest sweep — **45/47 MusicXML+kern scores agree exactly** (all 12 Bach kern
chorales; Mozart quartet + Clarinet Quintet; Clementi; Telemann; Schubert;
Debussy; Dichterliebe; Gounod; Haydn; the lieder — every multi-voice piano
score). partitura's importer is, on this corpus, essentially correct.

**Two rounds of "divergences" turned out to be bugs in the oracle *tool*, not in
partitura** — a live demonstration of the user's caution that the oracle script
`s` can be the buggy one:
1. It first compared the *nominal* notated duration, flagging every triplet
   (Mozart AnChloe / Clarinet Quintet). Fixed to use `effectiveDurationAt`
   (tuplet-scaled).
2. It then counted only voice 1 (`measure.elements`), ignoring the model's
   `voice2/voice3/voice4` — so it mis-reported every multi-voice piano score as
   "partitura dropped notes." Fixed to read all four voices. This collapsed the
   apparent gap from 14 scores to 2, and confirmed the importer *does* capture
   inner voices (Dichterliebe: 410 of music21's 411 notes).

The **2 genuine residuals**: `Voice_Alignment` (a synthetic 5-voice test — the
model caps at 4 voices/staff, so 2 notes shift) and `ActorPrelude` (~244 notes with irregular un-typed durations are
*snapped* to the nearest notatable value per G6, vs music21's exact fractional
quarterLength — a deliberate trade-off, not a parse error). See G12 / G13.

**Extending the oracle to the MEI corpus (14 files) then paid off big** — it
found two *real* MEI-reader bugs (not tool artifacts this time), now fixed:
0/14 → **10/14 exact** (G14 beams, G15 sections); a follow-up grace-note
fix (G16) then reached **16/20** across the expanded MEI corpus. The residual
over-reads are benign (repeat endings / enharmonic spelling).

## A better oracle than music21? — Verovio + an ensemble quorum

music21 has real ABC gaps (round 13: it ignores broken rhythm and mis-applies
key signatures), so it is not a trustworthy oracle everywhere. Two additions:

* **Verovio** (`tool/verovio_dump.py`, `dart run tool/oracle_diff.dart --oracle
  verovio`) — RISM Digital's engine, the *reference* MEI renderer, embeds
  **humlib** (authoritative `**kern`), and parses ABC (broken rhythm, keys) and
  MusicXML. It is a stronger front-end parser than music21 — e.g. on the O'Neill
  tune where music21 was wrong about K:D, **partitura agrees with Verovio 100%**,
  confirming partitura (not music21) was right. Caveat: Verovio's note times come
  from its playback timemap, which **expands repeats / graces / articulation**,
  so it is noisy for written-note comparison on repeat-heavy classical scores.

* **Ensemble quorum** (`--quorum`) — the actual answer. Compare partitura against
  **both** music21 and Verovio and classify each score:
  - **OK** — both oracles agree with partitura (high-confidence correct).
  - **consensus-bug** — the two independent oracles agree with *each other* but
    not with partitura → a genuine partitura-bug signal.
  - **oracle-split** — the oracles disagree with each other → an oracle
    limitation (music21's ABC gaps, Verovio's repeat expansion), *not* evidence
    against partitura.

  Across every score tried, the quorum finds **0 consensus-bugs**: there is no
  case where two independent parsers agree against partitura. Every divergence
  this whole hardening effort surfaced traced back to an oracle limitation or a
  since-fixed reader bug — strong, triangulated evidence the importer is correct.

## Limit of the ensemble oracle — a shared convention can fool a quorum

The `--quorum` better-oracle-check flagged `oneill103.abc` as a consensus-bug
(both music21 **and** Verovio read F♯ where partitura reads F♮ on 4 notes). But
this is a **false positive**: the tune has `=f` (explicit natural) followed by a
bare `f` **in the same bar**, and the **ABC 2.1 spec says an accidental carries
to the end of the bar** — so partitura (F♮) is *spec-correct*, and *both* oracles
share a common non-spec no-carry convention. A minimal test confirms it:
`K:G` … `=f f | f f` → partitura `F♮ F♮ | F♯ F♯` (carry within bar, reset at the
barline), music21 & Verovio both `F♮ F♯ | F♯ F♯`.

**Settled by a third oracle — `abc2midi`, the *reference* ABC engine** (James
Allwright / Seymour Shlien; `tool/abc2midi_dump.py`, `--oracle abc2midi`): it
gives `F♮ F♮ | F♯ F♯`, **identical to partitura** — so partitura and the
reference implementation agree, and music21 + Verovio share a non-spec no-carry
bug. Across 45 real ABC tunes, partitura's **pitch set matches abc2midi on
37/45** (only 11 pitch-classes differ total) — the reference engine validates
partitura's ABC reading. (abc2midi's overall midi@ql match is low only because
its MIDI is playback: repeats expanded + articulation gaps, like Verovio.) For
ABC, abc2midi is the authoritative pitch oracle; music21/Verovio are not.

The 8/45 tunes whose pitch set differed from abc2midi (5.03, 2025-04-26) are
**abc2midi's own tie-parsing bugs**, not partitura errors: it errors on the
O'Neill tie syntax (`{d}c3-B`, `f/-e/` → "Could not find note to be tied" on
nearly every tune) and on 8 emits a spurious pitch (an E♭ where there is no
`_e`; an F♮ in a D-major tune with no accidentals). Spot-checked against the
spec, partitura is correct on all of them. The newer **abc2midiu v1.0**
(keryell's abc-2.2 fork, 2026-04, built from source) gives the **same** result —
it confirms the accidental carry *and* reproduces the identical spurious pitches
from the same tie-errors — so the tie bug is inherent to the abc2midi family,
not a stale version. So **all three ABC engines (music21, Verovio,
abc2midi/abc2midiu) have distinct bugs on real tunes — no-carry accidentals,
repeat expansion, tie parsing — while partitura reads them spec-faithfully.**
There is no single clean ABC oracle; the round-trip harness (100%) is the
reliable ABC fidelity measure.

Lesson: even two independent oracles agreeing is not proof — when the tools
share an ecosystem convention that departs from the format spec, the quorum can
be wrong and partitura right. Consensus-bugs still must be checked against the
**spec**, not just the tools. (Whether to match the ecosystem's no-carry
behaviour for real-world ABC interop is an owner decision, not silently changed
— partitura currently follows the written standard.)

## Gaps

| # | Severity | Area | Symptom | Repro | Status |
|---|---|---|---|---|---|
| G1 | medium | CLI packaging | `render` to SVG failed *"SMuFL metadata not found"* when the CLI binary ran outside the repo tree — so the **released standalone binary** couldn't render without `--metadata`. | `partitura render x.musicxml x.svg` from `/tmp` | **fixed** — Bravura metadata embedded (deflate+base64, ~136 KB) as an offline fallback |
| G2 | high (fidelity) | reader / model | Multi-part scores collapsed to a **single part** through the single-`Score` path. | `partitura info Mozart_String_Quartet…` → 1 clef | **fixed by C6 + CLI wiring**: `staffSystemFromMusicXml` + `layoutMultiPartPages` import & paginate all parts. The **CLI `render`** now auto-detects a multi-part input, wraps it into line-broken systems (`layoutStaffSystemSystems` → `staffSystemSystemsToSvg`) and draws every staff with shared systemic barlines. Verified: Mozart quartet → 4 staves, ActorPrelude orchestral → **23 staves / 5379 glyphs**, Bach chorale kern → 4 (SATB), Clementi → 2. `--single` forces the old one-part path; `--width` / `--hide-empty` tune the wrap. |
| G6 | high | musicxml reader | The orchestral **ActorPrelude** threw `Cannot map duration 85/1024` — a `<duration>` with no `<type>` that doesn't reduce to a standard value aborted the import. | multi-part import of `ActorPreludeSample.xml` | **fixed** — snaps to the nearest note value |
| G7 | high | musicxml reader | A percussion `<unpitched>` note (no `<pitch>`, no `<rest>`) threw `<note> without <pitch> or <rest>`, aborting the import (orchestral scores). | same file, after G6 | **fixed** — `<unpitched>` maps to its display staff line (proper percussion staff is a tracked follow-up) |
| G8 | high (crash) | **abc reader** | A vocal ABC round-trip threw `RangeError` in `_layoutLyrics`. **Root cause** (not the layout): the reader added *rest* ids to `noteOrder`, so `w:` syllables aligned onto rests — shifting every syllable and attaching some past the last note. | round-trip render of Mozart AnChloe / DasVeilchen / Land der Berge | **fixed at the source** — `noteOrder` now holds note ids only, so syllables align to notes and skip rests (per the ABC spec). Regression test pins it. |
| G3 | high | musicxml reader | A slur `start`/`stop` imbalance (a `type="continue"` reusing a number, or a lost `stop`) left a slur open → parse aborted *"Unclosed `<slur>`"*. | `partitura info Debussy_Mandoline.xml` | **fixed** — dangling slur dropped, parse continues |
| G4 | high (crash) | layout engine | A degenerate `Hairpin(eN → eN)` (start == end) threw `must run forward in reading order` — uncaught. | `partitura render Dichterliebe01.xml …` | **fixed** (a2… ) |
| G5 | high (crash) | layout engine | A `Pedal(e0 → e29)` whose end id is not in the imported score threw `references an unknown note element id` — uncaught. | `partitura render OSMD_Function_Test_Pedals.musicxml …` | **fixed** |
| G9 | high (crash) | musicxml reader | A **guitar-tablature** MusicXML staff carries `<clef><sign>TAB</sign>`, which `_clefOf` didn't recognize → threw `Unsupported clef: TAB5`, aborting the whole import. | `partitura render BrookeWestSample.mxl …` | **fixed at the source** — `TAB` maps to the guitar clef (`treble8vb`, sounding 8vb) so the staff's real `<pitch>`es render; any other/malformed sign now defaults to treble instead of aborting (reader-leniency, per G3/G6/G7). BrookeWest → 2 staves. Regression test in `musicxml_test.dart`. |
| G10 | high (crash) | CLI file read | A **UTF-16 LE (BOM)** MusicXML — a legal, common export encoding, its XML prolog even declaring `encoding="UTF-16"` — threw `FileSystemException: Failed to decode data using encoding 'utf-8'` because the CLI read every text score via `File.readAsStringSync` (UTF-8 only). | `partitura render test_UTF16LEBOM_decoding_nested_tuplet.musicxml …` | **fixed at the byte→String boundary** — a `_readText` helper sniffs the BOM (UTF-16 LE/BE, UTF-8) and decodes accordingly (`dart:convert` ships no UTF-16 codec); all text-format reads route through it. CLI round-trip test in `cli_test.dart`. |
| G11 | low (rhythm fidelity) | abc writer/reader | An ABC round-trip of a dense syncopated ragtime (Joplin *The Entertainer*) preserves **every pitch, note and measure** (520 notes / 955 pitches / 92 bars identical) but re-encodes a handful of sub-beat **durations** (some 1/16 / dotted-1/16 in broken rhythm come back as a different value). Found by `tool/roundtrip_sweep.dart` (99.9% note-preserved). | round-trip of `ScottJoplin_The_Entertainer.xml` through ABC | **fixed** — two ABC accidental bugs: the writer computed accidentals against the *initial* key, so after a mid-tune `[K:…]` change a note the new key alters (E under 2 flats) was written bare and read a semitone off; and the reader carried voice-1 accidentals across a `&` overlay. Both fixed; ABC round-trip **90% → 100%** (Joplin *Entertainer*/*Elite Syncopations* now exact). `abc_test.dart`. |
| G12 | medium (export fidelity) | **kern / abc writers** | The kern and ABC **writers are single-voice subset codecs** — they emit only voice 1 and silently drop `voice2/3/4`, so a multi-voice score loses its inner voices on export (round-trip 90%, the loss exactly equals the voice2-4 note count: Bach *Ein feste Burg* 38/38, Ahle 40/40, Haydn 55/65). **Import is fine** — the model + all readers (MusicXML/MEI/MuseScore) carry four voices, verified 100% by the oracle. *(This gap was originally mis-logged as an importer bug; that was the oracle tool reading only voice 1 — corrected.)* Separately, the model caps at **4 voices/staff**, so `Voice_Alignment`'s 5th voice shifts (synthetic, 2 notes). | round-trip of `Bach-JS_Ein_feste_Burg.mei` through kern/ABC | **open** — kern needs spine-split (`*^`/`*v`) multi-voice output; ABC needs `V:`/`&` polyphony. Both are real features (the writers document themselves as single-spine). Model's 4-voice cap is a separate, low-value extension. **FIXED** — the ABC writer now emits inner voices as `&` overlays and the reader parses them into voice2/3/4; the kern writer splits the spine (`*^` … `*v *v`) with the voices time-merged and the reader tracks the split into voice2. Round-trip: **kern 89% → 100%, ABC 90% → 97%** (the ABC residual is G11 broken-rhythm durations, not voices — voice3-4 = 0 in every remaining case). Regression tests in `abc_test.dart` / `kern_test.dart`. Remaining edges: voices 3-4 in kern, multi-staff intra-voice (rare). |
| G13 | low (by design) | musicxml reader (duration snapping) | The orchestral **ActorPrelude** is the one MusicXML score that still diverges from music21 (95.7%): partitura keeps the 14 `<tremolo type="single">` correctly as marks (no expansion), but ~244 notes with **irregular `<duration>` values and no `<type>`** (e.g. 85/1024 — the G6 case) are **snapped to the nearest notatable value** (a dotted-64th, ql 0.094), whereas music21 keeps the exact fractional quarterLength. | `dart run tool/oracle_diff.dart ActorPreludeSample.xml` → 244 notes at ql 0.094 | **by design** — the G6 snap-to-nearest is what stops these un-typed fine durations from aborting the import; the trade-off is a small rhythmic rounding vs music21. Not a parse error. *(Earlier mislabelled as tremolo expansion — corrected after checking: only 14 notes carry a tremolo mark, none are expanded.)* |
| G14 | high (fidelity) | **mei reader** | MEI wraps beamed notes in `<beam>` containers; the layer reader handled `note/chord/rest/tuplet` but let `<beam>` fall through `default`, so **every beamed note was dropped**. Baroque scores are ~90% beamed — a Brandenburg movement read 758 of 9140 notes (8.3%). Found by the music21 oracle over the MEI corpus. | `dart run tool/oracle_diff.dart Bach-JS_BrandenburgConcert_No2_I_BWV1047.mei` → 8.3% | **fixed** — `_flattenBeams` unwraps `<beam>` (recursively; also inside `<tuplet>`) so its children join the sequence. Brandenburg I now 9140/9140 exact. Regression tests in `mei_test.dart`. |
| G15 | high (fidelity) | **mei reader** | The reader read only the **first** `<section>` of a score (`score.child('section')`), dropping every later section — a chorale with one section per verse kept 4 of 18 measures. | `dart run tool/oracle_diff.dart Altenburg_Macht_auf_die_Tor.mei` → 23% | **fixed** — gather measures from *all* `<section>`s (recursing through nested sections / repeat `<ending>`s) in document order. MEI oracle 0/14 → 10/14 exact after G14+G15. Regression test in `mei_test.dart`. |
| G16 | medium (fidelity) | **mei reader** | Grace notes (`<note grace="acc\|unacc">`) were read as **full-duration notes**, over-filling the bar and inflating the note count (the MusicXML reader already folds them). Found as a consistent small over-read across grace-heavy MEI (Beethoven quartet +30, Musikalisches Opfer +53). | `dart run tool/oracle_diff.dart Beethoven_StringQuartet_Op18_No1.mei` → +30 partitura-only | **fixed** — grace `<note>`/`<chord>` accumulate as `graceNotes` on the following principal note (acc→appoggiatura, unacc→acciaccatura), matching the MusicXML reader. MEI oracle 10/14 → **16/20** exact; the residual over-reads (Altenburg, Chopin) are repeat-ending / enharmonic, benign. `mei_test.dart`. |
| G17 | high (fidelity) | **mei reader** | Tuplets encoded as a `<tupletSpan startid endid num numbase>` **control event** (referencing the first/last note by id) — how professionally-encoded MEI marks most tuplets — were ignored, so the notes kept their nominal (unscaled) duration. The oracle showed pitch-perfect but duration-divergent scores: Hummel trumpet concerto 88% (20392 notes), Brahms quartet 95%, Liszt 92%. | `dart run tool/oracle_diff.dart Hummel_Concerto_for_trumpet_E-major.mei` → 2410/2410 duration-only | **fixed** — `<tupletSpan>`s are collected per measure, resolved by note id to voice-1 index ranges, and applied as `TupletSpan`s. Hummel & Liszt → 100%, Brahms → 99%. MEI oracle over the expanded 75-file corpus 51/69 exact. Residual: tuplets in voices 2-4 (the model carries tuplets on voice 1 only). `mei_test.dart`. |
| G18 | high (fidelity) | **kern reader** | Multi-staff kern (piano: 2 `**kern` spines, often + a `**dynam` spine) uses per-spine **sub-spine splits** (`*^`). When a *left* spine splits, every spine to its right shifts one column — but the reader tracks each staff at a **fixed** starting column and only follows splits within its *own* spine, so after a left split it reads the wrong column and **drops ~half the notes**. Found by the music21 oracle on real Chopin mazurkas / Mozart sonatas: partitura 411 vs music21 896 notes (46%). Single-staff `scoreFromKern` (no left neighbour) is unaffected. | `dart run tool/oracle_diff.dart chopin-mazurkas_mazurka06-1.krn` → 75%, 411/896 | **fixed** — a `_spineLayout` pass tracks the global Humdrum spine tree (`*^` duplicates a slot keeping its staff tag, `*v` merges, `*-` terminates, non-kern spines interleave) and returns, per line, the staff tag of every column. `_KernReader` now reads its staff by **tag**, not a fixed column, so left-neighbour splits no longer misalign it. Chopin mazurka06-1 75%→**98.9%**, mazurka-52→100%, Mozart sonata 89%→94%; new-kern oracle 0/8→**6/8 exact**; Bach chorales + 1398 core tests still green. `kern_test.dart` (G18 multi-staff split). |
| G19 | medium (over-read) | **mei reader** | On some MEI, partitura reads **phantom chords / duplicate pitches**: Brahms *Wie Melodien* → 37 chord-elements vs the file's 29, and 264 pitches from 241 `<note>` (~23 duplicated). **Surfaced by the better-oracle-check** (`--quorum`): both music21 *and* Verovio agree (226 notes) while partitura has +38 — a consensus signal that single-oracle runs had dismissed as a "benign over-read." | `dart run tool/oracle_diff.dart --quorum Brahms_WieMelodienZiehtEsMir.mei` → BUG? | **fixed** — when a measure omits its `<staff n=X>`, the reader fell back (`orElse`) to another staff's `<staff>`, duplicating that content. Now `@n`-labelled staves match exactly and an absent staff reads an **empty** bar (only unlabelled single-staff docs match by position). Both consensus-bugs resolved: Brahms *Wie Melodien* & Altenburg *Macht* → OK; MEI oracle 19/19 exact on the first 20 files; 1417 core + `mei_test.dart` (G19). **The first genuine bug the ensemble/quorum oracle caught that single oracles missed.** |
| G20 | high (engraving) | **musicxml reader** | Hidden MusicXML notes (`print-object="no"`) imported as visible notes, corrupting K545 bar 4's upper staff against Verovio. | K545 MXL, measure 4 hidden voice-2 32nds | **fixed** — hidden notes are skipped by the visible-score importer; regression in `musicxml_test.dart`. The raw music21 oracle now needs a visible-note mode for files with hidden playback scaffolding. |
| G21 | high (duration) | **musicxml reader** | MusicXML tuplets in inner voices were ignored; K545 measures 25/70 encoded 2:1 tuplets in voice 2, so four 32nd notes were read as sixteenths. | `oracle_diff --details K545.mxl` showed 72/74/79/81 at 0.25 instead of 0.125 | **fixed** — tuplets now track open spans per imported voice and set `TupletSpan.voice`; regression in `musicxml_test.dart`. |
| G22 | high (layout fidelity) | **multi-system layout** | The line-break slicer copied only `elements` and `voice2`, dropping voice3/4 and their ids/spans from wrapped systems. This causes missing long slurs/spans and wrong multi-voice engraving after system breaks. | K545 visual comparison; any wrapped staff with voice3/4 | **fixed** — `_slice` preserves voice3/voice4 and includes their ids for span filtering. |
| G23 | medium (PNG rendering) | **CLI PNG harness / SMuFL table** | CLI PNG output rendered text as black boxes (Flutter test font) and crashed/boxed extended dynamics like `ppp` because `smuflCodepoints` lacked the extended dynamic glyphs. | Satie Gymnopedie PNG; K545 PNG comparison | **fixed** — PNG harness loads Roboto for text, dynamic codepoint table covers every `DynamicLevel`, and regression checks actual codepoint coverage. |
| G24 | high (model/layout) | **clef changes** | MusicXML can change clef mid-measure/staff (K545 bar 5 bass staff changes to F clef after rests). The model only supports measure-start `clefChange`, so the change is applied at the wrong horizontal position. | K545 measure 5 | **fixed** — `Measure.inlineClefs` carries clef changes by onset; MusicXML imports first-measure and later inline clefs; layout draws the small clef at the current column and applies it to following notes. Regression in `musicxml_test.dart`. |
| G25 | medium (system engraving) | **staff-system SVG/PNG** | Staff/instrument labels (`Piano`) and line-start bar numbers (`5`, `8`, …) are present in the source/reference but not emitted by Partitura's staff-system renderers. | K545 Verovio vs Partitura SVG/PNG | **fixed** — wrapped staff systems preserve metadata/source breaks and emit a left margin with first-system instrument labels plus original measure numbers at following line starts in both SVG and Flutter PNG. Regression in `staff_system_systems_test.dart` / `musicxml_test.dart`. |
| G26 | medium (oracle parity) | **MusicXML visible-note oracle sweep** | Verovio oracle over the r15 MXL set reports mostly Verovio-only notes (1/8 exact: WTC Prelude only). The internal round-trip sweep remains 100% for notation formats, and K545 visual SVG/PNG is materially improved, so this is likely a mix of visible-note policy, repeats/alternate endings, and remaining importer under-read that needs per-file tracing. | `dart run tool/oracle_diff.dart --oracle verovio /Volumes/backups/ai/partitura-corpus/r15/source/*.mxl` | **open** — next step is a per-measure visible-note dump against Verovio for Canon/K545/Bach Minuet, separating true importer under-read from oracle expansion/repeat policy. |
| G27 | high (layout fidelity) | **multi-system slur slicing** | Slurs whose endpoints fell on different wrapped systems were dropped entirely by `_slice`, so long phrase marks in K545 disappeared even though MusicXML import had all 101 slurs. | K545 long phrase slurs across line breaks | **fixed** — `_slice` now turns cross-system slurs into visible start/end continuation segments anchored to visible notes on each affected line. It deliberately skips middle-only fake full-system arcs until the model has explicit continuation endpoints; those placeholder arcs caused severe overlap. Regression in `multi_system_test.dart`. |
| G28 | high (clef fidelity) | **MusicXML multi-staff defaults** | K545 omits an explicit initial staff-2 clef but later gives a staff-2 F clef mid-measure in bar 5. A blanket "staff 2 defaults to bass" fix suppressed that real clef change as redundant. | K545 opening / bar 5 lower staff | **fixed** — staff 2 still defaults to bass when no clef evidence exists, but a deferred first staff-specific clef means the preceding state remains treble so the later clef is rendered as a real inline change. Regression in `musicxml_test.dart`; probe shows staff 2 starts treble and bar 5 has `InlineClefChange(3/4, bass)`. |
| G29 | high (engraving) | **cross-staff slur placement** | K545 still exposes staff-system-aware engraving gaps: long phrase slurs in bars 37-40, 51-53 and 69-70 can occupy the neighboring staff's space because slurs are shaped inside a single-staff layout before the staff system knows about adjacent-staff ink. | K545 SVG/PNG overlap sweep | **open / mitigated** — dynamics are laid out before slurs; long slurs get denser sampled skyline clearance, deeper arches, and outside-staff endpoints; fake middle-only continuation arcs are skipped; bass-clef long phrase slurs prefer below; staff systems enlarge the inter-staff gap when adjacent staff ink would collide. This clears the concrete K545 neighboring-staff collisions in the r16 crop sweep, but the remaining full fix is still explicit slur placement/continuation metadata or a staff-system post-layout pass that can move/reshape slurs with knowledge of both staves. |
| G30 | medium (engraving) | **MusicXML words + multi-voice head collisions** | K545 exposed two smaller local engraving bugs: staff-2 `<words placement="below">legato</words>` was imported as an above-staff annotation and landed on staff lines; a simultaneous upper-staff whole note + 16ths in bar 25 shifted by black-notehead width only, so the noteheads overlapped. | K545 bars 13 and 25 | **fixed** — `Annotation` carries above/below placement, MusicXML words preserve/write it, below annotations clear the local bottom skyline; cross-voice collision shifts now use whole-note head width plus padding. Regressions in `annotation_test.dart`, `musicxml_test.dart`, `layout_more_test.dart`. |
| G31 | high (engraving) | **staff-system line breaking** | The greedy system packer estimated line width from measure widths, but a later justified/aligned staff-system layout could exceed `maxWidth`; K545 T57 and T70 overflowed the rendered page even though the estimate said they fit. | K545 SVG/PNG at `--width 120`, bars 57 and 70 | **fixed** — after rendering a candidate system, `layoutStaffSystemSystems` backs off measures until the actual laid-out width fits (unless a single measure itself is overwide). Regression is covered by the existing max-width packing tests plus the K545 r16 visual crop sweep. |

### G4 + G5 — fixed, and generalized
Root cause: **every** span/annotation layout pass threw on a degenerate span
(start == end / reversed) or a dangling note id. Any span whose other end is in a
dropped part (very common — see G2) crashed the whole render. Fix: **all** of the
~20 span passes (dynamics, hairpins, pedals, slurs, glissandos, portamentos,
laissez-vibrer, ottavas, trills, vibratos, lyrics, figured bass, breath marks,
jazz marks, chord diagrams) now **skip** a degenerate/dangling span and render
everything else — a renderer must never crash on real input. The
"fails-loudly" tests were updated to assert the new leniency. Verified: the two
crashers now render, core + Flutter suites green.

## Closing order (highest value first)
1. **G4 + G5** — never crash on a bad span (skip degenerate / dangling spans).
2. **G3** — handle `<slur type="continue">` in the MusicXML reader.
3. **G1** — embed the SMuFL metadata in the CLI so the released binary renders.
4. **G2** — folds into the C6 multi-part effort (other worktree).
