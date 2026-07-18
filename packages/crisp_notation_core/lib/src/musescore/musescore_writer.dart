/// MuseScore export: [Score] → a `.mscx` (MuseScore XML) document, a
/// **subset** codec that round-trips through `scoreFromMscx`.
///
/// Covers the shared musical data: clef (with mid-score changes), key and
/// time signatures (numeric; `.common`/`.cut` degrade to numeric 4/4 · 2/2),
/// measures, notes/chords, rests, durations (breve…64th with dots), up to
/// four voices, ties, pickup measures, articulations and ornaments (both as
/// `<Articulation>` SMuFL subtypes), tuplets (`<Tuplet>`/`<endTuplet>`) and
/// slurs (`<Spanner type="Slur">`). Lyrics, dynamics, grace notes and
/// repeat/navigation structure are out of scope (dropped on this hop). Pure
/// Dart (web-safe); the `.mscz` ZIP container is handled in `crisp_notation_cli`.
library;

import '../model/element.dart';
import '../model/measure.dart';
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

/// The MuseScore concert clef-type code for each crisp_notation [Clef].
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
  Ornament.invertedTurn: 'ornamentTurnInverted',
  // MuseScore renders an accidental trill as a trill plus a separate accidental
  // symbol, not a single ornament, so the accidental degrades to a plain trill
  // (as it does in the MEI/kern/ABC codecs) rather than dropping the ornament.
  Ornament.trillSharp: 'ornamentTrill',
  Ornament.trillFlat: 'ornamentTrill',
  Ornament.trillNatural: 'ornamentTrill',
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
  // Slur spanner offsets by note id: the start note carries a `<next>` to the
  // end, the end note a `<prev>` back. The offset is the whole-note distance
  // between their onsets.
  final Map<String, String> _slurNext = {};
  final Map<String, String> _slurPrev = {};
  // A note's dynamic word (pp…fff, sf…) by note id.
  late final Map<String, String> _dynamicsById = {
    for (final d in score.dynamics) d.elementId: d.level.name
  };
  // A note's lyric syllables (verse-sorted) by note id.
  late final Map<String, List<Lyric>> _lyricsById = () {
    final map = <String, List<Lyric>>{};
    for (final l in score.lyrics) {
      (map[l.elementId] ??= []).add(l);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.verse.compareTo(b.verse));
    }
    return map;
  }();

  _MscxWriter(this.score, this.out) {
    if (score.slurs.isEmpty) return;
    final onset = <String, Fraction>{};
    var measureStart = Fraction.zero;
    for (final m in score.measures) {
      // Voice 1 defines the measure's length; every voice restarts at the
      // measure's start onset, so a slur within voice 2/3/4 measures its own
      // span rather than being dropped for want of an onset.
      var acc = measureStart;
      for (final e in m.elements) {
        if (e.id != null) onset[e.id!] = acc;
        acc = acc + e.duration.toFraction();
      }
      final measureEnd = acc;
      for (final voice in [m.voice2, m.voice3, m.voice4]) {
        var vacc = measureStart;
        for (final e in voice) {
          if (e.id != null) onset[e.id!] = vacc;
          vacc = vacc + e.duration.toFraction();
        }
      }
      measureStart = measureEnd;
    }
    for (final s in score.slurs) {
      final a = onset[s.startId];
      final b = onset[s.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _slurNext[s.startId] = delta;
      _slurPrev[s.endId] = '-$delta';
    }
  }

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
    // Repeats are Measure-level flags in mscx.
    if (measure.startRepeat) out.writeln('        <startRepeat/>');
    if (measure.endRepeat) out.writeln('        <endRepeat>2</endRepeat>');
    // Navigation rides a Measure-level <Marker>; @subtype carries the model's
    // own name so every variant (incl. the compound al-fine/al-coda forms)
    // round-trips (the simple segno/coda/fine subtypes match mscx's own).
    if (measure.navigation != null) {
      out.writeln('        <Marker><subtype>${measure.navigation!.name}'
          '</subtype></Marker>');
    }
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

    _writeElements(measure.elements, tuplets: measure.tuplets);
    out.writeln('        </voice>');

    for (final voice in [measure.voice2, measure.voice3, measure.voice4]) {
      if (voice.isEmpty) continue;
      out.writeln('        <voice>');
      _writeElements(voice);
      out.writeln('        </voice>');
    }
    out.writeln('      </Measure>');
  }

  void _writeElements(List<MusicElement> elements,
      {List<TupletSpan> tuplets = const []}) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      for (final t in tuplets) {
        if (t.startIndex == i) {
          final base = _durationNames[element.duration.base] ?? 'eighth';
          out.writeln('          <Tuplet><normalNotes>${t.normal}</normalNotes>'
              '<actualNotes>${t.actual}</actualNotes>'
              '<baseNote>$base</baseNote></Tuplet>');
        }
      }
      if (element is RestElement) {
        out.writeln('          <Rest>${_durationXml(element.duration)}</Rest>');
      } else if (element is NoteElement) {
        // Grace notes are separate <Chord>s (tagged acciaccatura/appoggiatura)
        // that precede their principal chord.
        if (element.graceNotes.isNotEmpty) {
          final tag = element.graceStyle == GraceStyle.appoggiatura
              ? 'appoggiatura'
              : 'acciaccatura';
          for (final pitch in element.graceNotes) {
            out.writeln('          <Chord><$tag/>'
                '<durationType>eighth</durationType>'
                '<Note><pitch>${pitch.midiNumber}</pitch>'
                '<tpc>${tpcOf(pitch)}</tpc></Note></Chord>');
          }
        }
        // A dynamic is a voice element placed just before its note.
        final did = element.id;
        if (did != null && _dynamicsById.containsKey(did)) {
          out.writeln('          <Dynamic><subtype>${_dynamicsById[did]}'
              '</subtype></Dynamic>');
        }
        out.write('          <Chord>${_durationXml(element.duration)}'
            '${_articXml(element.articulations)}'
            '${_ornamentXml(element.ornament)}'
            '${_tremoloXml(element.tremolo)}');
        final id = element.id;
        if (id != null && _slurNext.containsKey(id)) {
          out.write('<Spanner type="Slur"><Slur/><next><location>'
              '<fractions>${_slurNext[id]}</fractions></location></next>'
              '</Spanner>');
        }
        if (id != null && _slurPrev.containsKey(id)) {
          out.write('<Spanner type="Slur"><prev><location>'
              '<fractions>${_slurPrev[id]}</fractions></location></prev>'
              '</Spanner>');
        }
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
        // Lyrics are <Lyrics> children of the chord, one per verse; a syllable
        // that continues its word is `syllabic=begin` (else `single`).
        if (id != null) {
          for (final l in _lyricsById[id] ?? const <Lyric>[]) {
            final syllabic = l.hyphenToNext ? 'begin' : 'single';
            out.write('<Lyrics><no>${l.verse - 1}</no>'
                '<syllabic>$syllabic</syllabic>'
                '<text>${_escape(l.text)}</text></Lyrics>');
          }
        }
        out.writeln('</Chord>');
      }
      for (final t in tuplets) {
        if (t.endIndex == i) out.writeln('          <endTuplet/>');
      }
    }
  }

  /// Single-note tremolo as `<Tremolo><subtype>rN</subtype></Tremolo>`: N slashes
  /// map to r8/r16/r32/… (r-value 8·2^(N-1)).
  static String _tremoloXml(int? tremolo) => tremolo == null || tremolo < 1
      ? ''
      : '<Tremolo><subtype>r${8 << (tremolo - 1)}</subtype></Tremolo>';

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
