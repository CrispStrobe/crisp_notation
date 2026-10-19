import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Grace notes tied into their principal (`NoteElement.graceTiesToMain`): the
/// principal does not strike the tied pitch again.

late final LayoutSettings settings;

const _d5 = Pitch(Step.d, octave: 5);
const _g4 = Pitch(Step.g, octave: 4);
const _g5 = Pitch(Step.g, octave: 5);

/// `\grace { d''16 g'' ~ d'' ~ } <g' d'' g''>4.` as a model.
NoteElement _tiedChord() => const NoteElement(
      pitches: [_g4, _d5, _g5],
      duration: NoteDuration(DurationBase.quarter, dots: 1),
      graceNotes: [_d5, _g5, _d5],
      graceTiesToMain: {1, 2},
      id: 'm',
    );

Score _score(NoteElement e) => Score(
      clef: Clef.treble,
      timeSignature: const TimeSignature(6, 8),
      measures: [
        Measure([
          e,
          NoteElement.note(
              _g4, const NoteDuration(DurationBase.quarter, dots: 1),
              id: 'n'),
        ]),
      ],
    );

NoteElement _first(Score s) => s.measures.first.elements.first as NoteElement;

String _musicXml({required bool tieFirst, required bool tieLast}) => '''
<score-partwise version="4.0"><part-list><score-part id="P1"><part-name>x</part-name></score-part></part-list>
<part id="P1"><measure number="1">
<attributes><divisions>2</divisions><time><beats>6</beats><beat-type>8</beat-type></time><clef><sign>G</sign><line>2</line></clef></attributes>
<note><grace/><pitch><step>D</step><octave>5</octave></pitch>${tieFirst ? '<tie type="start"/>' : ''}<voice>1</voice><type>16th</type></note>
<note><grace/><pitch><step>G</step><octave>5</octave></pitch>${tieLast ? '<tie type="start"/>' : ''}<voice>1</voice><type>16th</type></note>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
<note><chord/><pitch><step>G</step><octave>5</octave></pitch><duration>3</duration>${tieLast ? '<tie type="stop"/>' : ''}<voice>1</voice><type>quarter</type><dot/></note>
<note><pitch><step>G</step><octave>4</octave></pitch><duration>3</duration><voice>1</voice><type>quarter</type><dot/></note>
</measure></part></score-partwise>
''';

void main() {
  setUpAll(() {
    final source = File('../crisp_notation/assets/smufl/bravura_metadata.json')
        .readAsStringSync();
    settings = LayoutSettings(
        metadata:
            SmuflMetadata.fromJson(jsonDecode(source) as Map<String, Object?>));
  });

  group('the model', () {
    test('the tied pitches are the ones the principal does not strike', () {
      final e = _tiedChord();
      expect(e.pitchesTiedFromGrace, [_d5, _g5]);
      expect([for (var g = 0; g < 3; g++) e.graceTiesInto(g)],
          [false, true, true]);
      // A tie into a pitch the note lacks, or past the graces, ties nothing.
      final none = e.copyWith(pitches: [_g4], graceTiesToMain: {1, 7});
      expect(none.pitchesTiedFromGrace, isEmpty);
      expect(none.graceTiesInto(1), isFalse);
    });

    test('equality, copyWith and transposition carry the field', () {
      final e = _tiedChord();
      expect(e, isNot(e.copyWith(graceTiesToMain: {2})));
      expect(e.copyWith(), e);
      expect(e.toString(), contains('grace ties: 1,2'));
      final up = _first(_score(e).transposedBy(Interval.majorSecond));
      expect(up.graceTiesToMain, {1, 2});
    });
  });

  group('MusicXML', () {
    test('a grace <tie type="start"/> into the principal is read', () {
      final e =
          _first(scoreFromMusicXml(_musicXml(tieFirst: false, tieLast: true)));
      expect(e.graceNotes, [_d5, _g5]);
      expect(e.graceTiesToMain, {1});
      expect(e.pitchesTiedFromGrace, [_g5]);
      expect(
          _first(scoreFromMusicXml(_musicXml(tieFirst: false, tieLast: false)))
              .graceTiesToMain,
          isEmpty);
    });

    test('a grace tied into a pitch the principal lacks holds nothing', () {
      // d'' tied, then g'', then the principal: the d'' tie has no d'' to
      // land on in the principal (it holds g' and g''), so nothing is held.
      final e =
          _first(scoreFromMusicXml(_musicXml(tieFirst: true, tieLast: false)));
      expect(e.graceTiesToMain, {0});
      expect(e.pitchesTiedFromGrace, isEmpty);
    });

    test('written as a tie start on the grace and a stop on the principal', () {
      final xml = scoreToMusicXml(_score(_tiedChord()));
      final graces =
          RegExp('<note><grace[^]*?</note>').allMatches(xml).toList();
      expect(graces, hasLength(3));
      expect(graces[0][0], isNot(contains('<tie ')));
      expect(graces[1][0], contains('<tie type="start"/>'));
      expect(graces[1][0], contains('<tied type="start"/>'));
      expect(graces[2][0], contains('<tie type="start"/>'));
      expect(RegExp('<tie type="stop"/>').allMatches(xml), hasLength(2));
      final back = _first(scoreFromMusicXml(xml));
      expect(back.graceTiesToMain, {1, 2});
      expect(back.pitchesTiedFromGrace, unorderedEquals([_d5, _g5]));
    });
  });

  group('LilyPond', () {
    test('under tieWaitForNote every tied grace reaches the principal', () {
      final e = _first(scoreFromLilyPond(r"""
{ \time 6/8 \set tieWaitForNote = ##t
  \grace { d''16[ g'' ~ d''] ~ } <g' d'' g''>4. g'4. }"""));
      expect(e.graceTiesToMain, {1, 2});
      expect(e.pitchesTiedFromGrace, unorderedEquals([_d5, _g5]));
    });

    test('without it only the last grace\'s tie does', () {
      final e = _first(scoreFromLilyPond(r"""
{ \time 6/8 \grace { d''16[ g'' ~ d''] ~ } <g' d'' g''>4. g'4. }"""));
      expect(e.graceTiesToMain, {2});
      expect(
          _first(scoreFromLilyPond(r"{ \acciaccatura e''8 ~ e''4 }"))
              .graceTiesToMain,
          {0});
      // A tie into a principal without the pitch ties nothing.
      expect(
          _first(scoreFromLilyPond(r"{ \grace { e''16 ~ } d''4 }"))
              .graceTiesToMain,
          isEmpty);
    });

    test('the writer keeps the ties, waiting where it must', () {
      final ly = scoreToLilyPond(_score(_tiedChord()));
      expect(ly, contains(r'\set tieWaitForNote = ##t'));
      expect(ly, contains("g''8~ d''8~"));
      final back = _first(scoreFromLilyPond(ly));
      expect(back.graceTiesToMain, {1, 2});
      // ... and the waiting stops after the note.
      expect(ly, contains(r'\set tieWaitForNote = ##f'));
    });
  });

  test('layout draws a short tie from each tied grace head', () {
    int curves(NoteElement e) => const LayoutEngine()
        .layout(_score(e), settings)
        .primitives
        .whereType<CurvePrimitive>()
        .length;
    final tied = _tiedChord();
    expect(curves(tied) - curves(tied.copyWith(graceTiesToMain: {})), 2);
  });
}
