/// MuseScore export: [Score] → a `.mscx` (MuseScore XML) document, a
/// **subset** codec that round-trips through `scoreFromMscx`.
///
/// Covers the shared musical data: clef (with mid-score changes), key and
/// time signatures (numeric; `.common`/`.cut` degrade to numeric 4/4 · 2/2),
/// measures, notes/chords, rests, durations (breve…64th with dots), up to
/// four voices, ties, pickup measures, articulations and ornaments (both as
/// `<Articulation>` SMuFL subtypes). Slurs, tuplets, lyrics, dynamics, grace
/// notes and repeat/navigation structure are out of scope (dropped on this
/// hop). Pure Dart (web-safe); the `.mscz` ZIP container is handled in
/// `partitura_cli`.
library;

import '../model/element.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/pitch.dart';

/// The MuseScore file-format version this writer targets.
const _mscVersion = '4.20';

/// MuseScore `<durationType>` names, keyed by [DurationBase].
const _durationNames = {
  DurationBase.breve: 'breve',
  DurationBase.whole: 'whole',
  DurationBase.half: 'half',
  DurationBase.quarter: 'quarter',
  DurationBase.eighth: 'eighth',
  DurationBase.sixteenth: '16th',
  DurationBase.thirtySecond: '32nd',
  DurationBase.sixtyFourth: '64th',
};

/// The MuseScore concert clef-type code for each partitura [Clef].
const _clefCodes = {
  Clef.treble: 'G',
  Clef.bass: 'F',
  Clef.alto: 'C3',
  Clef.tenor: 'C4',
  Clef.treble8va: 'G8va',
  Clef.treble8vb: 'G8vb',
  Clef.bass8vb: 'F8vb',
  Clef.frenchViolin: 'G1',
  Clef.soprano: 'C1',
  Clef.mezzoSoprano: 'C2',
  Clef.baritone: 'F_B',
  Clef.subbass: 'F_C',
  Clef.percussion: 'PERC',
};

/// MuseScore `<Articulation>` subtype (SMuFL glyph name) per articulation.
const museScoreArtic = {
  Articulation.staccato: 'articStaccatoAbove',
  Articulation.tenuto: 'articTenutoAbove',
  Articulation.accent: 'articAccentAbove',
  Articulation.marcato: 'articMarcatoAbove',
  Articulation.fermata: 'fermataAbove',
  Articulation.upBow: 'stringsUpBow',
  Articulation.downBow: 'stringsDownBow',
};

/// MuseScore stores ornaments as `<Articulation>` subtypes too (SMuFL names).
const museScoreOrnament = {
  Ornament.trill: 'ornamentTrill',
  Ornament.shortTrill: 'ornamentShortTrill',
  Ornament.mordent: 'ornamentMordent',
  Ornament.turn: 'ornamentTurn',
};

