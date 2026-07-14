/// MusicXML export (same subset as the importer): [Score] / [GrandStaff]
/// → `score-partwise` document. Round-trips through `scoreFromMusicXml`.
library;

import '../layout/grand_staff.dart';
import '../layout/multi_part.dart';
import '../layout/staff_system.dart';
import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../smufl/glyph_names.dart';
import '../theory/clef.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/pitch.dart';
import '../theory/time_signature.dart';

/// Serializes [score] as a single-part `score-partwise` document.
String scoreToMusicXml(Score score, {String partName = 'Music'}) => _document(
      [_part('P1', score)],
      [('P1', score.metadata.instrument ?? partName)],
      score.metadata,
    );

/// Serializes [grandStaff] as two parts (`P1` upper, `P2` lower).
String grandStaffToMusicXml(GrandStaff grandStaff) => _document(
      [_part('P1', grandStaff.upper), _part('P2', grandStaff.lower)],
      [('P1', 'Upper'), ('P2', 'Lower')],
      grandStaff.upper.metadata,
    );

/// Serializes an N-part [score] as one `score-partwise` document that
/// round-trips through `multiPartScoreFromMusicXml`.
///
/// [partNames] overrides the per-part `<part-name>` (defaults to each part's
/// `metadata.instrument`, else `Part n`). Each part keeps its own
/// `<transpose>` (transposing instruments), so a concert-vs-written distinction
/// survives. `score.brackets` become `<part-group>`s with a `<group-symbol>`
/// (brace/bracket), and each multi-part group in
/// [MultiPartScore.effectiveBarlineGroups] adds a `<group-barline>yes</...>` so
/// the connected barlines round-trip.
String multiPartToMusicXml(MultiPartScore score, {List<String>? partNames}) {
  final parts = score.parts;
  final partXml = <String>[];
  final names = <(String, String)>[];
  for (var i = 0; i < parts.length; i++) {
    final id = 'P${i + 1}';
    partXml.add(_part(id, parts[i]));
    final name = (partNames != null && i < partNames.length)
        ? partNames[i]
        : (parts[i].metadata.instrument ?? 'Part ${i + 1}');
    names.add((id, name));
  }
  final groups = <_PartGroup>[
    for (final b in score.brackets)
      (
        first: b.first,
        last: b.last,
        symbol: b.kind == StaffBracketKind.brace ? 'brace' : 'bracket',
        barline: false,
      ),
    // Only multi-part groups connect barlines (a single-part group is a no-op).
    for (final g in score.effectiveBarlineGroups)
      if (g.last > g.first)
        (first: g.first, last: g.last, symbol: null, barline: true),
  ];
  return _document(partXml, names, const ScoreMetadata(), groups: groups);
}

/// A `<part-group>` to bracket/connect a run of score-parts [first]..[last]
/// (0-based part indices): [symbol] draws a `<group-symbol>` (brace/bracket),
/// [barline] emits `<group-barline>yes</group-barline>` so the parts' barlines
/// connect.
typedef _PartGroup = ({int first, int last, String? symbol, bool barline});

