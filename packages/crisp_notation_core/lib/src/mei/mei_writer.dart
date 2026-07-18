/// MEI (Music Encoding Initiative) export: [Score] → an `<mei>` document, a
/// **subset** codec that round-trips through `scoreFromMei`.
///
/// MEI is the open, standards-body XML for notation used across digital
/// musicology (Verovio, music21). Covered subset: clef (with mid-score
/// changes), key and time signatures (numeric + common/cut + additive),
/// measures, notes/chords, rests, durations (breve…64th with dots), two
/// voices (layers), ties, pickup measures, articulations (`@artic`/`@fermata`)
/// and ornaments (`<trill>`/`<mordent>`/`<turn>` control events). Pitch
/// spelling round-trips via gestural accidentals (`accid.ges`). Slurs
/// (`<slur>`), dynamics (`<dynam>`), tuplets (`<tuplet>`) and lyrics
/// (`<verse>/<syl>`) round-trip. Pure Dart (web-safe).
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

const _meiNs = 'http://www.music-encoding.org/ns/mei';

/// MEI `@dur` value for each undotted [DurationBase].
const _durValues = {
  DurationBase.breve: 'breve',
  DurationBase.whole: '1',
  DurationBase.half: '2',
  DurationBase.quarter: '4',
  DurationBase.eighth: '8',
  DurationBase.sixteenth: '16',
  DurationBase.thirtySecond: '32',
  DurationBase.sixtyFourth: '64',
};

/// Accidental code per alteration (written `@accid` / gestural `@accid.ges`).
const _accidCodes = {2: 'x', 1: 's', 0: 'n', -1: 'f', -2: 'ff'};

/// The (shape, line, dis, disPlace) of a clef for MEI's clef attributes.
(String, int, int?, String?) _clefParts(Clef clef) => switch (clef) {
      Clef.treble => ('G', 2, null, null),
      Clef.bass => ('F', 4, null, null),
      Clef.alto => ('C', 3, null, null),
      Clef.tenor => ('C', 4, null, null),
      Clef.treble8va => ('G', 2, 8, 'above'),
      Clef.treble8vb => ('G', 2, 8, 'below'),
      Clef.bass8vb => ('F', 4, 8, 'below'),
      Clef.frenchViolin => ('G', 1, null, null),
      Clef.soprano => ('C', 1, null, null),
      Clef.mezzoSoprano => ('C', 2, null, null),
      Clef.baritone => ('F', 3, null, null),
      Clef.subbass => ('F', 5, null, null),
      Clef.percussion => ('perc', 3, null, null),
    };

/// MEI `@keysig`/`@sig` string for [key]: `0`, `2s`, `3f`.
String meiKeySig(KeySignature key) => key.fifths == 0
    ? '0'
    : key.fifths > 0
        ? '${key.fifths}s'
        : '${-key.fifths}f';

