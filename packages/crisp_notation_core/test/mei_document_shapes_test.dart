import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Where MEI actually puts `<score>`.
///
/// The reader used to walk one fixed path, `music > body > mdiv > score`. MEI
/// does not guarantee that depth: `<mdiv>` nests for multi-movement works, a
/// document may hold several `<mdiv>` siblings where only a later one carries
/// music, and `<meiCorpus>` wraps whole `<mei>` documents. Running the official
/// MEI sample corpus found 42 files that contain notes and reported no score —
/// some of them with eight `score` elements inside.
String _wrap(String inner) => '<?xml version="1.0" encoding="UTF-8"?>$inner';

const _score = '<score><scoreDef/><section><measure n="1"><staff n="1">'
    '<layer n="1"><note pname="c" oct="4" dur="4"/></layer>'
    '</staff></measure></section></score>';

int _notes(Score s) => [
      for (final m in s.measures)
        for (final v in m.voices) ...v.whereType<NoteElement>(),
    ].length;

void main() {
  test('the plain path still works', () {
    final s = scoreFromMei(
      _wrap('<mei><music><body><mdiv>$_score</mdiv></body></music></mei>'),
    );
    expect(_notes(s), 1);
  });

  test('a nested mdiv (multi-movement) is reached', () {
    final s = scoreFromMei(_wrap(
      '<mei><music><body><mdiv><mdiv>$_score</mdiv></mdiv></body></music></mei>',
    ));
    expect(_notes(s), 1);
  });

  test('a later mdiv sibling is reached when the first has no score', () {
    final s = scoreFromMei(_wrap(
      '<mei><music><body><mdiv><head>Front matter</head></mdiv>'
      '<mdiv>$_score</mdiv></body></music></mei>',
    ));
    expect(_notes(s), 1);
  });

  test('a meiCorpus root is read', () {
    final s = scoreFromMei(_wrap(
      '<meiCorpus><meiHead/><mei><music><body><mdiv>$_score</mdiv></body>'
      '</music></mei></meiCorpus>',
    ));
    expect(_notes(s), 1);
  });

  test('a bare music fragment is read', () {
    final s = scoreFromMei(
      _wrap('<music><body><mdiv>$_score</mdiv></body></music>'),
    );
    expect(_notes(s), 1);
  });

  test('a part-based encoding is read', () {
    // MEI's alternative to score-based encoding: `parts > part` replaces
    // `score` outright and the staffDef sits directly inside the part.
    final s = scoreFromMei(_wrap(
      '<mei><music><body><mdiv><parts><part>'
      '<staffDef n="1" lines="5"/>'
      '<section><measure n="1"><staff n="1"><layer n="1">'
      '<note pname="d" oct="4" dur="4"/></layer></staff></measure></section>'
      '</part></parts></mdiv></body></music></mei>',
    ));
    expect(_notes(s), 1);
  });

  test('the first score WITH MUSIC wins over empty front matter', () {
    // Large documents open with title pages and cast lists as their own mdivs
    // holding empty scores; opera.mei has 18 mdivs and the music in the fifth.
    final s = scoreFromMei(_wrap(
      '<mei><music><body>'
      '<mdiv><score><section/></score></mdiv>'
      '<mdiv><score><section/></score></mdiv>'
      '<mdiv>$_score</mdiv>'
      '</body></music></mei>',
    ));
    expect(_notes(s), 1);
  });

  group('editorial containers', () {
    String doc(String layer) => _wrap(
          '<mei><music><body><mdiv><score><scoreDef/><section>'
          '<measure n="1"><staff n="1"><layer n="1">$layer</layer>'
          '</staff></measure></section></score></mdiv></body></music></mei>',
        );

    test('app/rdg takes exactly one reading, not both', () {
      // Variant readings are ALTERNATIVES; concatenating them would invent
      // music that no source contains.
      final s = scoreFromMei(doc(
        '<app><rdg><note pname="c" oct="4" dur="4"/></rdg>'
        '<rdg><note pname="d" oct="4" dur="4"/></rdg></app>',
      ));
      expect(_notes(s), 1);
    });

    test('app prefers the editor lemma', () {
      final s = scoreFromMei(doc(
        '<app><lem><note pname="e" oct="4" dur="4"/></lem>'
        '<rdg><note pname="f" oct="4" dur="4"/></rdg></app>',
      ));
      expect(_notes(s), 1);
      final p = s.measures.first.elements.whereType<NoteElement>().first;
      expect(p.pitches.first.step, Step.e);
    });

    test('choice prefers the corrected reading', () {
      final s = scoreFromMei(doc(
        '<choice><sic><note pname="g" oct="4" dur="4"/></sic>'
        '<corr><note pname="a" oct="4" dur="4"/></corr></choice>',
      ));
      expect(_notes(s), 1);
      expect(
          s.measures.first.elements
              .whereType<NoteElement>()
              .first
              .pitches
              .first
              .step,
          Step.a);
    });

    test('deleted material does not sound; supplied material does', () {
      expect(
          _notes(scoreFromMei(doc('<del><note pname="c" oct="4" dur="4"/>'
              '</del>'))),
          0);
      expect(
          _notes(scoreFromMei(doc('<supplied>'
              '<note pname="c" oct="4" dur="4"/></supplied>'))),
          1);
    });
  });

  test('a document with no score still fails, and says what the root was', () {
    // Metadata fragments are the bulk of the sample corpus's unreadable files
    // and SHOULD fail — 129 of them contain no note at all.
    expect(
      () => scoreFromMei(_wrap('<perfMedium><instrVoice>Lute</instrVoice>'
          '</perfMedium>')),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('perfMedium'))),
    );
    expect(
      () => scoreFromMei(_wrap('<mei><meiHead><title>Header only</title>'
          '</meiHead></mei>')),
      throwsA(isA<FormatException>()),
    );
  });
}