/// Serializes [score] as a single-part, single-staff MuseScore `.mscx`
/// document. [partName] labels the instrument track. Round-trips through
/// `scoreFromMscx` for the data the subset shares.
String scoreToMscx(Score score, {String partName = 'Music'}) {
  final meta = score.metadata;
  final track = meta.instrument ?? partName;
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<museScore version="$_mscVersion">')
    ..writeln('  <Score>');
  for (final (name, value) in [
    ('workTitle', meta.title),
    ('composer', meta.composer),
    ('lyricist', meta.lyricist),
    ('copyright', meta.copyright),
  ]) {
    if (value != null) {
      out.writeln('    <metaTag name="$name">${_escape(value)}</metaTag>');
    }
  }
  out
    ..writeln('    <Division>480</Division>')
    ..writeln('    <Part id="1">')
    ..writeln('      <Staff id="1"><StaffType group="pitched">'
        '<name>stdNormal</name></StaffType></Staff>')
    ..writeln('      <trackName>${_escape(track)}</trackName>')
    ..writeln('      <Instrument id="">'
        '<longName>${_escape(track)}</longName>'
        '<instrumentId>keyboard.piano</instrumentId></Instrument>')
    ..writeln('    </Part>')
    ..writeln('    <Staff id="1">');
  _MscxWriter(score, out).write();
  out
    ..writeln('    </Staff>')
    ..writeln('  </Score>')
    ..writeln('</museScore>');
  return out.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The MuseScore tonal-pitch-class (line-of-fifths) code for [pitch]: C = 14,
/// G = 15, F = 13, C♯ = 21, B♭ = 12, … (each fifth up/down is ±1).
int tpcOf(Pitch pitch) {
  const stepFifths = {
    Step.f: -1,
    Step.c: 0,
    Step.g: 1,
    Step.d: 2,
    Step.a: 3,
    Step.e: 4,
    Step.b: 5,
  };
  return stepFifths[pitch.step]! + 7 * pitch.alter + 14;
}

class _MscxWriter {
  final Score score;
  final StringBuffer out;
  _MscxWriter(this.score, this.out);

  void write() {
    for (var m = 0; m < score.measures.length; m++) {
      _writeMeasure(m);
    }
  }

  void _writeMeasure(int index) {
    final measure = score.measures[index];
    // A pickup / irregular measure declares its actual length.
    final len =
        measure.pickup ? ' len="${_fraction(measure.totalDuration)}"' : '';
    out.writeln('      <Measure$len>');
    out.writeln('        <voice>');

    // Leading signatures (measure 0) and any mid-score changes open the voice.
    final clef = index == 0 ? score.clef : measure.clefChange;
    if (clef != null) {
      final code = _clefCodes[clef] ?? 'G';
      out.writeln('          <Clef><concertClefType>$code</concertClefType>'
          '<transposingClefType>$code</transposingClefType></Clef>');
    }
    final key = index == 0 ? score.keySignature : measure.keyChange;
    if (key != null) {
      out.writeln('          <KeySig><concertKey>${key.fifths}</concertKey>'
          '</KeySig>');
    }
    final time = index == 0 ? score.timeSignature : measure.timeChange;
    if (time != null) {
      out.writeln('          <TimeSig><sigN>${time.beats}</sigN>'
          '<sigD>${time.beatUnit}</sigD></TimeSig>');
    }
    // MuseScore <tempo> is quarter-notes per second.
    if (index == 0 && score.tempo != null) {
      final t = score.tempo!;
      final f = NoteDuration(t.beatUnit, dots: t.dots).toFraction();
      final qps = t.bpm * f.numerator * 4 / f.denominator / 60;
      out.writeln('          <Tempo><tempo>$qps</tempo>'
          '<followText>1</followText></Tempo>');
    }

    _writeElements(measure.elements);
    out.writeln('        </voice>');

    for (final voice in [measure.voice2, measure.voice3, measure.voice4]) {
      if (voice.isEmpty) continue;
      out.writeln('        <voice>');
      _writeElements(voice);
      out.writeln('        </voice>');
    }
    out.writeln('      </Measure>');
  }

  void _writeElements(List<MusicElement> elements) {
    for (final element in elements) {
      if (element is RestElement) {
        out.writeln('          <Rest>${_durationXml(element.duration)}</Rest>');
      } else if (element is NoteElement) {
        out.write('          <Chord>${_durationXml(element.duration)}'
            '${_articXml(element.articulations)}'
            '${_ornamentXml(element.ornament)}');
        for (final pitch in element.pitches) {
          out.write('<Note>');
          if (element.tieToNext) {
            out.write('<Spanner type="Tie"><next><location>'
                '<fractions>${_fraction(element.duration.toFraction())}</fractions>'
                '</location></next></Spanner>');
          }
          out.write('<pitch>${pitch.midiNumber}</pitch>'
              '<tpc>${tpcOf(pitch)}</tpc></Note>');
        }
        out.writeln('</Chord>');
      }
    }
  }

  static String _durationXml(NoteDuration duration) {
    final name = _durationNames[duration.base]!;
    final dots = duration.dots == 0 ? '' : '<dots>${duration.dots}</dots>';
    return '<durationType>$name</durationType>$dots';
  }

  /// MuseScore `<Articulation><subtype>…</subtype></Articulation>` children
  /// for an element's [articulations] (SMuFL glyph-name subtypes).
  static String _articXml(Set<Articulation> articulations) {
    final buf = StringBuffer();
    for (final a in Articulation.values) {
      final subtype = museScoreArtic[a];
      if (subtype != null && articulations.contains(a)) {
        buf.write('<Articulation><subtype>$subtype</subtype></Articulation>');
      }
    }
    return buf.toString();
  }

  static String _ornamentXml(Ornament? ornament) {
    final subtype = museScoreOrnament[ornament];
    return subtype == null
        ? ''
        : '<Articulation><subtype>$subtype</subtype></Articulation>';
  }

  /// A whole-note [fraction] as MuseScore's `n/d` string (already reduced).
  static String _fraction(Fraction fraction) =>
      '${fraction.numerator}/${fraction.denominator}';
}
