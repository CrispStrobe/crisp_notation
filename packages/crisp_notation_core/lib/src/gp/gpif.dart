/// GPIF (`score.gpif`) import/export.
///
/// GPIF is the XML document at the heart of the `.gpx`/`.gp` (v6/7/8) file
/// formats (`.gpx` is a compressed container, `.gp` a zip — both hold a
/// `score.gpif`).
/// This is a **subset** codec, pure Dart (web-safe): it reads/writes the
/// GPIF document structure — track tuning, master bars, bars → voices → beats →
/// notes (string+fret), rhythms and the common playing techniques — into a
/// crisp_notation [Score]. On **import**, hammer-on/pull-off (`HopoOrigin`) → a
/// slur, slides (`Slide`) → a glissando, bends (`Bended`; a plain
/// `BendDestinationValue` where 100 = a whole step, or an origin/middle/
/// destination contour) → a `Bend`, normal (`Vibrato`) and whammy
/// (`VibratoWTremBar`) vibrato → a `Vibrato` (`wide` for the latter), dead
/// (`Muted`), ghost (`Ghost`) and harmonic (`Harmonic`, with `HarmonicType`
/// natural/artificial/pinch/tap/semi/feedback) notes → `TabNoteMark`s; export
/// writes the same properties back, so a round-trip keeps techniques. A bend
/// contour keeps its endpoints and first interior point; contours with more
/// than one interior point reduce to that first middle.
/// Multi-track files import one track at a time (`trackIndex`; see
/// [gpifTrackNames]) and export from a [MultiPartScore] one track per part
/// (`multiPartToGpif`, each track with its own tuning). It reads real `.gp` (v7) files correctly — validated
/// against the vendored `.gp` (v7) fixtures (pitches, chords, rhythm,
/// techniques, multi-track; fixture provenance in
/// `crisp_notation_cli/test/data/gp/README.md`).
///
/// The GPIF vocabulary here is the format's own XML tag set (factual); the
/// parsing and mapping code is original — not derived from any decoder's
/// source. The zip/`.gp` container wrapping lives in
/// `interchange/gp_container.dart` (web-safe); this module works on the
/// `score.gpif` XML string directly.
library;

import '../layout/multi_part.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../musicxml/xml_reader.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';
import '../theory/tuning.dart';

const _noteValues = {
  DurationBase.whole: 'Whole',
  DurationBase.half: 'Half',
  DurationBase.quarter: 'Quarter',
  DurationBase.eighth: 'Eighth',
  DurationBase.sixteenth: '16th',
  DurationBase.thirtySecond: '32nd',
  DurationBase.sixtyFourth: '64th',
};
final _basesByName = {for (final e in _noteValues.entries) e.value: e.key};

// GPIF's `<Dynamic>` vocabulary (PPP…FFF); exotic levels (sf, fp, …) have no
// GPIF equivalent and are simply not written.
const _gpDynamics = <DynamicLevel, String>{
  DynamicLevel.ppp: 'PPP',
  DynamicLevel.pp: 'PP',
  DynamicLevel.p: 'P',
  DynamicLevel.mp: 'MP',
  DynamicLevel.mf: 'MF',
  DynamicLevel.f: 'F',
  DynamicLevel.ff: 'FF',
  DynamicLevel.fff: 'FFF',
};
final _dynamicFromGp = {for (final e in _gpDynamics.entries) e.value: e.key};

/// An explicit fretboard placement for one part: `element id → {string index:
/// fret}` (string 0 = the top tab line, matching a [Tuning]'s string order; an
/// empty inner map is a silent element). Pass it to [scoreToGpif] /
/// [multiPartToGpif] to honour a real tab arranger's per-note choices; any
/// [NoteElement] whose `id` is absent from the map falls back to the greedy
/// per-pitch [Tuning.fretFor].
typedef GpFretPlan = Map<String, Map<int, int>>;

/// Serializes [score] to a `score.gpif` XML string, fretting its pitches on
/// [tuning] (default standard guitar). Notes unreachable on the tuning are
/// dropped. A bar's **voice 2** is written as a second GPIF voice (and read back
/// into `Measure.voice2`), so a two-voice staff round-trips. **Tuplets**
/// (`<PrimaryTuplet>`), the **key signature** (incl. mid-score changes) and
/// **dynamics** (PPP…FFF) round-trip too. Tab techniques (bends and bend
/// contours, hammer-on/pull-off, slides, normal/wide vibrato, dead/ghost/harmonic
/// marks) are written as GPIF note properties, so a `.gp` round-trip keeps them.
///
/// [frettings] optionally supplies an explicit arrangement (see [GpFretPlan]):
/// its `{string: fret}` per element wins over [Tuning.fretFor], so an external
/// arranger's fret choices reach the `.gp` instead of being re-derived.
String scoreToGpif(Score score, {Tuning? tuning, GpFretPlan? frettings}) =>
    _writeGpif([score], [tuning ?? Tuning.standardGuitar], const ['Guitar'],
        frettings: [frettings]);

