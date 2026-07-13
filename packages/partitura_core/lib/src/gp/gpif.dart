/// GPIF (`score.gpif`) import/export.
///
/// GPIF is the XML document at the heart of the `.gpx`/`.gp` (v6/7/8) file
/// formats (`.gpx` is a compressed container, `.gp` a zip — both hold a
/// `score.gpif`).
/// This is a **subset** codec, pure Dart (web-safe): it reads/writes the
/// GPIF document structure — track tuning, master bars, bars → voices → beats →
/// notes (string+fret), rhythms and the common playing techniques — into a
/// partitura [Score]. On **import**, hammer-on/pull-off (`HopoOrigin`) → a
/// slur, slides (`Slide`) → a glissando, bends (`Bended`/`BendDestinationValue`,
/// 100 = a whole step) → a `Bend`, whammy vibrato (`VibratoWTremBar`) →
/// a `Vibrato`, dead (`Muted`) and harmonic (`Harmonic`, with `HarmonicType`
/// natural/artificial/pinch) notes → `TabNoteMark`s; export writes the same
/// properties back, so a round-trip keeps techniques.
/// Multi-track files import one track at a time (`trackIndex`; see
/// [gpifTrackNames]). It reads real `.gp` (v7) files correctly — validated
/// against the vendored `.gp` (v7) fixtures (pitches, chords, rhythm,
/// techniques, multi-track; fixture provenance in
/// `partitura_cli/test/data/gp/README.md`).
///
/// The GPIF vocabulary here is the format's own XML tag set (factual); the
/// parsing and mapping code is original — not derived from any decoder's
/// source. The zip/`.gp` container wrapping lives in
/// `interchange/gp_container.dart` (web-safe); this module works on the
/// `score.gpif` XML string directly.
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
/// dropped. Voice 2 is ignored (single voice per bar). Tab techniques
/// (bends, hammer-on/pull-off, slides, vibrato, dead/harmonic) are written as
/// GPIF note properties, so a `.gp` round-trip keeps them.
String scoreToGpif(Score score, {Tuning? tuning}) {
  final tune = tuning ?? Tuning.standardGuitar;
  // Per-note technique lookups (a span is written on its start note).
  final hopoFrom = {for (final s in score.slurs) s.startId};
  final slideFrom = {for (final g in score.glissandos) g.startId};
  final bendBy = {for (final bend in score.bends) bend.noteId: bend.steps};
  final vibratoIds = {for (final v in score.vibratos) v.noteId};
  final markBy = {for (final m in score.tabNoteMarks) m.noteId: m.style};
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
        var first = true;
        for (final pitch in element.pitches) {
          final place = tune.fretFor(pitch);
          if (place == null) continue;
          final props = StringBuffer(
              '<Property name="String"><String>${place.$1}</String></Property>'
              '<Property name="Fret"><Fret>${place.$2}</Fret></Property>');
          // Element-level techniques go on the first sounding note.
          final eid = element.id;
          if (first && eid != null) {
            if (hopoFrom.contains(eid)) {
              props.write('<Property name="HopoOrigin"><Enable/></Property>');
            }
            if (slideFrom.contains(eid)) {
              props.write('<Property name="Slide"><Flags>2</Flags></Property>');
            }
            final steps = bendBy[eid];
            if (steps != null) {
              props.write('<Property name="Bended"><Enable/></Property>'
                  '<Property name="BendDestinationValue"><Float>'
                  '${(steps * 100).toStringAsFixed(6)}</Float></Property>');
            }
            if (vibratoIds.contains(eid)) {
              props.write('<Property name="Vibrato"><Enable/></Property>');
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
          notes.writeln('    <Note id="$noteId"><Properties>$props'
              '</Properties></Note>');
          noteRefs.add(noteId++);
          first = false;
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
  final slurs = <Slur>[]; // hammer-on / pull-off
  final glissandos = <Glissando>[]; // slides
  String? pendingHopo; // a HO/PO note waiting for its destination
  String? pendingSlide;
  var id = 0;
  TimeSignature? firstTime;

  for (final masterBar
      in root.child('MasterBars')?.children ?? const <XmlNode>[]) {
    if (masterBar.name != 'MasterBar') continue;
    final time = masterBar.childText('Time');
    if (time != null && firstTime == null) firstTime = _parseTime(time);

    // A MasterBar lists one bar id per track; pick this track's.
    final barIds = _ints(masterBar.childText('Bars'));
    if (barIds.isEmpty) continue;
    final barRef = trackIndex < barIds.length ? barIds[trackIndex] : barIds[0];
    final bar = barById[barRef];
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
      final nodes = <XmlNode>[];
      for (final noteRef in noteRefs) {
        final note = noteById[noteRef];
        if (note == null) continue;
        final string = int.tryParse(
            _findProperty(note, 'String')?.childText('String') ?? '');
        final fret =
            int.tryParse(_findProperty(note, 'Fret')?.childText('Fret') ?? '');
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
      elements
          .add(NoteElement(pitches: pitches, duration: duration, id: noteId));

      // Playing techniques → partitura's tab marks. Spans (HO/PO, slide)
      // connect this note to the previous one that opened them.
      final hopoFrom = pendingHopo;
      if (hopoFrom != null) {
        slurs.add(Slur(hopoFrom, noteId));
        pendingHopo = null;
      }
      final slideFrom = pendingSlide;
      if (slideFrom != null) {
        glissandos.add(Glissando(slideFrom, noteId));
        pendingSlide = null;
      }
      var dead = false, harmonic = false, vibrato = false, vibratoWide = false;
      var harmonicStyle = TabNoteStyle.harmonic;
      double? bendSteps;
      // Whammy-bar vibrato is a beat property.
      if (_propOn(beat, 'VibratoWTremBar')) {
        vibrato = true;
        vibratoWide = true;
      }
      for (final note in nodes) {
        if (_propOn(note, 'Muted')) dead = true;
        if (_propOn(note, 'Harmonic')) {
          harmonic = true;
          harmonicStyle =
              switch (_findProperty(note, 'HarmonicType')?.childText('HType')) {
            'Artificial' => TabNoteStyle.artificialHarmonic,
            'Pinch' => TabNoteStyle.pinchHarmonic,
            'Tap' => TabNoteStyle.tappedHarmonic,
            'Semi' => TabNoteStyle.semiHarmonic,
            'Feedback' => TabNoteStyle.feedbackHarmonic,
            _ => TabNoteStyle.harmonic,
          };
        }
        if (_propOn(note, 'HopoOrigin')) pendingHopo = noteId;
        if (_propOn(note, 'Slide')) pendingSlide = noteId;
        if (_propOn(note, 'Vibrato')) vibrato = true;
        if (_propOn(note, 'VibratoWTremBar')) {
          vibrato = true;
          vibratoWide = true;
        }
        final bv =
            _findProperty(note, 'BendDestinationValue')?.childText('Float');
        if (_propOn(note, 'Bended') && bv != null) {
          final v = (double.tryParse(bv) ?? 0) / 100;
          if (bendSteps == null || v > bendSteps) bendSteps = v;
        }
      }
      if (harmonic) {
        marks.add(TabNoteMark(noteId, harmonicStyle));
      } else if (dead) {
        marks.add(TabNoteMark(noteId, TabNoteStyle.dead));
      }
      if (bendSteps != null && bendSteps > 0) {
        bends.add(Bend(noteId, steps: bendSteps));
      }
      if (vibrato) vibratos.add(Vibrato(noteId, wide: vibratoWide));
    }
    measures.add(Measure(elements));
  }

  if (measures.isEmpty) {
    measures.add(Measure([RestElement(NoteDuration.whole, id: 'e0')]));
  }
  return Score(
    clef: Clef.treble,
    timeSignature: firstTime,
    measures: measures,
    slurs: slurs,
    glissandos: glissandos,
    bends: bends,
    vibratos: vibratos,
    tabNoteMarks: marks,
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
