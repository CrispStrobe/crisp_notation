/// Guitar Pro GPIF (`score.gpif`) import/export.
///
/// GPIF is the XML document at the heart of the Guitar Pro 6/7/8 file formats
/// (`.gpx` is a compressed container, `.gp` a zip — both hold a `score.gpif`).
/// This is a **subset** codec, pure Dart (web-safe): it reads/writes the
/// reference structure — track tuning, master bars, bars → voices → beats →
/// notes (string+fret) and rhythms — into a partitura [Score]. Playing
/// techniques and multi-track scores are out of scope for now. It round-trips
/// partitura's own GPIF and reads real Guitar Pro 7 files correctly (validated
/// against the alphaTab GP7 test corpus — pitches, chords and rhythm come
/// through); playing techniques in those files are simply ignored.
///
/// The zip/`.gp` container wrapping lives in the CLI (it needs `dart:io`); this
/// module works on the `score.gpif` XML string directly.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../musicxml/xml_reader.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
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

/// Serializes [score] to a `score.gpif` XML string, fretting its pitches on
/// [tuning] (default standard guitar). Notes unreachable on the tuning are
/// dropped. Voice 2 is ignored (single voice per bar).
String scoreToGpif(Score score, {Tuning? tuning}) {
  final tune = tuning ?? Tuning.standardGuitar;
  final b = StringBuffer();
  b.writeln('<?xml version="1.0" encoding="UTF-8"?>');
  b.writeln('<GPIF>');
  b.writeln('  <GPVersion>7</GPVersion>');
  b.writeln('  <Score><Title>partitura</Title></Score>');
  b.writeln('  <Tracks><Track id="0"><Name>Guitar</Name><Staves><Staff>'
      '<Properties><Property name="Tuning"><Pitches>'
      '${tune.strings.map((p) => p.midiNumber).join(' ')}'
      '</Pitches></Property></Properties></Staff></Staves></Track></Tracks>');

  final masterBars = StringBuffer();
  final bars = StringBuffer();
  final voices = StringBuffer();
  final beats = StringBuffer();
  final notes = StringBuffer();
  final rhythms = StringBuffer();

  // Rhythms are de-duplicated by (base, dots).
  final rhythmId = <String, int>{};
  int rhythmFor(NoteDuration d) {
    final name = _noteValues[d.base];
    if (name == null) return -1;
    final key = '$name.${d.dots}';
    return rhythmId.putIfAbsent(key, () {
      final id = rhythmId.length;
      rhythms.write('    <Rhythm id="$id"><NoteValue>$name</NoteValue>');
      for (var i = 0; i < d.dots; i++) {
        rhythms.write('<AugmentationDot/>');
      }
      rhythms.writeln('</Rhythm>');
      return id;
    });
  }

  var beatId = 0;
  var noteId = 0;
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    final ts = measure.timeChange ?? score.timeSignature;
    masterBars.writeln('    <MasterBar>${ts == null ? '' : '<Time>'
        '${ts.beats}/${ts.beatUnit}</Time>'}<Bars>$m</Bars></MasterBar>');
    bars.writeln('    <Bar id="$m"><Voices>$m -1 -1 -1</Voices></Bar>');

    final beatRefs = <int>[];
    for (final element in measure.elements) {
      final rid = rhythmFor(element.duration);
      if (rid < 0) continue;
      final noteRefs = <int>[];
      if (element is NoteElement) {
        for (final pitch in element.pitches) {
          final place = tune.fretFor(pitch);
          if (place == null) continue;
          notes.writeln('    <Note id="$noteId"><Properties>'
              '<Property name="String"><String>${place.$1}</String></Property>'
              '<Property name="Fret"><Fret>${place.$2}</Fret></Property>'
              '</Properties></Note>');
          noteRefs.add(noteId++);
        }
      }
      beats.write('    <Beat id="$beatId"><Rhythm ref="$rid"/>');
      if (noteRefs.isNotEmpty) {
        beats.write('<Notes>${noteRefs.join(' ')}</Notes>');
      } else {
        beats.write('<Rest/>');
      }
      beats.writeln('</Beat>');
      beatRefs.add(beatId++);
    }
    voices.writeln('    <Voice id="$m"><Beats>${beatRefs.join(' ')}</Beats>'
        '</Voice>');
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

/// Parses a `score.gpif` XML string into a [Score] (track 0, voice 0).
///
/// Throws [FormatException] on malformed or unsupported GPIF.
Score scoreFromGpif(String gpif) {
  final root = parseXml(gpif);
  if (root.name != 'GPIF') {
    throw const FormatException('not a GPIF document');
  }

  // Track 0 tuning → MIDI numbers (in the file's string order). The tuning
  // property lives on the staff.
  final staff =
      root.child('Tracks')?.child('Track')?.child('Staves')?.child('Staff');
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
  var id = 0;
  TimeSignature? firstTime;

  for (final masterBar
      in root.child('MasterBars')?.children ?? const <XmlNode>[]) {
    if (masterBar.name != 'MasterBar') continue;
    final time = masterBar.childText('Time');
    if (time != null && firstTime == null) firstTime = _parseTime(time);

    final barIds = _ints(masterBar.childText('Bars'));
    if (barIds.isEmpty) continue;
    final bar = barById[barIds.first];
    final voiceIds = _ints(bar?.childText('Voices'));
    final voiceRef = voiceIds.firstWhere((v) => v >= 0, orElse: () => -1);
    final voice = voiceRef < 0 ? null : voiceById[voiceRef];

    final elements = <MusicElement>[];
    for (final beatRef in _ints(voice?.childText('Beats'))) {
      final beat = beatById[beatRef];
      if (beat == null) continue;
      final rhythmRef =
          int.tryParse(beat.child('Rhythm')?.attributes['ref'] ?? '');
      final duration = _durationOf(rhythmById[rhythmRef]);
      if (duration == null) continue;

      final noteRefs = _ints(beat.childText('Notes'));
      if (noteRefs.isEmpty) {
        elements.add(RestElement(duration, id: 'e${id++}'));
        continue;
      }
      final pitches = <Pitch>[];
      for (final noteRef in noteRefs) {
        final note = noteById[noteRef];
        final string = int.tryParse(
            _findProperty(note, 'String')?.childText('String') ?? '');
        final fret =
            int.tryParse(_findProperty(note, 'Fret')?.childText('Fret') ?? '');
        if (string == null || fret == null || string >= tuningMidi.length) {
          continue;
        }
        pitches.add(_pitchFromMidi(tuningMidi[string] + fret));
      }
      if (pitches.isEmpty) {
        elements.add(RestElement(duration, id: 'e${id++}'));
      } else {
        pitches.sort((a, b) => a.midiNumber.compareTo(b.midiNumber));
        elements.add(
            NoteElement(pitches: pitches, duration: duration, id: 'e${id++}'));
      }
    }
    measures.add(Measure(elements));
  }

  if (measures.isEmpty) {
    measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
  }
  return Score(clef: Clef.treble, timeSignature: firstTime, measures: measures);
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