/// Serializes an N-part [score] to a `score.gpif` XML string with **one GPIF
/// track per part**, so a whole band (guitar + bass + …) survives an export.
///
/// Each track frets its part's pitches on its own tuning — `tunings[i]`,
/// falling back to [Tuning.standardGuitar] when the list is absent or shorter
/// than [MultiPartScore.parts] — and gets its own `<Staff>` `Tuning`
/// `<Pitches>`. `names[i]` overrides the track name (defaults to the part's
/// `metadata.instrument`, else `Track n`). Every technique [scoreToGpif]
/// writes (bends and bend contours, hammer-on/pull-off, slides, vibrato,
/// dead/ghost/harmonic marks) is written per track.
///
/// The parts share one `<MasterBars>` list — GPIF's master bars carry the
/// meter for the whole document and each one references **one `<Bar>` id per
/// track**, in track order — so the output round-trips through
/// [scoreFromGpif] at any `trackIndex`. The meter comes from the first part;
/// parts shorter than the longest one are padded with empty bars so the
/// per-track bar lists stay aligned.
/// [frettings] optionally supplies one [GpFretPlan] per part (index-aligned to
/// [MultiPartScore.parts]; a null or missing entry frets that part via
/// [Tuning.fretFor]).
String multiPartToGpif(MultiPartScore score,
    {List<Tuning>? tunings,
    List<String>? names,
    List<GpFretPlan?>? frettings}) {
  final parts = score.parts;
  return _writeGpif(
    parts,
    [
      for (var i = 0; i < parts.length; i++)
        (tunings != null && i < tunings.length)
            ? tunings[i]
            : Tuning.standardGuitar,
    ],
    [
      for (var i = 0; i < parts.length; i++)
        (names != null && i < names.length)
            ? names[i]
            : (parts[i].metadata.instrument ?? 'Track ${i + 1}'),
    ],
    frettings: frettings,
  );
}

