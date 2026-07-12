/// MusicXML export (same subset as the importer): [Score] / [GrandStaff]
/// → `score-partwise` document. Round-trips through `scoreFromMusicXml`.
library;

import '../layout/grand_staff.dart';
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

String _document(
    List<String> parts, List<(String, String)> names, ScoreMetadata meta) {
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
  for (final (id, name) in names) {
    buffer.writeln('    <score-part id="$id">'
        '<part-name>${_escape(name)}</part-name></score-part>');
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
        out.writeln('        <key><fifths>${key.fifths}</fifths></key>');
      }
      final time = index == 0 ? score.timeSignature : measure.timeChange;
      if (time != null) {
        final timeSym = switch (time.symbol) {
          TimeSymbol.common => ' symbol="common"',
          TimeSymbol.cut => ' symbol="cut"',
          TimeSymbol.numeric => '',
        };
        final beatsText = time.components?.join('+') ?? '${time.beats}';
        out.writeln('        <time$timeSym><beats>$beatsText</beats>'
            '<beat-type>${time.beatUnit}</beat-type></time>');
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
    if (measure.voice2.isNotEmpty) {
      // Rewind by voice 1's total duration (in divisions).
      var total = Fraction(0, 1);
      for (var i = 0; i < measure.elements.length; i++) {
        total = total + _quarters(measure.effectiveDurationAt(i));
      }
      final scaled = total * Fraction(divisions, 1);
      out.writeln('      <backup><duration>'
          '${scaled.numerator ~/ scaled.denominator}'
          '</duration></backup>');
      _writeVoice(measure, measure.voice2, '2', const []);
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
        final annotation = _annotationsById[id];
        if (annotation != null) {
          out.writeln('      <harmony><root><root-step>'
              '${_escape(annotation.text[0])}</root-step></root>'
              '<kind text="${_escape(annotation.text.substring(1))}">'
              'other</kind></harmony>');
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
        for (final grace in element.graceNotes) {
          out.writeln('      <note><grace/>${_pitchXml(grace)}'
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
      null => '',
    };
    final tremoloTag = element.tremolo == null
        ? ''
        : '<tremolo type="single">${element.tremolo}</tremolo>';
    if (ornamentTag.isNotEmpty || tremoloTag.isNotEmpty) {
      parts.add('<ornaments>$ornamentTag$tremoloTag</ornaments>');
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
    final out = StringBuffer();
    for (final lyric in lyrics) {
      final syllabic = lyric.hyphenToNext ? 'begin' : 'single';
      final extend = lyric.extender ? '<extend/>' : '';
      out.write('<lyric number="${lyric.verse}">'
          '<syllabic>$syllabic</syllabic>'
          '<text>${_escape(lyric.text)}</text>$extend</lyric>');
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
    final buf = StringBuffer('<figure>');
    var rest = figure;
    final prefix = _figAccidental[rest.isEmpty ? '' : rest[0]];
    if (prefix != null) {
      buf.write('<prefix>$prefix</prefix>');
      rest = rest.substring(1);
    }
    String? suffix;
    if (rest.isNotEmpty) {
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
