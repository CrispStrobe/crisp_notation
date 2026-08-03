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

import '../layout/multi_part.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// The MuseScore file-format version this writer targets.
const _mscVersion = '4.20';

/// MuseScore `<durationType>` names, keyed by [DurationBase].
const _durationNames = {
  DurationBase.long: 'long',
  DurationBase.breve: 'breve',
  DurationBase.whole: 'whole',
  DurationBase.half: 'half',
  DurationBase.quarter: 'quarter',
  DurationBase.eighth: 'eighth',
  DurationBase.sixteenth: '16th',
  DurationBase.thirtySecond: '32nd',
  DurationBase.sixtyFourth: '64th',
  // Absent, these hit the `!` in `_durationXml` and CRASHED the writer outright
  // — the same gap that made MEI emit no @dur and kern the literal text "null",
  // but louder. A real PDMX file reaches it.
  DurationBase.oneHundredTwentyEighth: '128th',
  DurationBase.twoHundredFiftySixth: '256th',
  DurationBase.fiveHundredTwelfth: '512th',
  DurationBase.oneThousandTwentyFourth: '1024th',
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
  Articulation.staccatissimo: 'articStaccatissimoAbove',
  // MuseScore models a breath as its own `<Breath>` element, not an
  // articulation subtype, so it is written separately.
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

/// A [multiPart] score → a multi-staff `.mscx`: one `<Part>` and one `<Staff>`
/// music block per part, so an orchestral score keeps EVERY part (unlike
/// [scoreToMscx], which writes one staff). Each staff reads back with
/// `scoreFromMscx(mscx, staffIndex: i)`. mscx staves are independent measure
/// lists (no cross-staff time-alignment) and this codec's slur/dynamic/lyric
/// markup is per-`_MscxWriter` (positional/inline, not id-referenced), so no
/// cross-part id handling is needed — each part is written self-contained.
String multiPartToMscx(MultiPartScore multiPart, {List<String>? partNames}) {
  final parts = multiPart.parts;
  if (parts.isEmpty) {
    return scoreToMscx(Score(clef: Clef.treble, measures: const []));
  }
  if (parts.length == 1) return scoreToMscx(parts.first);

  final meta = parts.first.metadata;
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
  out.writeln('    <Division>480</Division>');

  String trackOf(int p) =>
      (partNames != null && p < partNames.length ? partNames[p] : null) ??
      parts[p].metadata.instrument ??
      'Part ${p + 1}';

  // One <Part> declaration per part …
  for (var p = 0; p < parts.length; p++) {
    final track = trackOf(p);
    out
      ..writeln('    <Part id="${p + 1}">')
      ..writeln('      <Staff id="${p + 1}"><StaffType group="pitched">'
          '<name>stdNormal</name></StaffType></Staff>')
      ..writeln('      <trackName>${_escape(track)}</trackName>')
      ..writeln('      <Instrument id=""><longName>${_escape(track)}</longName>'
          '<instrumentId>keyboard.piano</instrumentId></Instrument>')
      ..writeln('    </Part>');
  }
  // … then one <Staff> music block per part.
  for (var p = 0; p < parts.length; p++) {
    out.writeln('    <Staff id="${p + 1}">');
    _MscxWriter(parts[p], out).write();
    out.writeln('    </Staff>');
  }
  out
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
  // ⚠️ LISTS, not one slot each: a note may open two slurs, or close one and
  // open the next. A map keyed by note id silently kept only the last.
  final Map<String, List<String>> _slurNext = {};
  final Map<String, List<String>> _slurPrev = {};
  // Hairpins ride the SAME `<Spanner>` mechanism as slurs — a `<next>` on the
  // start note and a `<prev>` on the end — plus a `<subtype>` for the
  // direction. 6,807 of the 8,445 corpus `.mscx` files (81%) carry one and we
  // wrote none of them.
  final Map<String, String> _hairpinNext = {};
  final Map<String, String> _hairpinPrev = {};
  final Map<String, HairpinType> _hairpinType = {};
  final Map<String, String> _pedalNext = {};
  final Map<String, String> _pedalPrev = {};
  final Map<String, String> _ottavaNext = {};
  final Map<String, String> _ottavaPrev = {};
  final Map<String, bool> _ottavaDown = {};
  final Map<String, String> _glissNext = {};
  final Map<String, String> _glissPrev = {};
  final Map<String, bool> _glissIsPort = {};

  /// Cue notes are `<small>` on the chord — 3,060 of them in the corpus.
  late final Set<String> _cueIds = score.cueNoteIds.toSet();

  /// Figured bass by note id. A `<FiguredBass>` is a voice-level SIBLING
  /// preceding its chord, the same shape as `<Harmony>` and `<StaffText>`.
  ///
  /// ⚠️ The whole figure goes in `<digit>`. Real MuseScore splits a leading
  /// accidental into `<prefix>` with its own numeric code; keeping the text
  /// whole is lossless for us and renders a plain numeric figure identically,
  /// which is what continuo mostly is.
  late final Map<String, List<String>> _figuredBassById = {
    for (final f in score.figuredBass) f.noteId: f.figures,
  };
  final Map<String, String> _trillNext = {};
  final Map<String, String> _trillPrev = {};
  // A note's dynamic word (pp…fff, sf…) by note id.
  late final Map<String, String> _dynamicsById = {
    for (final d in score.dynamics) d.elementId: d.level.name
  };

  /// Melisma length in MuseScore ticks, by "noteId#verse".
  ///
  /// `Lyric.extender` records only the FACT of a melisma — as MusicXML's
  /// `<extend/>` and LilyPond's `__` do — but MuseScore wants the DURATION it
  /// spans. It is derivable: a melisma runs from its own note until the next
  /// note carrying a syllable in the SAME verse, or to the end of the score.
  late final Map<String, int> _melismaTicks = () {
    // Notes in play order, with the onset each one starts at.
    final order = <(String, Fraction)>[];
    var at = Fraction.zero;
    for (final m in score.measures) {
      for (final e in m.elements) {
        if (e.id != null) order.add((e.id!, at));
        at = at + e.duration.toFraction();
      }
    }
    final byId = {for (final (id, on) in order) id: on};
    final end = at;
    final out = <String, int>{};
    for (final l in score.lyrics) {
      if (!l.extender) continue;
      final start = byId[l.elementId];
      if (start == null) continue;
      // The next note in the same verse that carries a syllable ends it.
      var stop = end;
      for (final other in score.lyrics) {
        if (other.verse != l.verse) continue;
        final o = byId[other.elementId];
        if (o == null || o.compareTo(start) <= 0) continue;
        if (o.compareTo(stop) < 0) stop = o;
      }
      final span = stop - start;
      // MuseScore ticks are 480 per QUARTER, so a whole note is 4 x 480.
      final ticks = span.numerator * 4 * 480 ~/ span.denominator;
      if (ticks > 0) out['${l.elementId}#${l.verse}'] = ticks;
    }
    return out;
  }();

  /// Text marks by note id. MuseScore writes them as `<StaffText>`, a
  /// voice-level SIBLING that precedes its chord — the same shape as the
  /// spanners and `<Dynamic>`.
  late final Map<String, String> _annotationsById = {
    for (final a in score.annotations) a.elementId: a.text,
  };

  /// Chord symbols by note id, as `<Harmony>` — another voice-level SIBLING
  /// preceding its chord, exactly like `<StaffText>` and the spanners.
  ///
  /// Root and bass go out as MuseScore's tonal pitch class, the inverse of the
  /// reader's `_pitchFromTpc`: TPC walks the line of fifths from F, so
  /// 13 = F, 14 = C, 20 = F#, 6 = Fb. Writing a MIDI number here would look
  /// right and read back a semitone-spelled-wrong root.
  late final Map<String, ChordSymbol> _chordsById = {
    for (final c in score.chordSymbols) c.elementId: c,
  };

  static int _tpcOf(Pitch p) {
    const order = [Step.f, Step.c, Step.g, Step.d, Step.a, Step.e, Step.b];
    return order.indexOf(p.step) - 1 + (p.alter + 2) * 7;
  }

  static String _harmonyXml(ChordSymbol c) {
    final b = StringBuffer('<Harmony><root>${_tpcOf(c.root)}</root>');
    // The reader takes `<name>` over the 1.x integer `<extension>`, and the
    // model's own suffix is what its name table reads back.
    if (c.quality != ChordSymbolKind.major) {
      b.write('<name>${_escape(c.quality.suffix)}</name>');
    }
    if (c.bass != null) b.write('<base>${_tpcOf(c.bass!)}</base>');
    return (b..write('</Harmony>')).toString();
  }

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
    // ⚠️ NO early-out on "which spanner lists are empty". There used to be one
    // naming slurs/hairpins/pedals/ottavas, so adding glissandi built no onset
    // map at all for a score that carried only those — every span silently
    // dropped, with the emitting code present and correct. A guard that has to
    // be extended for each new spanner type will eventually not be, and the
    // map is one pass over elements the writer walks several times anyway.
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
      (_slurNext[s.startId] ??= []).add(delta);
      (_slurPrev[s.endId] ??= []).add('-$delta');
    }
    for (final h in score.hairpins) {
      final a = onset[h.startId];
      final b = onset[h.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _hairpinNext[h.startId] = delta;
      _hairpinPrev[h.endId] = '-$delta';
      _hairpinType[h.startId] = h.type;
    }
    for (final g in score.glissandos) {
      final a = onset[g.startId];
      final b = onset[g.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _glissNext[g.startId] = delta;
      _glissPrev[g.endId] = '-$delta';
    }
    for (final t in score.trillExtensions) {
      final a = onset[t.startId];
      final b = onset[t.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _trillNext[t.startId] = delta;
      _trillPrev[t.endId] = '-$delta';
    }
    for (final p in score.portamentos) {
      final a = onset[p.startId];
      final b = onset[p.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _glissNext[p.startId] = delta;
      _glissPrev[p.endId] = '-$delta';
      _glissIsPort[p.startId] = true;
    }
    for (final ped in score.pedals) {
      final a = onset[ped.startId];
      final b = onset[ped.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _pedalNext[ped.startId] = delta;
      _pedalPrev[ped.endId] = '-$delta';
    }
    for (final o in score.ottavas) {
      final a = onset[o.startId];
      final b = onset[o.endId];
      if (a == null || b == null) continue;
      final delta = _fraction(b - a);
      _ottavaNext[o.startId] = delta;
      _ottavaPrev[o.endId] = '-$delta';
      _ottavaDown[o.startId] = o.down;
    }
  }

  /// The `<Spanner>` markup a note or rest opens/closes, for the spanner types
  /// that sit at VOICE level rather than inside the chord.
  ///
  /// ⚠️ Emitted for rests too — a pedal is held through rests by definition and
  /// the corpus file that surfaced this opens its pedal on one.
  String _voiceSpanners(String? id) {
    if (id == null) return '';
    final buf = StringBuffer();
    if (_hairpinNext.containsKey(id)) {
      final sub = _hairpinType[id] == HairpinType.diminuendo ? 1 : 0;
      buf.write('<Spanner type="HairPin"><HairPin><subtype>$sub</subtype>'
          '</HairPin><next><location>'
          '<fractions>${_hairpinNext[id]}</fractions></location></next>'
          '</Spanner>');
    }
    if (_hairpinPrev.containsKey(id)) {
      buf.write('<Spanner type="HairPin"><prev><location>'
          '<fractions>${_hairpinPrev[id]}</fractions></location></prev>'
          '</Spanner>');
    }
    if (_pedalNext.containsKey(id)) {
      buf.write('<Spanner type="Pedal"><Pedal/><next><location>'
          '<fractions>${_pedalNext[id]}</fractions></location></next>'
          '</Spanner>');
    }
    if (_pedalPrev.containsKey(id)) {
      buf.write('<Spanner type="Pedal"><prev><location>'
          '<fractions>${_pedalPrev[id]}</fractions></location></prev>'
          '</Spanner>');
    }
    if (_ottavaNext.containsKey(id)) {
      // `down` in the model means the notes are written LOWER (an 8va bracket
      // above), which MuseScore spells `8va`; the other way is `8vb`.
      final sub = (_ottavaDown[id] ?? false) ? '8va' : '8vb';
      buf.write('<Spanner type="Ottava"><Ottava><subtype>$sub</subtype>'
          '</Ottava><next><location>'
          '<fractions>${_ottavaNext[id]}</fractions></location></next>'
          '</Spanner>');
    }
    if (_glissNext.containsKey(id)) {
      // MuseScore spells both with one spanner: subtype 1 is the WAVY line (a
      // glissando), 0 the straight one (a portamento).
      buf.write('<Spanner type="Glissando"><Glissando><subtype>'
          '${_glissIsPort[id] == true ? 0 : 1}</subtype></Glissando>'
          '<next><location>'
          '<fractions>${_glissNext[id]}</fractions></location></next>'
          '</Spanner>');
    }
    if (_glissPrev.containsKey(id)) {
      buf.write('<Spanner type="Glissando"><prev><location>'
          '<fractions>${_glissPrev[id]}</fractions></location></prev>'
          '</Spanner>');
    }
    if (_trillNext.containsKey(id)) {
      buf.write('<Spanner type="Trill"><Trill><subtype>trill</subtype>'
          '</Trill><next><location>'
          '<fractions>${_trillNext[id]}</fractions></location></next>'
          '</Spanner>');
    }
    if (_trillPrev.containsKey(id)) {
      buf.write('<Spanner type="Trill"><prev><location>'
          '<fractions>${_trillPrev[id]}</fractions></location></prev>'
          '</Spanner>');
    }
    if (_ottavaPrev.containsKey(id)) {
      buf.write('<Spanner type="Ottava"><prev><location>'
          '<fractions>${_ottavaPrev[id]}</fractions></location></prev>'
          '</Spanner>');
    }
    return buf.toString();
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
    // A volta (real mscx uses a multi-measure <Spanner type="Volta">; the per-
    // measure model rides a simpler Measure-level <Volta><endings>).
    if (measure.volta != null) {
      out.writeln('        <Volta><endings>${measure.volta}</endings></Volta>');
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
      // MuseScore's TimeSigType: 1 = common (C), 2 = alla breve (¢), absent
      // = plain numerals. Measured in the corpus — 644 `4/4 subtype=1` and
      // 39 `2/2 subtype=2` — rather than guessed, because inventing an
      // encoding would round-trip with ourselves and mislead.
      final sub = switch (time.symbol) {
        TimeSymbol.common => '<subtype>1</subtype>',
        TimeSymbol.cut => '<subtype>2</subtype>',
        TimeSymbol.numeric => '',
      };
      out.writeln('          <TimeSig>$sub<sigN>${time.beats}</sigN>'
          '<sigD>${time.beatUnit}</sigD></TimeSig>');
    }
    // MuseScore <tempo> is quarter-notes per second. Only the score's INITIAL
    // tempo was written, so every mid-score marking was dropped on export.
    final tempoHere = index == 0 ? score.tempo : measure.tempoChange;
    if (tempoHere != null) {
      out.writeln('          <Tempo><tempo>${tempoHere.quarterBpm / 60}</tempo>'
          '<followText>1</followText></Tempo>');
    }

    // Each voice gets ONLY its own spans. A TupletSpan addresses one voice by
    // index, so the whole list stamps an inner voice's triplet onto voice 1's
    // notes; and inner voices used to get no spans at all, which silently
    // un-tripleted every tuplet they had.
    _writeElements(measure.elements,
        tuplets: measure.tupletsForVoice(0), inlineClefs: measure.inlineClefs);
    out.writeln('        </voice>');

    // A MuseScore `<voice>` carries no number, so POSITION is its identity: an
    // empty one that is simply skipped moves every later voice up a slot, and a
    // staff whose voice 3 is empty gets its voice 4 read back as voice 3. Write
    // the gap out as an empty voice, but only up to the last one that has
    // content — trailing empties would add voices the score does not have.
    final inner = [measure.voice2, measure.voice3, measure.voice4];
    var last = -1;
    for (var v = 0; v < inner.length; v++) {
      if (inner[v].isNotEmpty) last = v;
    }
    for (var v = 0; v <= last; v++) {
      out.writeln('        <voice>');
      _writeElements(inner[v], tuplets: measure.tupletsForVoice(v + 1));
      out.writeln('        </voice>');
    }
    // The barline STYLE is a <BarLine> inside the LAST voice, at the end —
    // MuseScore treats it as a segment like any other, not a Measure flag the
    // way the repeats above are.
    final bar = _mscxBarline[measure.barline];
    if (bar != null) {
      out.writeln('        <voice><BarLine><subtype>$bar</subtype>'
          '</BarLine></voice>');
    }
    out.writeln('      </Measure>');
  }

  void _writeElements(List<MusicElement> elements,
      {List<TupletSpan> tuplets = const [],
      List<InlineClefChange> inlineClefs = const []}) {
    // A MID-BAR clef is a `<Clef>` at its own onset inside the voice, not a
    // measure-level one — writing it at the barline re-clefs every note before
    // it.
    var at = Fraction.zero;
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      for (final ic in inlineClefs) {
        if (ic.onset == at) {
          out.writeln('          <Clef>'
              '<concertClefType>${_clefCodes[ic.clef] ?? 'G'}'
              '</concertClefType>'
              '<transposingClefType>${_clefCodes[ic.clef] ?? 'G'}'
              '</transposingClefType></Clef>');
        }
      }
      at = at + element.duration.toFraction();
      for (final t in tuplets) {
        if (t.startIndex == i) {
          final base = _durationNames[element.duration.base] ?? 'eighth';
          out.writeln('          <Tuplet><normalNotes>${t.normal}</normalNotes>'
              '<actualNotes>${t.actual}</actualNotes>'
              '<baseNote>$base</baseNote></Tuplet>');
        }
      }
      if (element is RestElement) {
        // A rest can anchor a voice-level spanner — a pedal is held through
        // rests by definition — so it carries them exactly as a chord does.
        // A rest can anchor a voice-level spanner — a pedal is held through
        // rests by definition — so it gets the same sibling treatment.
        final rs = _voiceSpanners(element.id);
        if (rs.isNotEmpty) out.writeln('          $rs');
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
        // ⚠️ Voice-level spanners are SIBLINGS of `<Chord>`/`<Rest>` in real
        // MuseScore, not children. Writing them inside the element produced
        // files our own reader could not read back — the same sibling-vs-child
        // trap that hid every corpus hairpin, in the other direction.
        final chord = _chordsById[element.id];
        if (chord != null) out.writeln('          ${_harmonyXml(chord)}');
        final figures = _figuredBassById[element.id];
        if (figures != null) {
          out.writeln('          <FiguredBass>'
              '${figures.map((f) => '<FiguredBassItem><digit>'
                  '${_escape(f)}</digit></FiguredBassItem>').join()}'
              '</FiguredBass>');
        }
        final ann = _annotationsById[element.id];
        if (ann != null) {
          out.writeln('          <StaffText><text>${_escape(ann)}</text>'
              '</StaffText>');
        }
        final vs = _voiceSpanners(element.id);
        if (vs.isNotEmpty) out.writeln('          $vs');
        out.write('          <Chord>${_durationXml(element.duration)}'
            '${_articXml(element.articulations)}'
            '${_ornamentXml(_visibleOrnament(element))}'
            '${_tremoloXml(element.tremolo)}'
            '${_arpeggioXml(element.arpeggio)}'
            '${_cueIds.contains(element.id) ? '<small>1</small>' : ''}');
        final id = element.id;
        for (final delta in (id == null ? null : _slurNext[id]) ?? const []) {
          out.write('<Spanner type="Slur"><Slur/><next><location>'
              '<fractions>$delta</fractions></location></next>'
              '</Spanner>');
        }
        for (final delta in (id == null ? null : _slurPrev[id]) ?? const []) {
          out.write('<Spanner type="Slur"><prev><location>'
              '<fractions>$delta</fractions></location></prev>'
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
              '<tpc>${tpcOf(pitch)}</tpc>'
              '${_noteheadXml(element.notehead)}');
          // Fingering is a `<Fingering>` CHILD of the note, not a sibling of
          // the chord the way the spanners are. Written on the first pitch
          // only: the model holds one list per element, not per pitch.
          if (pitch == element.pitches.first) {
            for (final f in element.fingerings) {
              out.write('<Fingering><text>$f</text></Fingering>');
            }
          }
          out.write('</Note>');
        }
        // Lyrics are <Lyrics> children of the chord, one per verse; a syllable
        // that continues its word is `syllabic=begin` (else `single`).
        if (id != null) {
          for (final l in _lyricsById[id] ?? const <Lyric>[]) {
            final syllabic = l.hyphenToNext ? 'begin' : 'single';
            final ticks = _melismaTicks['$id#${l.verse}'];
            final melisma = ticks == null ? '' : '<ticks>$ticks</ticks>';
            out.write('<Lyrics><no>${l.verse - 1}</no>'
                '<syllabic>$syllabic</syllabic>$melisma'
                '<text>${_escape(l.text)}</text></Lyrics>');
          }
        }
        out.writeln('</Chord>');
        // A breath is its own element in MuseScore, a SIBLING that FOLLOWS the
        // chord — you breathe after the note, not on it.
        if (element.articulations.contains(Articulation.breath)) {
          out.writeln('          <Breath><symbol>breathMarkComma</symbol>'
              '</Breath>');
        }
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
    // Never `!` on this lookup: an unmapped value must not take the whole
    // export down. Falling back to the written value's own name keeps the file
    // readable even if a future duration is added and missed here.
    final name = _durationNames[duration.base] ?? 'quarter';
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

  /// The ornament to PRINT on [element].
  ///
  /// A note that starts a trill extension gets no `<Trill>` ornament: the
  /// spanner already draws the "tr" and its wavy line, so emitting both prints
  /// the sign twice. An extended trill is the span alone — the same convention
  /// the MusicXML, MEI and LilyPond codecs apply.
  Ornament? _visibleOrnament(NoteElement element) =>
      element.id != null && _trillNext.containsKey(element.id)
          ? null
          : element.ornament;

  /// `<Arpeggio>` is a CHILD of the chord. MuseScore's ArpeggioType has 0 as
  /// the plain rolled arpeggio — 7,173 of 7,597 in the corpus — and 2 as the
  /// downward one, so `up` takes the common spelling rather than a rarer
  /// synonym.
  static String _arpeggioXml(Arpeggio? a) => switch (a) {
        null => '',
        Arpeggio.up => '<Arpeggio><subtype>0</subtype></Arpeggio>',
        Arpeggio.down => '<Arpeggio><subtype>2</subtype></Arpeggio>',
      };

  /// `<head>` is a child of the NOTE. `normal` writes nothing, so an ordinary
  /// note stays byte-identical.
  static String _noteheadXml(NoteheadShape head) => switch (head) {
        NoteheadShape.normal => '',
        NoteheadShape.x => '<head>cross</head>',
        NoteheadShape.diamond => '<head>diamond</head>',
        NoteheadShape.triangleUp => '<head>triangle</head>',
        NoteheadShape.slash => '<head>slash</head>',
        NoteheadShape.circleX => '<head>xcircle</head>',
      };

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

/// The model's barline styles in MuseScore's `<BarLine><subtype>` vocabulary.
/// `normal` writes nothing, so an ordinary bar stays byte-identical.
const Map<BarlineStyle, String?> _mscxBarline = {
  BarlineStyle.normal: null,
  BarlineStyle.doubleBar: 'double',
  BarlineStyle.finalBar: 'end',
  BarlineStyle.heavy: 'heavy',
  BarlineStyle.dashed: 'dashed',
  BarlineStyle.dotted: 'dotted',
  BarlineStyle.tick: 'normal',
  BarlineStyle.short: 'normal',
  BarlineStyle.reverseFinal: 'reverse-end',
  BarlineStyle.none: 'none',
};