/// Serializes [score] as a single-staff MEI document. [title] fills the
/// header. Round-trips through `scoreFromMei` for the data the subset shares.
String scoreToMei(Score score, {String title = 'Music'}) {
  final meta = score.metadata;
  final resp = StringBuffer();
  if (meta.composer != null) {
    resp.write('<persName role="composer">${_escape(meta.composer!)}'
        '</persName>');
  }
  if (meta.lyricist != null) {
    resp.write('<persName role="lyricist">${_escape(meta.lyricist!)}'
        '</persName>');
  }
  final titleStmt = '<title>${_escape(meta.title ?? title)}</title>'
      '${resp.isEmpty ? '' : '<respStmt>$resp</respStmt>'}';
  final pubStmt = meta.copyright == null
      ? '<pubStmt/>'
      : '<pubStmt><availability>${_escape(meta.copyright!)}</availability>'
          '</pubStmt>';
  final out = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<mei xmlns="$_meiNs" meiversion="5.0">')
    ..writeln('  <meiHead><fileDesc><titleStmt>$titleStmt</titleStmt>'
        '$pubStmt</fileDesc></meiHead>')
    ..writeln('  <music><body><mdiv><score>');

  // Leading scoreDef: key + meter on the scoreDef, clef on the staffDef.
  final (shape, line, dis, disPlace) = _clefParts(score.clef);
  final meterAttrs = score.timeSignature == null
      ? ''
      : ' ${_meterAttrs(score.timeSignature!, dotted: true)}';
  final t = score.tempo;
  final mm = t == null
      ? ''
      : ' mm="${_bpm(t.bpm)}" mm.unit="${_durValues[t.beatUnit]}"'
          '${t.dots == 0 ? '' : ' mm.dots="${t.dots}"'}';
  out.writeln('    <scoreDef keysig="${meiKeySig(score.keySignature)}"'
      '$meterAttrs$mm>');
  final label = score.metadata.instrument == null
      ? ''
      : ' label="${_escape(score.metadata.instrument!)}"';
  out.writeln('      <staffGrp><staffDef n="1"$label lines="5" '
      'clef.shape="$shape" clef.line="$line"'
      '${dis == null ? '' : ' clef.dis="$dis" clef.dis.place="$disPlace"'}'
      '/></staffGrp>');
  out.writeln('    </scoreDef>');
  out.writeln('    <section>');

  // Lyrics are `<verse>/<syl>` children of their note, keyed by note id and
  // ordered by verse so stacked verses stay in reading order.
  final lyricsById = <String, List<Lyric>>{};
  for (final lyric in score.lyrics) {
    (lyricsById[lyric.elementId] ??= []).add(lyric);
  }
  for (final list in lyricsById.values) {
    list.sort((a, b) => a.verse.compareTo(b.verse));
  }

  for (var m = 0; m < score.measures.length; m++) {
    // A volta (1st/2nd ending) is an <ending n="…"> wrapping its measure(s).
    final volta = score.measures[m].volta;
    if (volta != null) out.writeln('      <ending n="$volta">');
    _writeMeasure(out, score, m, lyricsById);
    if (volta != null) out.writeln('      </ending>');
  }

  out
    ..writeln('    </section>')
    ..writeln('  </score></mdiv></body></music>')
    ..writeln('</mei>');
  return out.toString();
}

String _meterAttrs(TimeSignature time, {required bool dotted}) {
  final count = time.components?.join('+') ?? '${time.beats}';
  final p = dotted ? 'meter.' : '';
  final sym = switch (time.symbol) {
    TimeSymbol.common => ' ${p}sym="common"',
    TimeSymbol.cut => ' ${p}sym="cut"',
    TimeSymbol.numeric => '',
  };
  return '${p}count="$count" ${p}unit="${time.beatUnit}"$sym';
}