/// The shared writer core: one `<Track>` per entry of [parts], fretted on the
/// matching [tunings] entry and labelled with the matching [names] entry.
String _writeGpif(List<Score> parts, List<Tuning> tunings, List<String> names,
    {List<GpFretPlan?>? frettings}) {
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<GPIF>');
  b.writeln('  <GPVersion>7</GPVersion>');
  b.writeln('  <Score><Title>crisp_notation</Title></Score>');
  final tracks = StringBuffer();
  for (var t = 0; t < parts.length; t++) {
    tracks.write('<Track id="$t"><Name>${_escape(names[t])}</Name>'
        '<Staves><Staff>'
        '<Properties><Property name="Tuning"><Pitches>'
        '${tunings[t].strings.map((p) => p.midiNumber).join(' ')}'
        '</Pitches></Property></Properties></Staff></Staves></Track>');
  }
  b.writeln('  <Tracks>$tracks</Tracks>');

  final masterBars = StringBuffer();
  final bars = StringBuffer();
  final voices = StringBuffer();
  final beats = StringBuffer();
  final notes = StringBuffer();
  final rhythms = StringBuffer();

  // Rhythms are de-duplicated by (base, dots, tuplet) across every track.
  final rhythmId = <String, int>{};
  int rhythmFor(NoteDuration d, {int? tupActual, int? tupNormal}) {
    final name = _noteValues[d.base];
    if (name == null) return -1;
    final key = '$name.${d.dots}.${tupActual ?? 0}:${tupNormal ?? 0}';
    return rhythmId.putIfAbsent(key, () {
      final id = rhythmId.length;
      rhythms.write('    <Rhythm id="$id"><NoteValue>$name</NoteValue>');
      for (var i = 0; i < d.dots; i++) {
        rhythms.write('<AugmentationDot/>');
      }
      if (tupActual != null && tupNormal != null) {
        rhythms.write('<PrimaryTuplet><Num>$tupActual</Num>'
            '<Den>$tupNormal</Den></PrimaryTuplet>');
      }
      rhythms.writeln('</Rhythm>');
      return id;
    });
  }

  // Ids are global across tracks; a MasterBar then lists this bar's id per
  // track, in track order.
  var barId = 0;
  var voiceId = 0;
  var beatId = 0;
  var noteId = 0;
  var measureCount = 0;
  for (final part in parts) {
    if (part.measures.length > measureCount) {
      measureCount = part.measures.length;
    }
  }
  // barIdsPerMeasure[m] = the bar id each track uses for measure m.
  final barIdsPerMeasure = [for (var m = 0; m < measureCount; m++) <int>[]];

  for (var t = 0; t < parts.length; t++) {
    final score = parts[t];
    final tune = tunings[t];
    final plan =
        (frettings != null && t < frettings.length) ? frettings[t] : null;
    // A note's pinned string placement, if the score carries one (a tab editor
    // records the arranger's per-pitch string choice as a TabVoicing). Used to
    // honour those strings on export instead of re-deriving with fretFor.
    final voicingBy = {for (final v in score.tabVoicings) v.noteId: v.strings};
    // Per-note technique lookups (a span is written on its start note).
    final hopoFrom = {for (final s in score.slurs) s.startId};
    final slideFrom = {for (final g in score.glissandos) g.startId};
    final bendBy = {for (final bend in score.bends) bend.noteId: bend};
    final vibratoWideBy = {for (final v in score.vibratos) v.noteId: v.wide};
    final markBy = {for (final m in score.tabNoteMarks) m.noteId: m.style};
    final dynamicBy = {for (final d in score.dynamics) d.elementId: d.level};

    // Emit one GPIF voice from [els] (a bar's voice-1 or voice-2 stream) into
    // the shared beat/note buffers; returns the beat ids to reference.
    List<int> emitVoice(Iterable<MusicElement> els, List<TupletSpan> tuplets) {
      final beatRefs = <int>[];
      final list = els is List<MusicElement> ? els : els.toList();
      for (var idx = 0; idx < list.length; idx++) {
        final element = list[idx];
        // Grace notes become GPIF grace beats (one per pitch, in order) right
        // before their main beat, marked <GraceNotes>BeforeBeat</GraceNotes>.
        if (element is NoteElement && element.graceNotes.isNotEmpty) {
          final grid = rhythmFor(const NoteDuration(DurationBase.eighth));
          for (final g in element.graceNotes) {
            final place = tune.fretFor(g);
            if (place == null) continue;
            notes.writeln('    <Note id="$noteId"><Properties>'
                '<Property name="String"><String>${place.$1}</String></Property>'
                '<Property name="Fret"><Fret>${place.$2}</Fret></Property>'
                '</Properties></Note>');
            beats.writeln('    <Beat id="$beatId"><Rhythm ref="$grid"/>'
                '<GraceNotes>BeforeBeat</GraceNotes>'
                '<Notes>$noteId</Notes></Beat>');
            noteId++;
            beatRefs.add(beatId++);
          }
        }
        final span = tuplets.where((t) => t.contains(idx));
        final rid = span.isEmpty
            ? rhythmFor(element.duration)
            : rhythmFor(element.duration,
                tupActual: span.first.actual, tupNormal: span.first.normal);
        if (rid < 0) continue;
        final noteRefs = <int>[];
        if (element is NoteElement) {
          final eid = element.id;
          // An explicit arrangement (id-keyed `{string: fret}`) wins; otherwise
          // fret each pitch greedily on the tuning. Emitting the lowest string
          // first keeps the note order deterministic (and byte-identical to the
          // fret-from-pitch path when no plan is supplied).
          final planned = eid == null ? null : plan?[eid];
          final voicing = eid == null ? null : voicingBy[eid];
          final placements = <(int, int)>[];
          if (planned != null) {
            for (final s in planned.keys.toList()..sort()) {
              placements.add((s, planned[s]!));
            }
          } else {
            // The score may pin each pitch to a string (a tab arranger's
            // choice); recover the fret from the open-string pitch. A null
            // result (voicing absent, wrong length, or not fitting this tuning)
            // falls back to the greedy fretFor.
            final derived =
                (voicing != null && voicing.length == element.pitches.length)
                    ? _fretsFromVoicing(element.pitches, voicing, tune)
                    : null;
            if (derived != null) {
              placements.addAll(derived);
            } else {
              for (final pitch in element.pitches) {
                final place = tune.fretFor(pitch);
                if (place != null) placements.add(place);
              }
            }
          }
          var first = true;
          for (final place in placements) {
            final props = StringBuffer(
                '<Property name="String"><String>${place.$1}</String></Property>'
                '<Property name="Fret"><Fret>${place.$2}</Fret></Property>');
            // Element-level techniques go on the first sounding note.
            if (first && eid != null) {
              if (hopoFrom.contains(eid)) {
                props.write('<Property name="HopoOrigin"><Enable/></Property>');
              }
              if (slideFrom.contains(eid)) {
                props.write(
                    '<Property name="Slide"><Flags>2</Flags></Property>');
              }
              final bend = bendBy[eid];
              if (bend != null) {
                props.write('<Property name="Bended"><Enable/></Property>');
                if (bend.points.isEmpty) {
                  props.write('<Property name="BendDestinationValue"><Float>'
                      '${(bend.steps * 100).toStringAsFixed(6)}</Float></Property>');
                } else {
                  // A multi-point contour → GPIF's origin / (optional) middle /
                  // destination points, values in 1/100 whole-tone, offsets in
                  // 0..100 along the note. A single middle point is emitted with
                  // its offset repeated for both plateau edges; contours with
                  // more than one interior point reduce to their first middle.
                  _writeBendPoint(props, 'Origin', bend.points.first);
                  final middles =
                      bend.points.sublist(1, bend.points.length - 1);
                  if (middles.isNotEmpty) {
                    props.write('<Property name="BendMiddleValue"><Float>'
                        '${(middles.first.steps * 100).toStringAsFixed(6)}'
                        '</Float></Property>');
                    final off = (middles.first.offset * 100).toStringAsFixed(6);
                    props.write('<Property name="BendMiddleOffset1"><Float>$off'
                        '</Float></Property>'
                        '<Property name="BendMiddleOffset2"><Float>$off'
                        '</Float></Property>');
                  }
                  _writeBendPoint(props, 'Destination', bend.points.last);
                }
              }
              final wide = vibratoWideBy[eid];
              if (wide != null) {
                props.write(wide
                    ? '<Property name="VibratoWTremBar"><Enable/></Property>'
                    : '<Property name="Vibrato"><Enable/></Property>');
              }
              if (markBy[eid] == TabNoteStyle.ghost) {
                props.write('<Property name="Ghost"><Enable/></Property>');
              }
              switch (markBy[eid]) {
                case TabNoteStyle.dead:
                  props.write('<Property name="Muted"><Enable/></Property>');
                case TabNoteStyle.harmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Natural</HType></Property>');
                case TabNoteStyle.artificialHarmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Artificial</HType></Property>');
                case TabNoteStyle.pinchHarmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Pinch</HType></Property>');
                case TabNoteStyle.tappedHarmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Tap</HType></Property>');
                case TabNoteStyle.semiHarmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Semi</HType></Property>');
                case TabNoteStyle.feedbackHarmonic:
                  props.write('<Property name="Harmonic"><Enable/></Property>'
                      '<Property name="HarmonicType">'
                      '<HType>Feedback</HType></Property>');
                case TabNoteStyle.ghost:
                case null:
                  break;
              }
            }
            // Articulations (element-level) go on the first sounding note.
            if (first) {
              if (element.articulations.contains(Articulation.staccato)) {
                props.write('<Property name="Staccato"><Enable/></Property>');
              }
              if (element.articulations.contains(Articulation.accent)) {
                props.write('<Property name="Accent"><Enable/></Property>');
              }
            }
            notes.writeln('    <Note id="$noteId"><Properties>$props'
                '</Properties></Note>');
            noteRefs.add(noteId++);
            first = false;
          }
        }
        beats.write('    <Beat id="$beatId"><Rhythm ref="$rid"/>');
        final dyn = element.id == null ? null : dynamicBy[element.id];
        final dynGp = dyn == null ? null : _gpDynamics[dyn];
        if (dynGp != null) beats.write('<Dynamic>$dynGp</Dynamic>');
        if (noteRefs.isNotEmpty) {
          beats.write('<Notes>${noteRefs.join(' ')}</Notes>');
        } else {
          beats.write('<Rest/>');
        }
        beats.writeln('</Beat>');
        beatRefs.add(beatId++);
      }
      return beatRefs;
    }

    for (var m = 0; m < measureCount; m++) {
      final measure = m < score.measures.length ? score.measures[m] : null;
      final bid = barId++;
      barIdsPerMeasure[m].add(bid);

      final vid1 = voiceId++;
      final v1Refs = emitVoice(measure?.elements ?? const <MusicElement>[],
          measure?.tupletsForVoice(0) ?? const <TupletSpan>[]);
      voices.writeln(
          '    <Voice id="$vid1"><Beats>${v1Refs.join(' ')}</Beats></Voice>');

      // A second GPIF voice when the part carries voice 2 (polyphonic staff).
      var vid2 = -1;
      final v2 = measure?.voice2 ?? const <MusicElement>[];
      if (v2.isNotEmpty) {
        vid2 = voiceId++;
        final v2Refs =
            emitVoice(v2, measure?.tupletsForVoice(1) ?? const <TupletSpan>[]);
        voices.writeln(
            '    <Voice id="$vid2"><Beats>${v2Refs.join(' ')}</Beats></Voice>');
      }
      bars.writeln(
          '    <Bar id="$bid"><Voices>$vid1 $vid2 -1 -1</Voices></Bar>');
    }
  }

  // The meter lives on the master bars, which the tracks share; take it from
  // the first part.
  final lead = parts.first;
  // Track the meter in force so an unchanged bar re-states the RUNNING meter,
  // not the document's initial one. Re-stamping `lead.timeSignature` on a bar
  // after a mid-score change (e.g. bar 3 of 4/4 → 3/4 → 3/4) made the reader
  // read back a spurious change (3/4 → 4/4). For a score with no changes the
  // running meter equals the initial meter on every bar, so the emitted bytes
  // are identical (the golden test is unaffected).
  TimeSignature? running;
  // The key signature is emitted only when it changes from the previous bar
  // (GPIF's default is no accidentals), so a C-major score emits none and the
  // golden bytes are unaffected. `<AccidentalCount>` is the signed fifths count.
  var prevFifths = 0;
  KeySignature? runKey;
  for (var m = 0; m < measureCount; m++) {
    final measure = m < lead.measures.length ? lead.measures[m] : null;
    final ts = measure?.timeChange ?? running ?? lead.timeSignature;
    if (ts != null) running = ts;
    final key = measure?.keyChange ?? runKey ?? lead.keySignature;
    runKey = key;
    final keyXml = key.fifths != prevFifths
        ? '<Key><AccidentalCount>${key.fifths}</AccidentalCount></Key>'
        : '';
    prevFifths = key.fifths;
    masterBars.writeln('    <MasterBar>${ts == null ? '' : '<Time>'
            '${ts.beats}/${ts.beatUnit}</Time>'}$keyXml'
        '<Bars>${barIdsPerMeasure[m].join(' ')}</Bars></MasterBar>');
  }

  b.writeln('  <MasterBars>');
  b.write(masterBars);
  b.writeln('  </MasterBars>');
  b.writeln('  <Bars>');
  b.write(bars);
  b.writeln('  </Bars>');
  b.writeln('  <Voices>');
  b.write(voices);
  b.writeln('  </Voices>');
  b.writeln('  <Beats>');
  b.write(beats);
  b.writeln('  </Beats>');
  b.writeln('  <Notes>');
  b.write(notes);
  b.writeln('  </Notes>');
  b.writeln('  <Rhythms>');
  b.write(rhythms);
  b.writeln('  </Rhythms>');
  b.writeln('</GPIF>');
  return b.toString();
}

