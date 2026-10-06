import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// GitHub issues #8, #9, #11, #12, #13 and #14 (item 3), reported against the
/// Dvořák 9 "New World" score. (#10, the staccatissimo codepoint, has its own
/// file: smufl_codepoints_test.dart.)
void main() {
  final settings = LayoutSettings(
      metadata: SmuflMetadata.fromJson(jsonDecode(
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync()) as Map<String, Object?>));

  String doc(String measures, {int fifths = 0, String time = '4/4'}) {
    final t = time.split('/');
    return '<score-partwise version="3.1"><part-list><score-part id="P1">'
        '<part-name>V</part-name></score-part></part-list><part id="P1">'
        '<measure number="1"><attributes><divisions>4</divisions>'
        '<key><fifths>$fifths</fifths></key><time><beats>${t[0]}</beats>'
        '<beat-type>${t[1]}</beat-type></time><clef><sign>G</sign>'
        '<line>2</line></clef></attributes>$measures</part></score-partwise>';
  }

  String note(String step, int octave,
          {String type = '16th',
          int duration = 1,
          String extra = '',
          String notations = ''}) =>
      '<note><pitch><step>$step</step><octave>$octave</octave></pitch>'
      '<duration>$duration</duration><voice>1</voice><type>$type</type>'
      '$extra${notations.isEmpty ? '' : '<notations>$notations</notations>'}'
      '</note>';

  List<CurvePrimitive> curves(ScoreLayout l) =>
      l.primitives.whereType<CurvePrimitive>().toList();

  // ------------------------------------------------------------------ #8

  group('#8 slur placement', () {
    // Bar 31 of the violin part: B4 G4 E4 G4 | B4 E5 G5 F#5, stems up then
    // down, one slur over all eight, MuseScore's bezier hints only.
    String bar31({String startAttrs = 'bezier-x="21.9" bezier-y="16.3"'}) {
      const steps = [
        ('B', 4), ('G', 4), ('E', 4), ('G', 4), //
        ('B', 4), ('E', 5), ('G', 5), ('F', 5),
      ];
      final b = StringBuffer();
      for (var i = 0; i < 8; i++) {
        final beam = i % 4 == 0
            ? 'begin'
            : i % 4 == 3
                ? 'end'
                : 'continue';
        b.write(note(steps[i].$1, steps[i].$2,
            extra: '<beam number="1">$beam</beam>',
            notations: i == 0
                ? '<slur type="start" number="1" $startAttrs/>'
                : i == 7
                    ? '<slur type="stop" number="1"/>'
                    : ''));
      }
      return doc('$b</measure>', fifths: 1, time: '2/4');
    }

    test('MusicXML placement, orientation and bezier-y set the side', () {
      SlurPlacement read(String attrs) =>
          scoreFromMusicXml(bar31(startAttrs: attrs)).slurs.single.placement;
      expect(read('placement="above"'), SlurPlacement.above);
      expect(read('placement="below"'), SlurPlacement.below);
      expect(read('orientation="over"'), SlurPlacement.above);
      expect(read('orientation="under"'), SlurPlacement.below);
      expect(read('bezier-y="16.3"'), SlurPlacement.above);
      expect(read('bezier-y="-12"'), SlurPlacement.below);
      expect(read(''), SlurPlacement.auto);
    });

    test('the placement survives MusicXML and MEI', () {
      for (final p in SlurPlacement.values) {
        final s = Score.simple(notes: 'c5:q d5 e5 f5')
            .copyWith(slurs: [Slur('e0', 'e3', placement: p)]);
        expect(scoreFromMusicXml(scoreToMusicXml(s)).slurs.single.placement, p,
            reason: 'MusicXML $p');
        expect(scoreFromMei(scoreToMei(s)).slurs.single.placement, p,
            reason: 'MEI $p');
      }
    });

    test('the reporter\'s bar draws its slur above, close to the notes', () {
      final layout = const LayoutEngine()
          .layout(scoreFromMusicXml(bar31(startAttrs: '')), settings);
      final c = curves(layout).single;
      // Above: the arc bulges up (smaller y) and stays near the staff top —
      // not 8 spaces under it as before.
      expect(c.control1.y, lessThan(c.start.y));
      expect(c.control1.y, greaterThan(-6));
    });

    test('an explicit side wins over the rule', () {
      final s = Score.simple(notes: 'c5:q d5 e5 f5');
      ScoreLayout lay(SlurPlacement p) => const LayoutEngine().layout(
          s.copyWith(slurs: [Slur('e0', 'e3', placement: p)]), settings);
      final up = curves(lay(SlurPlacement.above)).single;
      final down = curves(lay(SlurPlacement.below)).single;
      expect(up.control1.y, lessThan(up.start.y));
      expect(down.control1.y, greaterThan(down.start.y));
    });
  });

  // ------------------------------------------------------------------ #9

  group('#9 hairpins that touch share one line', () {
    test('cresc. then dim. over stems up then down sit level', () {
      final b = StringBuffer()
        ..write('<direction placement="below"><direction-type>'
            '<wedge type="crescendo" number="1"/></direction-type></direction>');
      const steps = [
        ('G', 4), ('F', 4), ('E', 4), ('F', 4), //
        ('B', 4), ('B', 4), ('B', 4), ('B', 4),
      ];
      for (var i = 0; i < 8; i++) {
        if (i == 4) {
          b.write('<direction placement="below"><direction-type>'
              '<wedge type="diminuendo" number="1"/></direction-type>'
              '</direction>');
        }
        b.write(note(steps[i].$1, steps[i].$2));
        if (i == 3 || i == 7) {
          b.write('<direction placement="below"><direction-type>'
              '<wedge type="stop" number="1"/></direction-type></direction>');
        }
      }
      final layout = const LayoutEngine().layout(
          scoreFromMusicXml(doc('$b</measure>', time: '2/4')), settings);
      // Hairpin strokes: id-less slanted lines below the staff. Each starts
      // at its wedge's tip, on the wedge's middle line.
      final strokes = [
        for (final l in layout.primitives.whereType<LinePrimitive>())
          if (l.elementId == null && l.from.y != l.to.y && l.from.y > 4) l,
      ];
      expect(strokes, hasLength(4), reason: 'two wedges, two strokes each');
      final heights = {for (final l in strokes) l.from.y};
      expect(heights, hasLength(1),
          reason: 'wedges at different heights: $heights');
      // The down-stems of the second group reach below the default line, so
      // the shared line is theirs: the first wedge moved down to meet it.
      expect(heights.single, greaterThan(6.2 + 0.05 + 1e-6));
    });

    test('a dynamic at a hairpin end sits on the hairpin line', () {
      final s = Score.simple(notes: 'c4:q d4 a5 b5').copyWith(
        hairpins: const [Hairpin('e0', 'e2', HairpinType.crescendo)],
        dynamics: const [DynamicMarking('e3', DynamicLevel.f)],
      );
      final layout = const LayoutEngine().layout(s, settings);
      final wedge = layout.primitives.whereType<LinePrimitive>().firstWhere(
          (l) =>
              l.elementId == null && l.from.y != l.to.y && l.from.x != l.to.x);
      final forte = layout.primitives
          .whereType<GlyphPrimitive>()
          .firstWhere((g) => g.smuflName == 'dynamicForte');
      // Same line: letters on its baseline + 0.6, the wedge centred + 0.05.
      expect(forte.position.y - 0.6, closeTo(wedge.from.y - 0.05, 1e-9));
      // And the wedge stops short of the letters.
      final wedgeRight = layout.primitives
          .whereType<LinePrimitive>()
          .where((l) =>
              l.elementId == null && l.from.y != l.to.y && l.from.x != l.to.x)
          .map((l) => max2(l.from.x, l.to.x))
          .reduce(max2);
      expect(wedgeRight, lessThan(forte.position.x));
    });
  });

  // ------------------------------------------------------------------ #11

  group('#11 text on a multi-measure rest', () {
    // Bar 1 of the violin part: eight bars' rest, "Adagio" ♪ = 63 over it.
    String part({int bars = 8}) {
      final b = StringBuffer(
          '<attributes><measure-style><multiple-rest>$bars</multiple-rest>'
          '</measure-style></attributes>'
          '<direction placement="above"><direction-type>'
          '<words font-weight="bold">Adagio </words></direction-type>'
          '<direction-type><metronome><beat-unit>eighth</beat-unit>'
          '<per-minute>63</per-minute></metronome></direction-type>'
          '<sound tempo="31.5"/></direction>'
          '<note><rest measure="yes"/><duration>8</duration><voice>1</voice>'
          '</note></measure>');
      for (var i = 2; i <= bars; i++) {
        b.write('<measure number="$i"><note><rest measure="yes"/>'
            '<duration>8</duration><voice>1</voice></note></measure>');
      }
      b.write('<measure number="${bars + 1}">'
          '${note('B', 4, type: 'half', duration: 8)}</measure>');
      return doc(b.toString().replaceFirst('</measure>', '</measure>'),
          fifths: 1, time: '4/8');
    }

    test('lays out, with the text over bar 1', () {
      final score = scoreFromMusicXml(part());
      final systems = layoutSystems(score, settings, maxWidth: 60);
      final text = [
        for (final s in systems.systems)
          for (final t in s.layout.primitives.whereType<TextPrimitive>()) t
      ];
      expect(text.map((t) => t.text), contains('Adagio'));
    });

    test('the covered bars fold into the multi-rest, counted once', () {
      final score = scoreFromMusicXml(part());
      expect(score.measures, hasLength(2));
      expect(score.measures.first.multiRest, 8);
      // 8 bars of 4/8 plus the half note: 4.5 whole notes, not 8 bars more.
      final end = playbackTimeline(score)
          .map((n) => n.start + n.duration)
          .reduce((a, b) => a > b ? a : b);
      expect(end, Fraction(9, 2));
    });

    test('a system keeps every bar instead (its staves must line up)', () {
      final system = staffSystemFromMusicXml(part());
      expect(system.staves.single.measures, hasLength(9));
      expect(system.staves.single.measures.every((m) => m.multiRest == null),
          isTrue);
    });

    test('writing it back emits the covered bars; reading is stable', () {
      final s = Score.simple(
          timeSignature: TimeSignature.fourFour,
          notes: 'c4:w | !mrest=5 | d4:w');
      final xml = scoreToMusicXml(s);
      expect(RegExp('<measure ').allMatches(xml).length, 7);
      expect(xml, contains('<measure number="7">'));
      expect(scoreFromMusicXml(xml), s);
    });
  });

  // ------------------------------------------------------------------ #12

  group('#12 metronome marks are drawn', () {
    final score = Score.simple(
      timeSignature: TimeSignature.fourFour,
      notes: 'c5:q d5 e5 f5 | g5:w | a5:w',
    ).copyWith(
      tempo: const Tempo(63, beatUnit: DurationBase.eighth),
      annotations: const [Annotation('e0', 'Adagio')],
    );
    final withChange = score.copyWith(measures: [
      score.measures[0],
      score.measures[1],
      score.measures[2].copyWith(tempoChange: const Tempo(136)),
    ]);

    test('"Adagio ♪ = 63" over the first beat', () {
      final l = const LayoutEngine().layout(score, settings);
      final glyphs = l.primitives.whereType<GlyphPrimitive>();
      expect(glyphs.map((g) => g.smuflName), contains('metNote8thUp'));
      final texts = l.primitives.whereType<TextPrimitive>().toList();
      expect(texts.map((t) => t.text), containsAll(['Adagio', '= 63']));
      // One run on one baseline: words, then the note, then the value.
      final words = texts.firstWhere((t) => t.text == 'Adagio');
      final value = texts.firstWhere((t) => t.text == '= 63');
      final metNote = glyphs.firstWhere((g) => g.smuflName == 'metNote8thUp');
      expect(value.position.y, words.position.y);
      expect(words.position.x, lessThan(metNote.position.x));
      expect(metNote.position.x, lessThan(value.position.x));
      expect(words.position.y, lessThan(0), reason: 'above the staff');
    });

    test('a tempo change is marked over its bar', () {
      final l = const LayoutEngine().layout(withChange, settings);
      expect(l.primitives.whereType<GlyphPrimitive>().map((g) => g.smuflName),
          contains('metNoteQuarterUp'));
      expect(l.primitives.whereType<TextPrimitive>().map((t) => t.text),
          contains('= 136'));
    });

    test('drawTempoMarks: false leaves them to the app', () {
      final off =
          LayoutSettings(metadata: settings.metadata, drawTempoMarks: false);
      final l = const LayoutEngine().layout(withChange, off);
      expect(
          l.primitives
              .whereType<GlyphPrimitive>()
              .where((g) => g.smuflName.startsWith('metNote')),
          isEmpty);
      // The words are still an ordinary annotation then.
      expect(l.primitives.whereType<TextPrimitive>().map((t) => t.text),
          contains('Adagio'));
    });

    test('a mark on the last bar ends inside the line', () {
      final s = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: 'c5:q d5 e5 f5 | g5:w',
      );
      final marked = s.copyWith(
        measures: [
          s.measures[0],
          s.measures[1].copyWith(tempoChange: const Tempo(136)),
        ],
        annotations: const [Annotation('e4', 'Allegro molto')],
      );
      final l = const LayoutEngine().layout(marked, settings);
      final value = l.primitives
          .whereType<TextPrimitive>()
          .firstWhere((t) => t.text == '= 136');
      // The value's estimated right edge stays within the bars.
      expect(value.position.x + 0.31 * settings.annotationSize * 5,
          lessThanOrEqualTo(l.measureRegions.last.endX + 1e-9));
    });

    test('only the first system states the opening tempo', () {
      final long = Score.simple(
        timeSignature: TimeSignature.fourFour,
        notes: List.filled(16, 'c5:q d5 e5 f5').join(' | '),
      ).copyWith(tempo: const Tempo(100));
      final systems = layoutSystems(long, settings, maxWidth: 40).systems;
      expect(systems.length, greaterThan(1));
      int marks(SystemLayout s) => s.layout.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == '= 100')
          .length;
      expect(marks(systems.first), 1);
      for (final s in systems.skip(1)) {
        expect(marks(s), 0);
      }
    });

    test('a system marks only its top staff', () {
      final l = layoutStaffSystem(StaffSystem([score, score]), settings);
      int marks(ScoreLayout s) => s.primitives
          .whereType<TextPrimitive>()
          .where((t) => t.text == '= 63')
          .length;
      expect(marks(l.staves[0]), 1);
      expect(marks(l.staves[1]), 0);
    });
  });

  // ------------------------------------------------------------------ #13

  group('#13 a part inherits the score-wide tempo', () {
    String twoParts({String lowerDirections = ''}) {
      String bar(int n, String content) =>
          '<measure number="$n">$content</measure>';
      const attrs = '<attributes><divisions>4</divisions><key><fifths>0'
          '</fifths></key><time><beats>4</beats><beat-type>4</beat-type>'
          '</time><clef><sign>G</sign><line>2</line></clef></attributes>';
      const tempo1 = '<direction placement="above"><direction-type><words>'
          'Adagio</words></direction-type><direction-type><metronome>'
          '<beat-unit>eighth</beat-unit><per-minute>63</per-minute>'
          '</metronome></direction-type><sound tempo="31.5"/></direction>';
      const tempo2 = '<direction placement="above"><direction-type><words>'
          'Allegro molto</words></direction-type><sound tempo="136"/>'
          '</direction>';
      String whole(String step) =>
          '<note><pitch><step>$step</step><octave>5</octave></pitch>'
          '<duration>16</duration><voice>1</voice><type>whole</type></note>';
      const rest = '<note><rest measure="yes"/><duration>16</duration>'
          '<voice>1</voice></note>';
      return '<score-partwise version="3.1"><part-list>'
          '<score-part id="P1"><part-name>Fl</part-name></score-part>'
          '<score-part id="P2"><part-name>Vn</part-name></score-part>'
          '</part-list>'
          '<part id="P1">${bar(1, '$attrs$tempo1${whole('C')}')}'
          '${bar(2, whole('D'))}${bar(3, '$tempo2${whole('E')}')}</part>'
          '<part id="P2">${bar(1, '$attrs$lowerDirections$rest')}'
          '${bar(2, rest)}${bar(3, whole('G'))}</part>'
          '</score-partwise>';
    }

    test('tempo, tempo change and tempo words reach part 2', () {
      final vn = scoreFromMusicXml(twoParts(), partIndex: 1);
      expect(vn.tempo, const Tempo(63, beatUnit: DurationBase.eighth));
      expect(vn.measures[2].tempoChange?.bpm, 136);
      expect(vn.annotations.map((a) => a.text),
          containsAll(['Adagio', 'Allegro molto']));
      // Anchored in the right bars.
      final ids0 = vn.measures[0].elements.map((e) => e.id).toSet();
      final ids2 = vn.measures[2].elements.map((e) => e.id).toSet();
      expect(
          ids0.contains(
              vn.annotations.firstWhere((a) => a.text == 'Adagio').elementId),
          isTrue);
      expect(
          ids2.contains(vn.annotations
              .firstWhere((a) => a.text == 'Allegro molto')
              .elementId),
          isTrue);
      // And it lays out.
      expect(() => layoutSystems(vn, settings, maxWidth: 60), returnsNormally);
    });

    test('opt out with inheritGlobalDirections: false', () {
      final vn = scoreFromMusicXml(twoParts(),
          partIndex: 1, inheritGlobalDirections: false);
      expect(vn.tempo, isNull);
      expect(vn.annotations, isEmpty);
    });

    test('the part\'s own marks are kept, not doubled', () {
      final vn = scoreFromMusicXml(
          twoParts(
              lowerDirections: '<direction placement="above">'
                  '<direction-type><words>Adagio</words></direction-type>'
                  '<direction-type><metronome><beat-unit>quarter</beat-unit>'
                  '<per-minute>60</per-minute></metronome></direction-type>'
                  '</direction>'),
          partIndex: 1);
      expect(vn.tempo?.bpm, 60);
      expect(vn.annotations.where((a) => a.text == 'Adagio'), hasLength(1));
    });
  });

  // ------------------------------------------------------------------ #14

  group('#14 a slur written several times is one slur', () {
    // Violini I, bar 256: the export stacks the same slur under numbers 1-4.
    String stacked(int copies) => doc(
          '${note('A', 5, type: 'eighth', duration: 2, notations: [
                for (var n = 1; n <= copies; n++)
                  '<slur type="start" number="$n" bezier-y="19.6"/>'
              ].join())}'
          '${note('D', 6, type: 'eighth', duration: 2, notations: [
                for (var n = 1; n <= copies; n++)
                  '<slur type="stop" number="$n"/>'
              ].join())}'
          '<note><rest/><duration>12</duration><voice>1</voice>'
          '<type>half</type><dot/></note></measure>',
        );

    test('the reader keeps one', () {
      expect(scoreFromMusicXml(stacked(4)).slurs, hasLength(1));
    });

    test('the layout draws one, even when the model holds copies', () {
      final s = Score.simple(notes: 'a5:q d6 r:h').copyWith(
          slurs: const [Slur('e0', 'e1'), Slur('e0', 'e1'), Slur('e0', 'e1')]);
      expect(curves(const LayoutEngine().layout(s, settings)), hasLength(1));
    });
  });

  group('#14 a chord\'s tremolo sits on its free stem', () {
    for (final (name, notes, down) in [
      ('stem down', 'a4+f5:h', true),
      ('stem up', 'e4+a4:h', false),
    ]) {
      test(name, () {
        final s = Score.simple(notes: '$notes $notes');
        final tremolo = s.copyWith(measures: [
          Measure([
            for (final e in s.measures.single.elements)
              (e as NoteElement).copyWith(tremolo: 3),
          ]),
        ]);
        final l = const LayoutEngine().layout(tremolo, settings);
        final strokes = l.primitives
            .whereType<GlyphPrimitive>()
            .firstWhere((g) => g.smuflName == 'tremolo3');
        final heads = l.primitives
            .whereType<GlyphPrimitive>()
            .where((g) =>
                g.smuflName.startsWith('notehead') && g.elementId == 'e0')
            .map((g) => g.position.y)
            .toList();
        // Strokes beyond the outermost head on the stem side.
        if (down) {
          expect(strokes.position.y, greaterThan(heads.reduce(max2)));
        } else {
          expect(strokes.position.y, lessThan(heads.reduce(min2)));
        }
      });
    }
  });
}

double max2(double a, double b) => a > b ? a : b;
double min2(double a, double b) => a < b ? a : b;