void _writeMeasure(StringBuffer out, Score score, int index,
    Map<String, List<Lyric>> lyricsById) {
  final measure = score.measures[index];
  final metcon = measure.pickup ? ' metcon="false"' : '';
  final number = score.barNumberAt(index) ?? 0;
  // Repeats are barline attributes on the measure itself.
  final left = measure.startRepeat ? ' left="rptstart"' : '';
  final right = measure.endRepeat ? ' right="rptend"' : '';
  out.writeln('      <measure n="$number"$metcon$left$right>');
  out.writeln('        <staff n="1">');

  // Mid-score changes open layer 1 as inline clef/keySig/meterSig.
  final changes = StringBuffer();
  if (measure.clefChange != null) {
    final (shape, line, dis, disPlace) = _clefParts(measure.clefChange!);
    changes.write('<clef shape="$shape" line="$line"'
        '${dis == null ? '' : ' dis="$dis" dis.place="$disPlace"'}/>');
  }
  if (measure.keyChange != null) {
    changes.write('<keySig sig="${meiKeySig(measure.keyChange!)}"/>');
  }
  if (measure.timeChange != null) {
    changes.write('<meterSig ${_meterAttrs(measure.timeChange!, dotted: false)}'
        '/>');
  }

  _writeLayer(out, 1, measure.elements, changes.toString(),
      measureIndex: index, tuplets: measure.tuplets, lyricsById: lyricsById);
  for (final (n, voice) in [
    (2, measure.voice2),
    (3, measure.voice3),
    (4, measure.voice4),
  ]) {
    if (voice.isNotEmpty) {
      _writeLayer(out, n, voice, '',
          measureIndex: index, lyricsById: lyricsById);
    }
  }
  out.writeln('        </staff>');

  // Ornaments and slurs are control events anchored to a note by its xml:id.
  // A note that carries an ornament but no id of its own gets a deterministic
  // position-derived id (see _meiIdFor) — the same one _writeLayer stamps on
  // the <note> — so the ornament keeps its anchor instead of being dropped.
  final controls = StringBuffer();
  for (final (voiceNum, voice) in [
    (1, measure.elements),
    (2, measure.voice2),
    (3, measure.voice3),
    (4, measure.voice4),
  ]) {
    for (var i = 0; i < voice.length; i++) {
      final element = voice[i];
      if (element is NoteElement && element.ornament != null) {
        final id = _meiIdFor(element, index, voiceNum, i);
        if (id != null) controls.write(_ornamentEvent(element.ornament!, id));
      }
    }
  }
  // A slur is emitted in the measure that holds its start note.
  final measureIds = {
    for (final e in [
      ...measure.elements,
      ...measure.voice2,
      ...measure.voice3,
      ...measure.voice4,
    ])
      if (e.id != null) e.id!,
  };
  for (final slur in score.slurs) {
    if (measureIds.contains(slur.startId)) {
      controls
          .write('<slur startid="#${slur.startId}" endid="#${slur.endId}"/>');
    }
  }
  // Dynamics are `<dynam>` control events anchored to their note by id, the
  // dynamic word (pp…fff, sf…) carried as the element's text.
  for (final dyn in score.dynamics) {
    if (measureIds.contains(dyn.elementId)) {
      controls.write('<dynam startid="#${dyn.elementId}">${dyn.level.name}'
          '</dynam>');
    }
  }
  // A navigation mark (D.C., D.S., segno, coda, fine, …) is a measure-level
  // <repeatMark>; @func carries the model's own name so every variant (incl.
  // the compound al-fine/al-coda forms) round-trips exactly.
  if (measure.navigation != null) {
    controls.write('<repeatMark func="${measure.navigation!.name}"/>');
  }
  if (controls.isNotEmpty) out.writeln('        $controls');
  out.writeln('      </measure>');
}

/// The xml:id used to anchor a note's control events (its ornament). A note
/// keeps its own [NoteElement.id]; an ornamented note that lacks one is given a
/// deterministic, position-derived id (`o<measure>_<voice>_<index>`) so the
/// ornament still has a `startid` to point at — previously such notes silently
/// lost their ornament. Position is unique within a document, so these never
/// collide, and only ornamented notes get one (unornamented id-less notes stay
/// id-free, keeping the output minimal). Returns null when there is nothing to
/// anchor.
String? _meiIdFor(NoteElement e, int measure, int voice, int index) =>
    e.id ?? (e.ornament != null ? 'o${measure}_${voice}_$index' : null);

/// The `<verse>/<syl>` children for a note's [lyrics] (already verse-sorted).
/// `@con` carries the continuation to the next syllable: `d`=hyphen (word
/// continues), `u`=melisma extender, `b`=elision.
String _verses(List<Lyric>? lyrics) {
  if (lyrics == null || lyrics.isEmpty) return '';
  final out = StringBuffer();
  for (final l in lyrics) {
    final con = l.elidesToNext
        ? ' con="b"'
        : l.hyphenToNext
            ? ' con="d"'
            : l.extender
                ? ' con="u"'
                : '';
    out.write('<verse n="${l.verse}"><syl$con>${_escape(l.text)}</syl>'
        '</verse>');
  }
  return out.toString();
}

/// A `<trill>`/`<mordent>`/`<turn>` control event anchored to note [id].
String _ornamentEvent(Ornament ornament, String id) => switch (ornament) {
      Ornament.trill => '<trill startid="#$id"/>',
      Ornament.shortTrill => '<mordent form="upper" startid="#$id"/>',
      Ornament.mordent => '<mordent form="lower" startid="#$id"/>',
      Ornament.turn => '<turn startid="#$id"/>',
      Ornament.invertedTurn => '<turn form="lower" startid="#$id"/>',
      // MEI has no trill-with-accidental sign; fall back to a plain trill.
      Ornament.trillSharp ||
      Ornament.trillFlat ||
      Ornament.trillNatural =>
        '<trill startid="#$id"/>',
    };