/// Recovers `(string, fret)` placements from a [TabVoicing]'s per-pitch string
/// choices: `fret = pitch − open-string`. Returns null if any pitch doesn't sit
/// on its pinned string within `[0, 24]` (a voicing inconsistent with [tune]),
/// so the caller falls back to [Tuning.fretFor].
List<(int, int)>? _fretsFromVoicing(
    List<Pitch> pitches, List<int> strings, Tuning tune) {
  final out = <(int, int)>[];
  for (var i = 0; i < pitches.length; i++) {
    final s = strings[i];
    if (s < 0 || s >= tune.strings.length) return null;
    final fret = pitches[i].midiNumber - tune.strings[s].midiNumber;
    if (fret < 0 || fret > 24) return null;
    out.add((s, fret));
  }
  return out;
}

/// Escapes the XML text characters that can appear in a track name.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// Writes a GPIF bend [which] ('Origin' or 'Destination') point: value in
/// 1/100 whole-tone, offset in 0..100 along the note's duration.
void _writeBendPoint(StringBuffer props, String which, BendPoint point) {
  props.write('<Property name="Bend${which}Value"><Float>'
      '${(point.steps * 100).toStringAsFixed(6)}</Float></Property>'
      '<Property name="Bend${which}Offset"><Float>'
      '${(point.offset * 100).toStringAsFixed(6)}</Float></Property>');
}

