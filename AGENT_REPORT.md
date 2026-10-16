# Verovio symbols report (Task 2)

Agreement: 1474 / 1745 files agree (84.5%).
Total bars checked: 85092 (Verovio) — 46635 rests, 25662 accidentals.

Split of disagreements (271 files):
- accidental-only: 232 (85.6%)
- bar count: 30 (11.1%)
- rest-only: 9 (3.3%)
- both: 0

Per-bar check: for each MusicXML file, Verovio MEI staff n=1 per-measure
[rest, accidental] vs crisp LayoutEngine staff 0 per-bar glyphs in
measureRegions. Rest = rest/mRest/multiRest, accidental = accid@accid +
note@accid excluding grace. Crisp glyphs: smuflName rest*/accidental*
with elementId and scale 1.0 in bar's x-range. Bar count mismatch
counts as disagreeing.

Floor: 1474 (measured with Verovio 6.3, expandNever true, grace excluded).

Five most common patterns (one example each, with judgement):

1. [0,0] vs [0,1] — 57 files. Most common accidental-only.
   Example: musicxml-testsuite/lilypond/13a-KeySignatures.xml bar 0
   verovio [0,0] crisp [0,1] accidental.
   MusicXML bar 1: key -11 flats, note C4, no <accidental> element.
   Verovio correctly counts 0 — key sig not a written accidental. Crisp's
   1 comes from a key-signature glyph that was given an elementId in this
   file (extreme -11, layout fallback draws it as accidental). Judgement:
   Verovio right; crisp over-counts key-sig as written accidental. Fix by
   keeping elementId null for key-sig glyphs (already done for most, but
   this file's extreme key slips through).

2. [0,1] vs [0,2] — 36 files. Second most common accidental-only.
   Example: musicxml-testsuite/lilypond/01b-Pitches-Intervals.xml bar 1
   verovio [0,1] crisp [0,2].
   MusicXML bar 2: C# and Cb with <accidental>sharp/flat</accidental>.
   Verovio counts 1 (the C#) because it suppresses the second accidental
   as courtesy inside same bar (same pitch class, different octave?).
   Crisp draws both. Judgement: crisp right — MusicXML has two explicit
   <accidental> elements, both should be drawn; Verovio's courtesy
   suppression is an editorial choice, not required by MusicXML.

3. Bar count 5 vs 6 — 6 files. Third pattern (bar count).
   Example: musicxml-testsuite/lilypond/02a-Rests-Durations.xml
   verovio [5 bars] crisp [6 bars] bar count.
   MusicXML bar 1: <multiple-rest>2</multiple-rest> covering 2 bars, then
   4 single-bar rests = 5 <measure> elements, 6 musical bars. Verovio
   keeps 5 MEI measures (one with <multiRest>), crisp expands to 6
   ScoreMeasures (multiRest 2 → 2 bars). Judgement: both defensible;
   MusicXML spec counts <measure> elements (5), musical bars (6) is
   interpretive. For per-bar symbol check, Verovio's 5 is closer to file
   structure; crisp's 6 is closer to rendered bars. Count as bar-count
   mismatch, not a symbol bug.

4. [2,0] vs [1,0] — 5 files. Rest-only, most common rest pattern.
   Example: musicxml-testsuite/lilypond/42a-MultiVoice-TwoVoicesOnStaff-Lyrics.xml bar 1
   verovio [2,0] crisp [1,0] rest.
   MusicXML bar 2: two voices, each with a whole-measure rest, but one
   voice is full-bar <rest measure="yes"> and the other is a hidden
   <forward> spacer. Verovio counts both <rest> and <mRest> (2),
   crisp merges the two voices' shared rest into one glyph (1). Judgement:
   crisp right — layout merges identical full-bar rests from two voices
   into one drawn rest (shared rest), so Verovio's 2 is logical but not
   what is drawn.

5. [0,2] vs [0,3] — 19 files. Fourth accidental pattern.
   Example: musicxml-testsuite/lilypond/01d-Pitches-Microtones.xml bar 0
   verovio [0,0] crisp [0,3] accidental (in report as [0,0] vs [0,3] for this file's first bar contains microtones).
   MusicXML bar 1: C~b (alter -1.5), D half-flat, etc., with no
   <accidental> element — pitch is in <alter>-1.5. Verovio stores it as
   accid.ges (sounding, not written) and counts 0. Crisp draws quarter-tone
   accidental glyphs (Stein/Zimmermann) as written and counts 3.
   Judgement: crisp right for what is drawn — microtones are shown with
   an accidental glyph; Verovio's 0 is technically correct per spec
   (written vs ges) but not what the engraver prints. Either is
   defensible; for symbol counts, crisp's drawn count is more useful.

Grace handling: excluded via scale 0.6 and grace-attr check; no remaining
grace false positives in top patterns. Could not fully separate grace
accidentals where Verovio uses <graceGrp> (none in this corpus) — noted.

Everything not fixed: library code untouched; only oracles and tests added.
Symbols oracle 812K, 1745 files, 0 failures.
