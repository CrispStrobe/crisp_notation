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

## Round-trip fidelity (import ↔ export)

Beyond "does it crash?", we measure **how much survives** a write-then-read
round-trip — this exercises the importer *and* the exporter together and
quantifies parse fidelity. Two harnesses:

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
  | MusicXML | 100% (79/79) | 100.0% |
  | MEI | 100% (79/79) | 100.0% |
  | kern | 100% (79/79) | 100.0% |
  | MuseScore | 100% (79/79) | 100.0% |
  | ABC | 99% (78/79) | 99.9% |
  | MIDI | 32% (25/79) | 88.4% |

  MIDI's lower "exact" is **expected** — the multiset key includes duration, and
  MIDI re-notates dotted/tied rhythm; the committed test's sampled-sounding
  metric confirms MIDI keeps what sounds. A round-trip only proves reader+writer
  are **mutually consistent**; the external oracle (`tool/oracle_diff.*`) tests
  **correctness** against an independent parser.

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
| G11 | low (rhythm fidelity) | abc writer/reader | An ABC round-trip of a dense syncopated ragtime (Joplin *The Entertainer*) preserves **every pitch, note and measure** (520 notes / 955 pitches / 92 bars identical) but re-encodes a handful of sub-beat **durations** (some 1/16 / dotted-1/16 in broken rhythm come back as a different value). Found by `tool/roundtrip_sweep.dart` (99.9% note-preserved). | round-trip of `ScottJoplin_The_Entertainer.xml` through ABC | **open** — narrow: likely ABC broken-rhythm (`>`/`<`) or dotted-sixteenth encoding. No notes lost; low priority. |

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