/// The names of the tracks in a GPIF document, in order (for choosing a
/// [trackIndex] to import).
List<String> gpifTrackNames(String gpif) {
  final root = parseXml(gpif);
  return [
    for (final t
        in root.child('Tracks')?.childrenNamed('Track') ?? const <XmlNode>[])
      t.childText('Name') ?? 'Track',
  ];
}

/// Parses a `.gpif` document into a [MultiPartScore] — every `<Track>` as its
/// own part (the single-track `scoreFromGpif` read one [trackIndex]).
MultiPartScore multiPartScoreFromGpif(String gpif) {
  final n = gpifTrackNames(gpif).length;
  return MultiPartScore([
    for (var t = 0; t < (n == 0 ? 1 : n); t++)
      scoreFromGpif(gpif, trackIndex: t),
  ]);
}

/// Parses a `score.gpif` XML string into a [Score] — the [trackIndex]-th track
/// (default 0), voice 0.
///
/// Throws [FormatException] on malformed or unsupported GPIF.
Score scoreFromGpif(String gpif, {int trackIndex = 0}) {
  final root = parseXml(gpif);
  if (root.name != 'GPIF') {
    throw const FormatException('not a GPIF document');
  }

  // The chosen track's tuning → MIDI numbers (in the file's string order). The
  // tuning property lives on the staff.
  final tracks =
      root.child('Tracks')?.childrenNamed('Track').toList() ?? const [];
  final track =
      tracks.isEmpty ? null : tracks[trackIndex.clamp(0, tracks.length - 1)];
  final staff = track?.child('Staves')?.child('Staff');
  final tuningText = _findProperty(staff, 'Tuning')?.childText('Pitches');
  final tuningMidi = (tuningText ?? '64 59 55 50 45 40')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty)
      .map(int.parse)
      .toList();

  final barById = _byId(root.child('Bars'), 'Bar');
  final voiceById = _byId(root.child('Voices'), 'Voice');
  final beatById = _byId(root.child('Beats'), 'Beat');
  final noteById = _byId(root.child('Notes'), 'Note');
  final rhythmById = _byId(root.child('Rhythms'), 'Rhythm');

  final measures = <Measure>[];
  final bends = <Bend>[];
  final vibratos = <Vibrato>[];
  final marks = <TabNoteMark>[];
  final dynamics = <DynamicMarking>[];
  final slurs = <Slur>[]; // hammer-on / pull-off
  final glissandos = <Glissando>[]; // slides
  // HO/PO + slide spans waiting for their destination note, one pair per voice
  // lane ([0] = hopo id, [1] = slide id) so voice 1 and voice 2 don't cross.
  final pend1 = <String?>[null, null];
  final pend2 = <String?>[null, null];
  var id = 0;
  TimeSignature? firstTime;
  TimeSignature? runningTime; // the meter in force, for mid-score changes
  int? firstFifths;
  var runningFifths = 0; // the key in force (signed fifths), for changes

  for (final masterBar
      in root.child('MasterBars')?.children ?? const <XmlNode>[]) {
    if (masterBar.name != 'MasterBar') continue;
    final time = masterBar.childText('Time');
    final barTime = time == null ? null : _parseTime(time);
    firstTime ??= barTime;
    // The key signature (signed fifths); a bar carrying a different one is a
    // mid-score key change.
    final barFifths = int.tryParse(
        masterBar.child('Key')?.childText('AccidentalCount') ?? '');
    firstFifths ??= barFifths;
    final KeySignature? keyChange =
        (barFifths != null && barFifths != runningFifths)
            ? KeySignature(barFifths)
            : null;
    if (barFifths != null) runningFifths = barFifths;
    // A bar whose meter differs from the running one carries a mid-score change
    // (the writer emits <Time> on every MasterBar, so a change is a difference).
    final TimeSignature? timeChange =
        (barTime != null && runningTime != null && barTime != runningTime)
            ? barTime
            : null;
    if (barTime != null) runningTime = barTime;

    // A MasterBar lists one bar id per track; pick this track's.
    final barIds = _ints(masterBar.childText('Bars'));
    if (barIds.isEmpty) continue;
    final barRef = trackIndex < barIds.length ? barIds[trackIndex] : barIds[0];
    final bar = barById[barRef];
    final voiceIds = _ints(bar?.childText('Voices'));
    // Read the bar's voices (lane 0 → this measure's elements, lane 1 → voice 2).
    final positive = voiceIds.where((v) => v >= 0).toList();
    final laneElements = <List<MusicElement>>[];
    final measureTuplets = <TupletSpan>[];
    for (var lane = 0; lane < positive.length && lane < 2; lane++) {
      final voice = voiceById[positive[lane]];
      final pend = lane == 0 ? pend1 : pend2;
      final elements = <MusicElement>[];
      // One entry per element: its tuplet ratio (num, den) or null. Consecutive
      // same-ratio beats are grouped into a TupletSpan after the loop.
      final tupRatios = <(int, int)?>[];
      // Grace-note pitches read from grace beats, waiting for their main note.
      final pendingGraces = <Pitch>[];
      for (final beatRef in _ints(voice?.childText('Beats'))) {
        final beat = beatById[beatRef];
        if (beat == null) continue;
        final rhythmRef =
            int.tryParse(beat.child('Rhythm')?.attributes['ref'] ?? '');
        final duration = _durationOf(rhythmById[rhythmRef]);
        if (duration == null) continue;
        // A grace beat contributes its pitch(es) to the next real note, not a
        // timed element of its own.
        if (beat.childText('GraceNotes') != null) {
          for (final noteRef in _ints(beat.childText('Notes'))) {
            final note = noteById[noteRef];
            final string = int.tryParse(
                _findProperty(note, 'String')?.childText('String') ?? '');
            final fret = int.tryParse(
                _findProperty(note, 'Fret')?.childText('Fret') ?? '');
            if (string != null && fret != null && string < tuningMidi.length) {
              pendingGraces.add(_pitchFromMidi(tuningMidi[string] + fret));
            }
          }
          continue;
        }
        tupRatios.add(_tupletOf(rhythmById[rhythmRef]));

        final noteRefs = _ints(beat.childText('Notes'));
        if (noteRefs.isEmpty) {
          elements.add(RestElement(duration, id: 'e${id++}'));
          continue;
        }
        final pitches = <Pitch>[];
        final nodes = <XmlNode>[];
        for (final noteRef in noteRefs) {
          final note = noteById[noteRef];
          if (note == null) continue;
          final string = int.tryParse(
              _findProperty(note, 'String')?.childText('String') ?? '');
          final fret = int.tryParse(
              _findProperty(note, 'Fret')?.childText('Fret') ?? '');
          if (string == null || fret == null || string >= tuningMidi.length) {
            continue;
          }
          pitches.add(_pitchFromMidi(tuningMidi[string] + fret));
          nodes.add(note);
        }
        if (pitches.isEmpty) {
          elements.add(RestElement(duration, id: 'e${id++}'));
          continue;
        }
        pitches.sort((a, b) => a.midiNumber.compareTo(b.midiNumber));
        final noteId = 'e${id++}';
        final arts = <Articulation>{};
        if (_propOn(beat, 'Staccato')) arts.add(Articulation.staccato);
        for (final note in nodes) {
          if (_propOn(note, 'Staccato')) arts.add(Articulation.staccato);
          if (_propOn(note, 'Accent')) arts.add(Articulation.accent);
        }
        elements.add(NoteElement(
          pitches: pitches,
          duration: duration,
          id: noteId,
          articulations: arts,
          graceNotes: List.of(pendingGraces),
        ));
        pendingGraces.clear();

        final dyn = _dynamicFromGp[beat.childText('Dynamic')];
        if (dyn != null) dynamics.add(DynamicMarking(noteId, dyn));

        // Playing techniques → crisp_notation's tab marks. Spans (HO/PO, slide)
        // connect this note to the previous one that opened them.
        final hopoFrom = pend[0];
        if (hopoFrom != null) {
          slurs.add(Slur(hopoFrom, noteId));
          pend[0] = null;
        }
        final slideFrom = pend[1];
        if (slideFrom != null) {
          glissandos.add(Glissando(slideFrom, noteId));
          pend[1] = null;
        }
        var dead = false,
            harmonic = false,
            vibrato = false,
            vibratoWide = false;
        var ghost = false;
        var harmonicStyle = TabNoteStyle.harmonic;
        double? bendSteps;
        List<BendPoint>? bendCurve;
        // Whammy-bar vibrato is a beat property.
        if (_propOn(beat, 'VibratoWTremBar')) {
          vibrato = true;
          vibratoWide = true;
        }
        for (final note in nodes) {
          if (_propOn(note, 'Muted')) dead = true;
          if (_propOn(note, 'Ghost')) ghost = true;
          if (_propOn(note, 'Harmonic')) {
            harmonic = true;
            harmonicStyle = switch (
                _findProperty(note, 'HarmonicType')?.childText('HType')) {
              'Artificial' => TabNoteStyle.artificialHarmonic,
              'Pinch' => TabNoteStyle.pinchHarmonic,
              'Tap' => TabNoteStyle.tappedHarmonic,
              'Semi' => TabNoteStyle.semiHarmonic,
              'Feedback' => TabNoteStyle.feedbackHarmonic,
              _ => TabNoteStyle.harmonic,
            };
          }
          if (_propOn(note, 'HopoOrigin')) pend[0] = noteId;
          if (_propOn(note, 'Slide')) pend[1] = noteId;
          if (_propOn(note, 'Vibrato')) vibrato = true;
          if (_propOn(note, 'VibratoWTremBar')) {
            vibrato = true;
            vibratoWide = true;
          }
          if (_propOn(note, 'Bended')) {
            final origin =
                _findProperty(note, 'BendOriginValue')?.childText('Float');
            if (origin != null) {
              // A contour: origin, an optional middle, and the destination.
              double read(String name, double fallback) =>
                  (double.tryParse(
                          _findProperty(note, name)?.childText('Float') ??
                              '') ??
                      fallback) /
                  100;
              final points = <BendPoint>[
                BendPoint(
                    read('BendOriginOffset', 0), read('BendOriginValue', 0)),
              ];
              if (_findProperty(note, 'BendMiddleValue') != null) {
                points.add(BendPoint(
                    read('BendMiddleOffset1', 50), read('BendMiddleValue', 0)));
              }
              points.add(BendPoint(read('BendDestinationOffset', 100),
                  read('BendDestinationValue', 0)));
              bendCurve ??= points;
            } else {
              final bv = _findProperty(note, 'BendDestinationValue')
                  ?.childText('Float');
              if (bv != null) {
                final v = (double.tryParse(bv) ?? 0) / 100;
                if (bendSteps == null || v > bendSteps) bendSteps = v;
              }
            }
          }
        }
        if (harmonic) {
          marks.add(TabNoteMark(noteId, harmonicStyle));
        } else if (dead) {
          marks.add(TabNoteMark(noteId, TabNoteStyle.dead));
        } else if (ghost) {
          marks.add(TabNoteMark(noteId, TabNoteStyle.ghost));
        }
        if (bendCurve != null) {
          bends.add(Bend.curve(noteId, bendCurve));
        } else if (bendSteps != null && bendSteps > 0) {
          bends.add(Bend(noteId, steps: bendSteps));
        }
        if (vibrato) vibratos.add(Vibrato(noteId, wide: vibratoWide));
      }
      laneElements.add(elements);
      measureTuplets.addAll(_groupTuplets(tupRatios, lane));
    }
    measures.add(Measure(
      laneElements.isNotEmpty ? laneElements[0] : const <MusicElement>[],
      voice2:
          laneElements.length > 1 ? laneElements[1] : const <MusicElement>[],
      tuplets: measureTuplets,
      timeChange: timeChange,
      keyChange: keyChange,
    ));
  }

  if (measures.isEmpty) {
    measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
  }
  return Score(
    clef: Clef.treble,
    timeSignature: firstTime,
    keySignature: KeySignature(firstFifths ?? 0),
    measures: measures,
    slurs: slurs,
    glissandos: glissandos,
    bends: bends,
    vibratos: vibratos,
    tabNoteMarks: marks,
    dynamics: dynamics,
  );
}