void _writeLayer(
    StringBuffer out, int n, List<MusicElement> elements, String prefix,
    {required int measureIndex,
    Map<String, List<Lyric>> lyricsById = const {},
    List<TupletSpan> tuplets = const []}) {
  out.write('          <layer n="$n">$prefix');
  for (var i = 0; i < elements.length; i++) {
    final element = elements[i];
    for (final t in tuplets) {
      if (t.startIndex == i) {
        out.write('<tuplet num="${t.actual}" numbase="${t.normal}">');
      }
    }
    if (element is RestElement) {
      out.write('<rest ${_durAttrs(element.duration)}/>');
    } else if (element is NoteElement) {
      // Grace notes precede the principal note (MEI `<note grace="acc|unacc">`;
      // acc = appoggiatura, unacc = acciaccatura). No duration in the model, so
      // they are written as small eighths.
      if (element.graceNotes.isNotEmpty) {
        final g =
            element.graceStyle == GraceStyle.appoggiatura ? 'acc' : 'unacc';
        for (final pitch in element.graceNotes) {
          out.write('<note grace="$g" dur="8" ${_pitchAttrs(pitch, null)}/>');
        }
      }
      final tie = element.tieToNext ? ' tie="i"' : '';
      final artic = _articAttrs(element.articulations);
      final anchorId = _meiIdFor(element, measureIndex, n, i);
      final xmlId = anchorId == null ? '' : ' xml:id="$anchorId"';
      final verses = element.id == null ? '' : _verses(lyricsById[element.id]);
      if (element.pitches.length == 1) {
        final head = '<note$xmlId ${_durAttrs(element.duration)} '
            '${_pitchAttrs(element.pitches.single, element.showAccidental)}'
            '$tie$artic';
        out.write(verses.isEmpty ? '$head/>' : '$head>$verses</note>');
      } else {
        out.write('<chord$xmlId ${_durAttrs(element.duration)}$tie$artic>');
        for (final pitch in element.pitches) {
          out.write('<note ${_pitchAttrs(pitch, element.showAccidental)}/>');
        }
        out.write('$verses</chord>');
      }
    }
    for (final t in tuplets) {
      if (t.endIndex == i) out.write('</tuplet>');
    }
  }
  out.writeln('</layer>');
}

String _durAttrs(NoteDuration duration) {
  final dots = duration.dots == 0 ? '' : ' dots="${duration.dots}"';
  return 'dur="${_durValues[duration.base]}"$dots';
}

/// MEI `@artic` token per articulation (fermata is a separate `@fermata`).
const meiArtic = {
  Articulation.staccato: 'stacc',
  Articulation.tenuto: 'ten',
  Articulation.accent: 'acc',
  Articulation.marcato: 'marc',
  Articulation.upBow: 'upbow',
  Articulation.downBow: 'dnbow',
};

/// The `@artic`/`@fermata` attributes for an element's [articulations].
String _articAttrs(Set<Articulation> articulations) {
  final tokens = [
    for (final a in Articulation.values)
      if (articulations.contains(a) && meiArtic[a] != null) meiArtic[a],
  ];
  final artic = tokens.isEmpty ? '' : ' artic="${tokens.join(' ')}"';
  final fermata =
      articulations.contains(Articulation.fermata) ? ' fermata="above"' : '';
  return '$artic$fermata';
}

String _pitchAttrs(Pitch pitch, bool? showAccidental) {
  final accidGes =
      pitch.alter == 0 ? '' : ' accid.ges="${_accidCodes[pitch.alter]}"';
  final accid =
      showAccidental == true ? ' accid="${_accidCodes[pitch.alter]}"' : '';
  return 'pname="${pitch.step.name}" oct="${pitch.octave}"$accidGes$accid';
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// A bpm as a compact string (no trailing `.0`).
String _bpm(double bpm) =>
    bpm == bpm.roundToDouble() ? bpm.round().toString() : bpm.toString();
