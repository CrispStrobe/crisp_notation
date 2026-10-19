import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Nested tuplet spans: an element inside several sounds the product of their
/// ratios, in the model, the layout and the writers and readers.

late final LayoutSettings settings;

NoteElement _note(Step step, NoteDuration d, String id) =>
    NoteElement.note(Pitch(step, octave: 5), d, id: id);

/// A quarter, then a triplet of eighths whose middle one is itself a
/// triplet of sixteenths, filling a 2/4 bar:
/// `c4 \tuplet 3/2 { d8 \tuplet 3/2 { e16 f g } a8 }`.
Score _nested({bool outerHidden = false}) => Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.twoFour,
      measures: [
        Measure(
          [
            NoteElement.note(
                const Pitch(Step.c, octave: 5), NoteDuration.quarter,
                id: 'q'),
            _note(Step.d, NoteDuration.eighth, 'a'),
            _note(Step.e, NoteDuration.sixteenth, 'b'),
            _note(Step.f, NoteDuration.sixteenth, 'c'),
            _note(Step.g, NoteDuration.sixteenth, 'd'),
            _note(Step.a, NoteDuration.eighth, 'e'),
          ],
          tuplets: [
            const TupletSpan(2, 4, actual: 3, normal: 2),
            TupletSpan(1, 5, actual: 3, normal: 2, hidden: outerHidden),
          ],
        ),
      ],
    );