/// Whether a note carries the boolean property [name] (present, not disabled).
bool _propOn(XmlNode? note, String name) {
  final p = _findProperty(note, name);
  return p != null && p.child('Disable') == null;
}

Map<int, XmlNode> _byId(XmlNode? parent, String childName) => {
      for (final node in parent?.childrenNamed(childName) ?? const <XmlNode>[])
        if (int.tryParse(node.attributes['id'] ?? '') case final int id)
          id: node,
    };

XmlNode? _findProperty(XmlNode? node, String name) {
  for (final p in node?.child('Properties')?.childrenNamed('Property') ??
      const <XmlNode>[]) {
    if (p.attributes['name'] == name) return p;
  }
  return null;
}

List<int> _ints(String? text) => (text ?? '')
    .split(RegExp(r'\s+'))
    .where((t) => t.isNotEmpty)
    .map((t) => int.tryParse(t) ?? -1)
    .toList();

NoteDuration? _durationOf(XmlNode? rhythm) {
  if (rhythm == null) return null;
  final base = _basesByName[rhythm.childText('NoteValue')];
  if (base == null) return null;
  final dots = rhythm.childrenNamed('AugmentationDot').length.clamp(0, 2);
  return NoteDuration(base, dots: dots);
}

/// The `(actual, normal)` ratio of a rhythm's `<PrimaryTuplet>`, or null.
(int, int)? _tupletOf(XmlNode? rhythm) {
  final t = rhythm?.child('PrimaryTuplet');
  if (t == null) return null;
  final actual = int.tryParse(t.childText('Num') ?? '');
  final normal = int.tryParse(t.childText('Den') ?? '');
  if (actual == null || normal == null || actual < 2 || normal < 1) return null;
  return (actual, normal);
}

