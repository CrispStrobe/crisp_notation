/// LilyPond export: [Score] → a `.ly` source string for the LilyPond engraver.
///
/// Export-only — LilyPond input is a full (Turing-complete) language, so there
/// is no importer. Generated from the documented syntax (no LilyPond code is
/// used), pure Dart. Covers clef (with mid-score changes), key/time
/// signatures, notes/chords, rests, durations (breve…64th with dots), two
/// voices, ties and pickup (`\partial`). Slurs, tuplets, articulations,
/// lyrics, dynamics and repeat structure are out of scope. Pitch names use
/// LilyPond's default Dutch note language.
library;

import '../model/element.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// The LilyPond version tag emitted at the top of the file.
const _lilyVersion = '2.24.0';

const _clefNames = {
  Clef.treble: 'treble',
  Clef.bass: 'bass',
  Clef.alto: 'alto',
  Clef.tenor: 'tenor',
  Clef.treble8va: '"treble^8"',
  Clef.treble8vb: '"treble_8"',
  Clef.bass8vb: '"bass_8"',
  Clef.frenchViolin: 'french',
  Clef.soprano: 'soprano',
  Clef.mezzoSoprano: 'mezzosoprano',
  Clef.baritone: 'varbaritone', // F-clef baritone (partitura's baritone)
  Clef.subbass: 'subbass',
  Clef.percussion: 'percussion',
};

/// Major-key tonic (Dutch note name) for a signature of `fifths`.
const _keyTonics = {
  0: 'c', 1: 'g', 2: 'd', 3: 'a', 4: 'e', 5: 'b', 6: 'fis', 7: 'cis', //
  -1: 'f', -2: 'bes', -3: 'ees', -4: 'aes', -5: 'des', -6: 'ges', -7: 'ces',
};

const _durValues = {
  DurationBase.breve: r'\breve',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
};

/// Serializes [score] as a LilyPond `.ly` document.
String scoreToLilyPond(Score score) {
  final out = StringBuffer()
    ..writeln('\\version "$_lilyVersion"')
    ..writeln('\\score {')
    ..writeln('  \\new Staff {');

  final body = StringBuffer();
  body.write('    ${_clef(score.clef)} ${_key(score.keySignature)} ');
  if (score.timeSignature != null) {
    body.write('${_time(score.timeSignature!)} ');
  }

  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (m > 0) {
      if (measure.clefChange != null) {
        body.write('${_clef(measure.clefChange!)} ');
      }
      if (measure.keyChange != null) body.write('${_key(measure.keyChange!)} ');
      if (measure.timeChange != null) {
        body.write('${_time(measure.timeChange!)} ');
      }
    }
    if (measure.pickup) {
      final dur = _durationOf(measure.totalDuration);
      if (dur != null) body.write('\\partial $dur ');
    }
    if (measure.voice2.isEmpty) {
      body.write('${_elements(measure.elements)} ');
    } else {
      body.write('<< { ${_elements(measure.elements)} } '
          '\\\\ { ${_elements(measure.voice2)} } >> ');
    }
  }

  out
    ..writeln(body.toString().trimRight())
    ..writeln('  }')
    ..writeln('  \\layout { }')
    ..writeln('}');
  return out.toString();
}

String _clef(Clef clef) => '\\clef ${_clefNames[clef]}';

String _key(KeySignature key) => '\\key ${_keyTonics[key.fifths]} \\major';

String _time(TimeSignature time) {
  // 4/4 and 2/2 render as C / cut-C by LilyPond default; force numerals
  // otherwise so a numeric 4/4 doesn't come out as the C symbol.
  final numeric =
      time.symbol == TimeSymbol.numeric ? '\\numericTimeSignature ' : '';
  final beats = time.components?.reduce((a, b) => a + b) ?? time.beats;
  return '$numeric\\time $beats/${time.beatUnit}';
}

String _elements(List<MusicElement> elements) =>
    elements.map(_element).join(' ');

String _element(MusicElement element) {
  if (element is RestElement) {
    return 'r${_dur(element.duration)}';
  }
  final note = element as NoteElement;
  final tie = note.tieToNext ? '~' : '';
  final artic = _artic(note.articulations);
  if (note.pitches.length == 1) {
    return '${_pitch(note.pitches.single)}${_dur(note.duration)}$artic$tie';
  }
  final inner = note.pitches.map(_pitch).join(' ');
  return '<$inner>${_dur(note.duration)}$artic$tie';
}

/// LilyPond articulation scripts appended to a note.
String _artic(Set<Articulation> a) {
  final b = StringBuffer();
  if (a.contains(Articulation.staccato)) b.write('-.');
  if (a.contains(Articulation.tenuto)) b.write('--');
  if (a.contains(Articulation.accent)) b.write('->');
  if (a.contains(Articulation.marcato)) b.write('-^');
  if (a.contains(Articulation.fermata)) b.write('\\fermata');
  if (a.contains(Articulation.upBow)) b.write('\\upbow');
  if (a.contains(Articulation.downBow)) b.write('\\downbow');
  return b.toString();
}

String _dur(NoteDuration duration) =>
    '${_durValues[duration.base]}${'.' * duration.dots}';

String _pitch(Pitch pitch) {
  const accid = {1: 'is', 2: 'isis', -1: 'es', -2: 'eses', 0: ''};
  final marks =
      pitch.octave >= 3 ? "'" * (pitch.octave - 3) : ',' * (3 - pitch.octave);
  return '${pitch.step.name}${accid[pitch.alter]}$marks';
}

/// A whole-note fraction as a single LilyPond duration, or null if it is not
/// one plain base(+dots) value (e.g. a 5/4 pickup).
String? _durationOf(Fraction fraction) {
  for (final base in DurationBase.values) {
    final (bn, bd) =
        base == DurationBase.breve ? (2, 1) : (1, base.denominator);
    for (var dots = 0; dots <= 2; dots++) {
      final mulN = (1 << (dots + 1)) - 1;
      final mulD = 1 << dots;
      if (bn * mulN * fraction.denominator == fraction.numerator * bd * mulD) {
        return '${_durValues[base]}${'.' * dots}';
      }
    }
  }
  return null;
}