List<Fraction> _sounding(Score s) => [
      for (final m in s.measures)
        for (var i = 0; i < m.elements.length; i++) m.effectiveDurationAt(i),
    ];

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  final outer = Fraction(1, 12); // a triplet eighth
  final inner = Fraction(1, 36); // a triplet sixteenth inside it

  test('every covering span scales an element, whatever the list order', () {
    expect(_sounding(_nested()),
        [Fraction(1, 4), outer, inner, inner, inner, outer]);
    final m = _nested().measures.single;
    expect(m.totalDuration, Fraction(1, 2));
    // The order the spans are listed in does not matter.
    final swapped = m.copyWith(tuplets: m.tuplets.reversed.toList());
    expect(swapped.effectiveDurationAt(3), inner);
    expect(m.tupletsAt(3).map((t) => t.endIndex), [5, 4]);
    expect(m.tupletsAt(1).map((t) => t.endIndex), [5]);
    expect(m.tupletsAt(0), isEmpty);
  });

  group('layout', () {
    int digits(ScoreLayout l, int d) => l.primitives
        .whereType<GlyphPrimitive>()
        .where((g) => g.smuflName == SmuflGlyph.tupletDigit(d))
        .length;

    test('nested spans each draw a bracket, the outer beyond the inner', () {
      final layout = const LayoutEngine().layout(_nested(), settings);
      final threes = layout.primitives
          .whereType<GlyphPrimitive>()
          .where((g) => g.smuflName == SmuflGlyph.tupletDigit(3))
          .map((g) => g.position.y)
          .toList();
      expect(threes, hasLength(2));
      // Both on one side of the staff, the outer one farther out: they do
      // not sit on top of each other.
      expect((threes[0] - threes[1]).abs(), greaterThan(1.0));
    });

    test('a hidden outer span draws nothing', () {
      final layout =
          const LayoutEngine().layout(_nested(outerHidden: true), settings);
      expect(digits(layout, 3), 1);
    });

    test('spans that cross without nesting still fail loudly', () {
      final m = _nested().measures.single.copyWith(tuplets: const [
        TupletSpan(1, 3, actual: 3, normal: 2),
        TupletSpan(2, 4, actual: 3, normal: 2),
      ]);
      expect(
        () => const LayoutEngine()
            .layout(Score(clef: Clef.treble, measures: [m]), settings),
        throwsArgumentError,
      );
    });
  });

  group('MusicXML', () {
    test('the time-modification is the product, with a bracket per level', () {
      final xml = scoreToMusicXml(_nested());
      expect(
          RegExp('<actual-notes>9</actual-notes><normal-notes>4'
                  '</normal-notes>')
              .allMatches(xml)
              .length,
          3);
      expect(
          RegExp('<actual-notes>3</actual-notes><normal-notes>2'
                  '</normal-notes>')
              .allMatches(xml)
              .length,
          2);
      expect(xml, contains('<tuplet type="start" number="2">'));
      expect(xml, contains('<tuplet type="stop" number="2"/>'));
      expect(
          xml,
          contains('<tuplet-actual><tuplet-number>3</tuplet-number>'
              '</tuplet-actual>'));
    });

    test('nested brackets read back as nested spans', () {
      final back = scoreFromMusicXml(scoreToMusicXml(_nested()));
      expect(_sounding(back), _sounding(_nested()));
      final spans = back.measures.single.tuplets;
      expect(spans.where((t) => !t.hidden).map((t) => (t.actual, t.normal)),
          [(3, 2), (3, 2)]);
    });

    test('a hidden outer span reads back as hidden timing', () {
      final score = _nested(outerHidden: true);
      final xml = scoreToMusicXml(score);
      expect(xml, isNot(contains('number="2"')));
      final back = scoreFromMusicXml(xml);
      expect(_sounding(back), _sounding(score));
      final m = back.measures.single;
      expect(m.tuplets.where((t) => !t.hidden).single.startIndex, 2);
    });
  });

  /// The spans of [s]'s single bar as (start, end, actual, normal, hidden),
  /// outermost first.
  List<(int, int, int, int, bool)> spansOf(Score s) => [
        for (final t in TupletSpan.outermostFirst(s.measures.single.tuplets))
          (t.startIndex, t.endIndex, t.actual, t.normal, t.hidden),
      ];

  List<NoteDuration> written(Score s) =>
      [for (final e in s.measures.single.elements) e.duration];

  test('kern writes the combined ratio', () {
    final back = scoreFromKern(scoreToKern(_nested()));
    expect(_sounding(back), _sounding(_nested()));
  });

  group('MEI', () {
    test('nested <tuplet>s read back as nested spans', () {
      final mei = scoreToMei(_nested());
      expect(mei, contains('<tuplet num="3" numbase="2"><note'));
      final back = scoreFromMei(mei);
      expect(_sounding(back), _sounding(_nested()));
      expect(spansOf(back), spansOf(_nested()));
    });

    test('a hidden span is a <tuplet> that draws nothing', () {
      final score = _nested(outerHidden: true);
      final mei = scoreToMei(score);
      expect(
          mei,
          contains('<tuplet num="3" numbase="2" bracket.visible="false" '
              'num.visible="false">'));
      final back = scoreFromMei(mei);
      expect(_sounding(back), _sounding(score));
      expect(spansOf(back), spansOf(score));
    });

    test('a <tupletSpan> nested in a <tuplet> is kept, a restated one not', () {
      String mei(String spans) => '''
<mei xmlns="http://www.music-encoding.org/ns/mei"><music><body><mdiv><score>
<scoreDef meter.count="2" meter.unit="4"><staffGrp><staffDef n="1" lines="5" clef.shape="G" clef.line="2"/></staffGrp></scoreDef>
<section><measure n="1"><staff n="1"><layer n="1">
<note dur="4" pname="c" oct="5"/>
<tuplet num="3" numbase="2"><note dur="8" pname="d" oct="5"/>
<note xml:id="b" dur="16" pname="e" oct="5"/><note dur="16" pname="f" oct="5"/><note xml:id="d" dur="16" pname="g" oct="5"/>
<note dur="8" pname="a" oct="5"/></tuplet>
</layer></staff>$spans</measure></section></score></mdiv></body></music></mei>''';
      final nested =
          scoreFromMei(mei('<tupletSpan startid="#b" endid="#d" num="3" '
              'numbase="2"/>'));
      // Same ratio as the enclosing tuplet: read as a restatement of it.
      expect(spansOf(nested), [(1, 5, 3, 2, false)]);
      final quint =
          scoreFromMei(mei('<tupletSpan startid="#b" endid="#d" num="5" '
              'numbase="4"/>'));
      expect(spansOf(quint), [(1, 5, 3, 2, false), (2, 4, 5, 4, false)]);
    });
  });

  group('MuseScore', () {
    test('a <Tuplet> inside a <Tuplet> reads back nested', () {
      final mscx = scoreToMscx(_nested());
      expect(RegExp('<Tuplet>').allMatches(mscx).length, 2);
      expect(RegExp('<endTuplet/>').allMatches(mscx).length, 2);
      final back = scoreFromMscx(mscx);
      expect(_sounding(back), _sounding(_nested()));
      expect(spansOf(back), spansOf(_nested()));
    });

    test('the outer base note is its own, not its first note\'s', () {
      // The outer triplet OPENS on the inner one's first sixteenth.
      final score = Score(
        clef: Clef.treble,
        timeSignature: TimeSignature.twoFour,
        measures: [
          Measure([
            NoteElement.note(
                const Pitch(Step.c, octave: 5), NoteDuration.quarter),
            _note(Step.e, NoteDuration.sixteenth, 'b'),
            _note(Step.f, NoteDuration.sixteenth, 'c'),
            _note(Step.g, NoteDuration.sixteenth, 'd'),
            _note(Step.a, NoteDuration.eighth, 'e'),
            _note(Step.b, NoteDuration.eighth, 'f'),
          ], tuplets: const [
            TupletSpan(1, 5, actual: 3, normal: 2),
            TupletSpan(1, 3, actual: 3, normal: 2),
          ]),
        ],
      );
      final mscx = scoreToMscx(score);
      expect(mscx, contains('<baseNote>eighth</baseNote>'));
      expect(mscx, contains('<baseNote>16th</baseNote>'));
      expect(_sounding(scoreFromMscx(mscx)), _sounding(score));
    });

    test('a hidden span shows neither number nor bracket', () {
      final score = _nested(outerHidden: true);
      final mscx = scoreToMscx(score);
      expect(mscx, contains('<numberType>2</numberType>'));
      final back = scoreFromMscx(mscx);
      expect(_sounding(back), _sounding(score));
      expect(spansOf(back), spansOf(score));
    });

    test('MuseScore 2 tuplets by id, nested through a parent reference', () {
      final back = scoreFromMscx('''
<museScore version="2.06"><Score><Part><Staff id="1"/></Part>
<Staff id="1"><Measure number="1">
<TimeSig><sigN>2</sigN><sigD>4</sigD></TimeSig>
<Chord><durationType>quarter</durationType><Note><pitch>72</pitch><tpc>14</tpc></Note></Chord>
<Tuplet id="1"><normalNotes>2</normalNotes><actualNotes>3</actualNotes><baseNote>eighth</baseNote></Tuplet>
<Chord><Tuplet>1</Tuplet><durationType>eighth</durationType><Note><pitch>74</pitch><tpc>16</tpc></Note></Chord>
<Tuplet id="2"><Tuplet>1</Tuplet><normalNotes>2</normalNotes><actualNotes>3</actualNotes><baseNote>16th</baseNote></Tuplet>
<Chord><Tuplet>2</Tuplet><durationType>16th</durationType><Note><pitch>76</pitch><tpc>18</tpc></Note></Chord>
<Chord><Tuplet>2</Tuplet><durationType>16th</durationType><Note><pitch>77</pitch><tpc>13</tpc></Note></Chord>
<Chord><Tuplet>2</Tuplet><durationType>16th</durationType><Note><pitch>79</pitch><tpc>15</tpc></Note></Chord>
<Chord><Tuplet>1</Tuplet><durationType>eighth</durationType><Note><pitch>81</pitch><tpc>17</tpc></Note></Chord>
</Measure></Staff></Score></museScore>''');
      expect(_sounding(back), _sounding(_nested()));
      expect(spansOf(back), spansOf(_nested()));
    });
  });

  group('LilyPond', () {
    test('a \\times inside a \\times sounds both ratios', () {
      final s = scoreFromLilyPond(
          r"{ \time 2/4 c''4 \tuplet 3/2 { d''8 \tuplet 3/2 { e''16 f'' g'' } a''8 } }");
      expect(_sounding(s), _sounding(_nested()));
    });

    test('nested and hidden spans round-trip through the writer', () {
      for (final hidden in [false, true]) {
        final score = _nested(outerHidden: hidden);
        final ly = scoreToLilyPond(score);
        expect(ly,
            contains(hidden ? r'\scaleDurations 2/3 {' : r'\tuplet 3/2 { d'));
        final back = scoreFromLilyPond(ly);
        expect(_sounding(back), _sounding(score));
        expect(back.measures.single.tuplets.where((t) => t.hidden).length,
            hidden ? 1 : 0);
      }
    });
  });
}