/// Groups a per-element list of tuplet [ratios] into [TupletSpan]s — one per
/// maximal run of consecutive same-ratio elements, addressing [voice]. Timing is
/// preserved for any grouping; back-to-back tuplets of the same ratio merge into
/// one span (a visual-only difference, not a timing one).
List<TupletSpan> _groupTuplets(List<(int, int)?> ratios, int voice) {
  final spans = <TupletSpan>[];
  var start = -1;
  (int, int)? cur;
  void close(int end) {
    final c = cur;
    if (start >= 0 && c != null && end >= start) {
      spans.add(
          TupletSpan(start, end, actual: c.$1, normal: c.$2, voice: voice));
    }
    start = -1;
    cur = null;
  }

  for (var i = 0; i < ratios.length; i++) {
    final r = ratios[i];
    if (r == null) {
      close(i - 1);
    } else if (cur == null) {
      start = i;
      cur = r;
    } else if (r != cur) {
      close(i - 1);
      start = i;
      cur = r;
    }
  }
  close(ratios.length - 1);
  return spans;
}

TimeSignature _parseTime(String text) {
  final parts = text.split('/');
  return TimeSignature(int.parse(parts[0]), int.parse(parts[1]));
}

Pitch _pitchFromMidi(int key) {
  const table = [
    (Step.c, 0), (Step.c, 1), (Step.d, 0), (Step.d, 1), //
    (Step.e, 0), (Step.f, 0), (Step.f, 1), (Step.g, 0),
    (Step.g, 1), (Step.a, 0), (Step.a, 1), (Step.b, 0),
  ];
  final (step, alter) = table[key % 12];
  return Pitch(step, alter: alter, octave: key ~/ 12 - 1);
}