String _document(
    List<String> parts, List<(String, String)> names, ScoreMetadata meta,
    {List<_PartGroup> groups = const []}) {
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<score-partwise version="4.0">');
  if (meta.title != null) {
    buffer.writeln('  <work><work-title>${_escape(meta.title!)}'
        '</work-title></work>');
  }
  if (meta.composer != null ||
      meta.lyricist != null ||
      meta.copyright != null) {
    buffer.writeln('  <identification>');
    if (meta.composer != null) {
      buffer.writeln('    <creator type="composer">'
          '${_escape(meta.composer!)}</creator>');
    }
    if (meta.lyricist != null) {
      buffer.writeln('    <creator type="lyricist">'
          '${_escape(meta.lyricist!)}</creator>');
    }
    if (meta.copyright != null) {
      buffer.writeln('    <rights>${_escape(meta.copyright!)}</rights>');
    }
    buffer.writeln('  </identification>');
  }
  buffer.writeln('  <part-list>');
  for (var i = 0; i < names.length; i++) {
    // Open groups starting here, widest first, so they nest correctly.
    final starting = [
      for (var g = 0; g < groups.length; g++)
        if (groups[g].first == i) g,
    ]..sort((a, b) =>
        (groups[b].last - groups[b].first) -
        (groups[a].last - groups[a].first));
    for (final g in starting) {
      final group = groups[g];
      buffer.write('    <part-group type="start" number="${g + 1}">');
      // `none` keeps a barline-only group from being read back as a bracket.
      buffer.write('<group-symbol>${group.symbol ?? 'none'}</group-symbol>');
      if (group.barline) {
        buffer.write('<group-barline>yes</group-barline>');
      }
      buffer.writeln('</part-group>');
    }
    final (id, name) = names[i];
    buffer.writeln('    <score-part id="$id">'
        '<part-name>${_escape(name)}</part-name></score-part>');
    // Close groups ending here, narrowest first (reverse of opening order).
    final ending = [
      for (var g = 0; g < groups.length; g++)
        if (groups[g].last == i) g,
    ]..sort((a, b) =>
        (groups[a].last - groups[a].first) -
        (groups[b].last - groups[b].first));
    for (final g in ending) {
      buffer.writeln('    <part-group type="stop" number="${g + 1}"/>');
    }
  }
  buffer.writeln('  </part-list>');
  parts.forEach(buffer.write);
  buffer.writeln('</score-partwise>');
  return buffer.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// MusicXML note-type name per [DurationBase].
const _typeNames = {
  DurationBase.breve: 'breve',
  DurationBase.whole: 'whole',
  DurationBase.half: 'half',
  DurationBase.quarter: 'quarter',
  DurationBase.eighth: 'eighth',
  DurationBase.sixteenth: '16th',
  DurationBase.thirtySecond: '32nd',
  DurationBase.sixtyFourth: '64th',
};
String _typeName(DurationBase base) => _typeNames[base]!;

/// A bpm as a compact string (no trailing `.0`).
String _bpmStr(double bpm) =>
    bpm == bpm.roundToDouble() ? bpm.round().toString() : bpm.toString();

/// The value of a (possibly dotted) beat unit in quarter notes.
double _beatQuarters(DurationBase base, int dots) {
  final f = NoteDuration(base, dots: dots).toFraction();
  return f.numerator * 4 / f.denominator;
}

/// Divisions per quarter: the least common multiple of every duration's
/// quarter-denominator, so all `<duration>` values are integers.
int _divisionsFor(Score score) {
  var lcm = 1;
  void include(Fraction quarters) {
    var a = lcm, b = quarters.denominator;
    while (b != 0) {
      final t = a % b;
      a = b;
      b = t;
    }
    lcm = lcm ~/ a * quarters.denominator;
  }

  for (final measure in score.measures) {
    for (var i = 0; i < measure.elements.length; i++) {
      include(_quarters(measure.effectiveDurationAt(i)));
    }
    for (final element in measure.voice2) {
      include(_quarters(_wholeNotes(element.duration)));
    }
  }
  return lcm;
}

/// A whole-note fraction expressed in quarters.
Fraction _quarters(Fraction wholeNotes) => wholeNotes * Fraction(4, 1);

/// A duration's exact whole-note value as a [Fraction].
Fraction _wholeNotes(NoteDuration duration) {
  final (numerator, denominator) = duration.fraction;
  return Fraction(numerator, denominator);
}

String _part(String partId, Score score) {
  final buffer = StringBuffer()..writeln('  <part id="$partId">');
  final divisions = _divisionsFor(score);
  final writer = _PartWriter(score, divisions, buffer);
  writer.write();
  buffer.writeln('  </part>');
  return buffer.toString();
}

class _PartWriter {
  final Score score;
  final int divisions;
  final StringBuffer out;
  _PartWriter(this.score, this.divisions, this.out);

  late final Map<String, List<Lyric>> _lyricsById = () {
    final map = <String, List<Lyric>>{};
    for (final lyric in score.lyrics) {
      (map[lyric.elementId] ??= []).add(lyric);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.verse.compareTo(b.verse));
    }
    return map;
  }();
  late final Map<String, Annotation> _annotationsById = {
    for (final annotation in score.annotations)
      annotation.elementId: annotation,
  };
  late final Map<String, ChordSymbol> _chordSymbolsById = {
    for (final chord in score.chordSymbols) chord.elementId: chord,
  };
  late final Map<String, DynamicLevel> _dynamicsById = {
    for (final marking in score.dynamics) marking.elementId: marking.level,
  };
  late final Map<String, JazzArticulation> _jazzById = {
    for (final mark in score.jazzMarks) mark.noteId: mark.type,
  };
  late final Map<String, FiguredBass> _figuredBassById = {
    for (final fb in score.figuredBass) fb.noteId: fb,
  };
  late final Map<String, BreathSymbol> _breathById = {
    for (final bm in score.breathMarks) bm.noteId: bm.symbol,
  };
  late final Map<String, LaissezVibrer> _laissezVibrerById = {
    for (final lv in score.laissezVibrer) lv.noteId: lv,
  };
  late final Map<String, String> _slurStartsById = {
    for (var i = 0; i < score.slurs.length; i++)
      score.slurs[i].startId: '${i % 6 + 1}',
  };
  late final Map<String, String> _slurStopsById = {
    for (var i = 0; i < score.slurs.length; i++)
      score.slurs[i].endId: '${i % 6 + 1}',
  };
  late final Map<String, String> _glissStartsById = {
    for (var i = 0; i < score.glissandos.length; i++)
      score.glissandos[i].startId: '${i % 6 + 1}',
  };
  late final Map<String, String> _trillStartsById = {
    for (var i = 0; i < score.trillExtensions.length; i++)
      score.trillExtensions[i].startId: '${i % 6 + 1}',
  };
  late final Map<String, String> _trillStopsById = {
    for (var i = 0; i < score.trillExtensions.length; i++)
      score.trillExtensions[i].endId: '${i % 6 + 1}',
  };
  late final Map<String, String> _glissStopsById = {
    for (var i = 0; i < score.glissandos.length; i++)
      score.glissandos[i].endId: '${i % 6 + 1}',
  };

  void write() {
    for (var m = 0; m < score.measures.length; m++) {
      _writeMeasure(m);
    }
  }

  void _writeMeasure(int index) {
    final measure = score.measures[index];
    // Pickups are number="0" implicit="yes" and are not counted; other
    // measures number sequentially from 1.
    final priorNonPickup =
        score.measures.take(index).where((m) => !m.pickup).length;
    final number = measure.pickup ? 0 : priorNonPickup + 1;
    final implicit = measure.pickup ? ' implicit="yes"' : '';
    out.writeln('    <measure number="$number"$implicit>');

    if (index == 0 ||
        measure.clefChange != null ||
        measure.keyChange != null ||
        measure.timeChange != null ||
        measure.multiRest != null) {
      out.writeln('      <attributes>');
      if (index == 0) out.writeln('        <divisions>$divisions</divisions>');
      final key = index == 0 ? score.keySignature : measure.keyChange;
      if (key != null) {
        final custom = key.custom;
        if (custom != null) {
          // Non-traditional key signature: explicit key-step/key-alter pairs.
          out.writeln('        <key>');
          for (final acc in custom) {
            out.writeln(
                '          <key-step>${acc.step.name.toUpperCase()}</key-step>'
                '<key-alter>${acc.alter}</key-alter>');
          }
          out.writeln('        </key>');
        } else {
          out.writeln('        <key><fifths>${key.fifths}</fifths></key>');
        }
      }
      final time = index == 0 ? score.timeSignature : measure.timeChange;
      if (time != null) {
        final timeSym = switch (time.symbol) {
          TimeSymbol.common => ' symbol="common"',
          TimeSymbol.cut => ' symbol="cut"',
          TimeSymbol.numeric => '',
        };
        final beatsText = time.components?.join('+') ?? '${time.beats}';
        final alt = time.alternate;
        final inter = alt == null
            ? ''
            : '<interchangeable>'
                '<beats>${alt.components?.join('+') ?? alt.beats}</beats>'
                '<beat-type>${alt.beatUnit}</beat-type></interchangeable>';
        out.writeln('        <time$timeSym><beats>$beatsText</beats>'
            '<beat-type>${time.beatUnit}</beat-type>$inter</time>');
      }
      final clef = index == 0 ? score.clef : measure.clefChange;
      if (clef != null) {
        final (sign, line, octave) = switch (clef) {
          Clef.treble => ('G', 2, 0),
          Clef.bass => ('F', 4, 0),
          Clef.alto => ('C', 3, 0),
          Clef.tenor => ('C', 4, 0),
          Clef.treble8va => ('G', 2, 1),
          Clef.treble8vb => ('G', 2, -1),
          Clef.bass8vb => ('F', 4, -1),
          Clef.frenchViolin => ('G', 1, 0),
          Clef.soprano => ('C', 1, 0),
          Clef.mezzoSoprano => ('C', 2, 0),
          Clef.baritone => ('F', 3, 0),
          Clef.subbass => ('F', 5, 0),
          Clef.percussion => ('percussion', 2, 0),
        };
        out.writeln('        <clef><sign>$sign</sign>'
            '<line>$line</line>'
            '${octave == 0 ? '' : '<clef-octave-change>$octave</clef-octave-change>'}'
            '</clef>');
      }
      final transposition = index == 0 ? score.transposition : null;
      if (transposition != null) {
        final sign = transposition.down ? -1 : 1;
        final diatonic = (transposition.interval.number - 1) * sign;
        final chromatic = transposition.interval.semitones * sign;
        final octaveChange = transposition.octaves * sign;
        out.writeln('        <transpose>'
            '<diatonic>$diatonic</diatonic>'
            '<chromatic>$chromatic</chromatic>'
            '${octaveChange == 0 ? '' : '<octave-change>$octaveChange</octave-change>'}'
            '</transpose>');
      }
      if (measure.multiRest != null) {
        out.writeln('        <measure-style><multiple-rest>'
            '${measure.multiRest}</multiple-rest></measure-style>');
      }
      out.writeln('      </attributes>');
    }

    // A metronome mark: the initial tempo opens the first measure; a
    // `Measure.tempoChange` opens the measure it takes effect on.
    final tempo = index == 0 ? score.tempo : measure.tempoChange;
    if (tempo != null) {
      final unit = _typeName(tempo.beatUnit);
      final dotTags = '<beat-unit-dot/>' * tempo.dots;
      final sound =
          _bpmStr(tempo.bpm * _beatQuarters(tempo.beatUnit, tempo.dots));
      out.writeln('      <direction placement="above"><direction-type>'
          '<metronome><beat-unit>$unit</beat-unit>$dotTags'
          '<per-minute>${_bpmStr(tempo.bpm)}</per-minute></metronome>'
          '</direction-type><sound tempo="$sound"/></direction>');
    }

    if (measure.startRepeat) {
      out.writeln('      <barline location="left">'
          '<repeat direction="forward"/></barline>');
    }
    if (measure.volta != null) {
      out.writeln('      <barline location="left">'
          '<ending number="${measure.volta}" type="start"/></barline>');
    }
    // Navigation targets (segno/coda) open the measure.
    final nav = measure.navigation;
    if (nav != null && nav.isTarget) {
      out.writeln('      <direction><direction-type>'
          '<${nav == NavigationMark.segno ? 'segno' : 'coda'}/>'
          '</direction-type></direction>');
    }

    _writeVoice(measure, measure.elements, '1', measure.tuplets);
    // Each further voice: rewind (backup) by the just-written voice's total
    // duration to the measure start, then write it.
    var lastVoice = measure.elements;
    var lastIsVoice1 = true;
    for (final (elements, label) in [
      (measure.voice2, '2'),
      (measure.voice3, '3'),
      (measure.voice4, '4'),
    ]) {
      if (elements.isEmpty) continue;
      var total = Fraction(0, 1);
      for (var i = 0; i < lastVoice.length; i++) {
        total = total +
            (lastIsVoice1
                ? _quarters(measure.effectiveDurationAt(i))
                : _quarters(_wholeNotes(lastVoice[i].duration)));
      }
      final scaled = total * Fraction(divisions, 1);
      out.writeln('      <backup><duration>'
          '${scaled.numerator ~/ scaled.denominator}'
          '</duration></backup>');
      _writeVoice(measure, elements, label, const []);
      lastVoice = elements;
      lastIsVoice1 = false;
    }

    // Navigation instructions (D.C./D.S./To Coda/Fine) close the measure.
    if (nav != null && !nav.isTarget) {
      final sound = switch (nav) {
        NavigationMark.toCoda => '<sound tocoda="coda"/>',
        NavigationMark.daCapo ||
        NavigationMark.daCapoAlFine ||
        NavigationMark.daCapoAlCoda =>
          '<sound dacapo="yes"/>',
        NavigationMark.dalSegno ||
        NavigationMark.dalSegnoAlFine ||
        NavigationMark.dalSegnoAlCoda =>
          '<sound dalsegno="segno"/>',
        NavigationMark.fine => '<sound fine="yes"/>',
        _ => '',
      };
      out.writeln('      <direction><direction-type><words>'
          '${_escape(SmuflGlyph.navigationLabel(nav)!)}'
          '</words></direction-type>$sound</direction>');
    }

    if (measure.endRepeat) {
      out.writeln('      <barline location="right">'
          '<repeat direction="backward"/></barline>');
    } else {
      final barStyle = switch (measure.barline) {
        BarlineStyle.normal => null,
        BarlineStyle.doubleBar => 'light-light',
        BarlineStyle.finalBar => 'light-heavy',
        BarlineStyle.heavy => 'heavy',
        BarlineStyle.dashed => 'dashed',
        BarlineStyle.dotted => 'dotted',
        BarlineStyle.tick => 'tick',
        BarlineStyle.short => 'short',
        BarlineStyle.reverseFinal => 'heavy-light',
        BarlineStyle.none => 'none',
      };
      if (barStyle != null) {
        out.writeln('      <barline location="right">'
            '<bar-style>$barStyle</bar-style></barline>');
      }
    }
    out.writeln('    </measure>');
  }

  void _writeVoice(
    Measure measure,
    List<MusicElement> elements,
    String voice,
    List<TupletSpan> tuplets,
  ) {
    for (var i = 0; i < elements.length; i++) {
      final element = elements[i];
      final id = element.id;
      final quarters = voice == '1'
          ? _quarters(measure.effectiveDurationAt(i))
          : _quarters(_wholeNotes(element.duration));
      final scaled = quarters * Fraction(divisions, 1);
      final durationDivisions = scaled.numerator ~/ scaled.denominator;

      TupletSpan? span;
      for (final tuplet in tuplets) {
        if (i >= tuplet.startIndex && i <= tuplet.endIndex) span = tuplet;
      }

      if (id != null) {
        final level = _dynamicsById[id];
        if (level != null) {
          out.writeln('      <direction><direction-type><dynamics>'
              '<${level.name}/></dynamics></direction-type></direction>');
        }
        for (final hairpin in score.hairpins) {
          if (hairpin.startId == id) {
            final type = hairpin.type == HairpinType.crescendo
                ? 'crescendo'
                : 'diminuendo';
            out.writeln('      <direction><direction-type>'
                '<wedge type="$type"/></direction-type></direction>');
          }
        }
        for (final ottava in score.ottavas) {
          if (ottava.startId == id) {
            out.writeln('      <direction><direction-type>'
                '<octave-shift type="${ottava.down ? 'up' : 'down'}" '
                'size="8"/></direction-type></direction>');
          }
        }
        for (final pedal in score.pedals) {
          if (pedal.startId == id) {
            out.writeln('      <direction><direction-type>'
                '<pedal type="start" line="no"/></direction-type></direction>');
          }
        }
        final chord = _chordSymbolsById[id];
        if (chord != null) {
          out.write('      <harmony><root>'
              '<root-step>${chord.root.step.name.toUpperCase()}</root-step>');
          if (chord.root.alter != 0) {
            out.write('<root-alter>${chord.root.alter}</root-alter>');
          }
          out.write('</root><kind>${chord.quality.musicXmlKind}</kind>');
          final bass = chord.bass;
          if (bass != null) {
            out.write('<bass><bass-step>${bass.step.name.toUpperCase()}'
                '</bass-step>');
            if (bass.alter != 0) {
              out.write('<bass-alter>${bass.alter}</bass-alter>');
            }
            out.write('</bass>');
          }
          out.writeln('</harmony>');
        }
        final annotation = _annotationsById[id];
        if (annotation != null) {
          out.writeln('      <direction><direction-type><words>'
              '${_escape(annotation.text)}</words></direction-type></direction>');
        }
        final figuredBass = _figuredBassById[id];
        if (figuredBass != null) {
          out.write('      <figured-bass>');
          for (final figure in figuredBass.figures) {
            out.write(_figureXml(figure));
          }
          out.writeln('</figured-bass>');
        }
      }

      if (element is RestElement) {
        out.writeln('      <note><rest/>'
            '<duration>$durationDivisions</duration>'
            '<voice>$voice</voice>${_typeAndDots(element.duration)}</note>');
      } else if (element is NoteElement) {
        final slash =
            element.graceStyle == GraceStyle.acciaccatura ? 'yes' : 'no';
        for (final grace in element.graceNotes) {
          out.writeln('      <note><grace slash="$slash"/>${_pitchXml(grace)}'
              '<type>eighth</type><voice>$voice</voice></note>');
        }
        for (var p = 0; p < element.pitches.length; p++) {
          out.write('      <note>');
          if (p > 0) out.write('<chord/>');
          out.write(_pitchXml(element.pitches[p]));
          out.write('<duration>$durationDivisions</duration>');
          if (element.tieToNext) out.write('<tie type="start"/>');
          out.write('<voice>$voice</voice>');
          out.write(_typeAndDots(element.duration));
          if (element.showAccidental == true && p == 0) {
            out.write('<accidental>'
                '${_accidentalName(element.pitches[p].alter)}</accidental>');
          }
          if (span != null) {
            out.write('<time-modification>'
                '<actual-notes>${span.actual}</actual-notes>'
                '<normal-notes>${span.normal}</normal-notes>'
                '</time-modification>');
          }
          final head = _noteheadName(element.notehead);
          if (head != null) out.write('<notehead>$head</notehead>');
          if (p == 0) out.write(_notationsXml(element, i, span));
          if (p == 0 && id != null) out.write(_lyricXml(id));
          out.writeln('</note>');
        }
      }

      // Wedges/ottavas stop right after their end note (the importer
      // anchors a stop on the most recently read note).
      if (id != null) {
        for (final hairpin in score.hairpins) {
          if (hairpin.endId == id) {
            out.writeln('      <direction><direction-type>'
                '<wedge type="stop"/></direction-type></direction>');
          }
        }
        for (final ottava in score.ottavas) {
          if (ottava.endId == id) {
            out.writeln('      <direction><direction-type>'
                '<octave-shift type="stop" size="8"/>'
                '</direction-type></direction>');
          }
        }
        for (final pedal in score.pedals) {
          if (pedal.endId == id) {
            out.writeln('      <direction><direction-type>'
                '<pedal type="stop" line="no"/></direction-type></direction>');
          }
        }
      }
    }
  }

  String _notationsXml(NoteElement element, int index, TupletSpan? span) {
    final parts = <String>[];
    final id = element.id;
    if (id != null) {
      final start = _slurStartsById[id];
      if (start != null) parts.add('<slur type="start" number="$start"/>');
      final stop = _slurStopsById[id];
      if (stop != null) parts.add('<slur type="stop" number="$stop"/>');
      final gStart = _glissStartsById[id];
      if (gStart != null) {
        parts.add('<slide type="start" line-type="solid" number="$gStart"/>');
      }
      final gStop = _glissStopsById[id];
      if (gStop != null) parts.add('<slide type="stop" number="$gStop"/>');
      final lv = _laissezVibrerById[id];
      if (lv != null) {
        final orient = lv.down == null
            ? ''
            : ' orientation="'
                '${lv.down! ? 'under' : 'over'}"';
        parts.add('<tied type="let-ring"$orient/>');
      }
    }
    if (span != null && index == span.startIndex) {
      parts.add('<tuplet type="start"/>');
    }
    if (span != null && index == span.endIndex) {
      parts.add('<tuplet type="stop"/>');
    }
    if (element.articulations.contains(Articulation.fermata)) {
      parts.add('<fermata/>');
    }
    final ornamentTag = switch (element.ornament) {
      Ornament.trill => '<trill-mark/>',
      Ornament.shortTrill => '<inverted-mordent/>',
      Ornament.mordent => '<mordent/>',
      Ornament.turn => '<turn/>',
      Ornament.invertedTurn => '<inverted-turn/>',
      // A trill-with-accidental: a trill-mark plus an accidental-mark above.
      Ornament.trillSharp =>
        '<trill-mark/><accidental-mark placement="above">sharp</accidental-mark>',
      Ornament.trillFlat =>
        '<trill-mark/><accidental-mark placement="above">flat</accidental-mark>',
      Ornament.trillNatural =>
        '<trill-mark/><accidental-mark placement="above">natural'
            '</accidental-mark>',
      null => '',
    };
    final tremoloTag = element.tremolo == null
        ? ''
        : '<tremolo type="single">${element.tremolo}</tremolo>';
    // Extended-trill wavy lines (a trill-mark + wavy-line start on the first
    // note, a wavy-line stop on the last).
    final wavyTag = StringBuffer();
    final wavyStart = id == null ? null : _trillStartsById[id];
    if (wavyStart != null) {
      if (ornamentTag.isEmpty) wavyTag.write('<trill-mark/>');
      wavyTag.write('<wavy-line type="start" number="$wavyStart"/>');
    }
    final wavyStop = id == null ? null : _trillStopsById[id];
    if (wavyStop != null) {
      wavyTag.write('<wavy-line type="stop" number="$wavyStop"/>');
    }
    if (ornamentTag.isNotEmpty || tremoloTag.isNotEmpty || wavyTag.isNotEmpty) {
      parts.add('<ornaments>$ornamentTag$tremoloTag$wavyTag</ornaments>');
    }
    final jazz = id == null ? null : _jazzById[id];
    final marks = <String>[
      if (element.articulations.contains(Articulation.staccato)) '<staccato/>',
      if (element.articulations.contains(Articulation.tenuto)) '<tenuto/>',
      if (element.articulations.contains(Articulation.accent)) '<accent/>',
      if (element.articulations.contains(Articulation.marcato))
        '<strong-accent/>',
      if (jazz == JazzArticulation.scoop) '<scoop/>',
      if (jazz == JazzArticulation.plop) '<plop/>',
      if (jazz == JazzArticulation.doit) '<doit/>',
      if (jazz == JazzArticulation.fall) '<falloff/>',
      if (id != null && _breathById[id] == BreathSymbol.comma) '<breath-mark/>',
      if (id != null && _breathById[id] == BreathSymbol.caesura) '<caesura/>',
    ];
    if (marks.isNotEmpty) {
      parts.add('<articulations>${marks.join()}</articulations>');
    }
    // <technical>: up-/down-bow string marks and fingering digits.
    final technical = <String>[
      if (element.articulations.contains(Articulation.upBow)) '<up-bow/>',
      if (element.articulations.contains(Articulation.downBow)) '<down-bow/>',
      for (final f in element.fingerings) '<fingering>$f</fingering>',
    ];
    if (technical.isNotEmpty) {
      parts.add('<technical>${technical.join()}</technical>');
    }
    if (element.arpeggio != null) {
      parts.add('<arpeggiate direction="${element.arpeggio!.name}"/>');
    }
    return parts.isEmpty ? '' : '<notations>${parts.join()}</notations>';
  }

  String _lyricXml(String id) {
    final lyrics = _lyricsById[id];
    if (lyrics == null) return '';
    // Syllables in the same verse on this one note are an elision group — one
    // <lyric> with the texts separated by <elision>.
    final byVerse = <int, List<Lyric>>{};
    for (final l in lyrics) {
      (byVerse[l.verse] ??= []).add(l);
    }
    final out = StringBuffer();
    for (final verse in byVerse.keys.toList()..sort()) {
      final syllables = byVerse[verse]!;
      final syllabic = syllables.first.hyphenToNext ? 'begin' : 'single';
      final extend = syllables.last.extender ? '<extend/>' : '';
      out.write('<lyric number="$verse"><syllabic>$syllabic</syllabic>');
      for (var i = 0; i < syllables.length; i++) {
        if (i > 0) out.write('<elision>‿</elision>');
        out.write('<text>${_escape(syllables[i].text)}</text>');
      }
      out.write('$extend</lyric>');
    }
    return out.toString();
  }

  static String _pitchXml(Pitch pitch) {
    final alter = pitch.alter == 0 ? '' : '<alter>${pitch.alter}</alter>';
    return '<pitch><step>${pitch.step.name.toUpperCase()}</step>$alter'
        '<octave>${pitch.octave}</octave></pitch>';
  }

  static String _typeAndDots(NoteDuration duration) {
    const names = {
      DurationBase.breve: 'breve',
      DurationBase.whole: 'whole',
      DurationBase.half: 'half',
      DurationBase.quarter: 'quarter',
      DurationBase.eighth: 'eighth',
      DurationBase.sixteenth: '16th',
      DurationBase.thirtySecond: '32nd',
      DurationBase.sixtyFourth: '64th',
    };
    return '<type>${names[duration.base]}</type>${'<dot/>' * duration.dots}';
  }

  // A figured-bass figure string → <figure> with a leading-accidental prefix,
  // the digits as <figure-number>, and a trailing +/accidental as <suffix>.
  static const _figAccidental = {
    '#': 'sharp',
    '♯': 'sharp',
    'b': 'flat',
    '♭': 'flat',
    'n': 'natural',
    '♮': 'natural',
  };
  static String _figureXml(String figure) {
    if (figure.isEmpty) return '<figure/>';
    // A '_' row is a held-figure continuation: an empty figure with an extend.
    if (figure == '_') return '<figure><extend/></figure>';
    final buf = StringBuffer('<figure>');
    var rest = figure;
    final prefix = _figAccidental[rest.isEmpty ? '' : rest[0]];
    if (prefix != null) {
      buf.write('<prefix>$prefix</prefix>');
      rest = rest.substring(1);
    }
    String? suffix;
    if (rest.contains(r'\')) {
      // A slashed (raised) digit round-trips as MusicXML <suffix>slash</suffix>.
      suffix = 'slash';
      rest = rest.replaceAll(r'\', '');
    } else if (rest.isNotEmpty) {
      final last = rest[rest.length - 1];
      if (last == '+') {
        suffix = 'sharp';
        rest = rest.substring(0, rest.length - 1);
      } else if (_figAccidental.containsKey(last)) {
        suffix = _figAccidental[last];
        rest = rest.substring(0, rest.length - 1);
      }
    }
    final number = rest.replaceAll(RegExp(r'[^0-9]'), '');
    if (number.isNotEmpty) buf.write('<figure-number>$number</figure-number>');
    if (suffix != null) buf.write('<suffix>$suffix</suffix>');
    return (buf..write('</figure>')).toString();
  }

  static String? _noteheadName(NoteheadShape shape) => switch (shape) {
        NoteheadShape.normal => null,
        NoteheadShape.x => 'x',
        NoteheadShape.diamond => 'diamond',
        NoteheadShape.triangleUp => 'triangle',
        NoteheadShape.slash => 'slash',
        NoteheadShape.circleX => 'circle-x',
      };

  static String _accidentalName(int alter) => switch (alter) {
        2 => 'double-sharp',
        1 => 'sharp',
        -1 => 'flat',
        -2 => 'flat-flat',
        _ => 'natural',
      };
}
