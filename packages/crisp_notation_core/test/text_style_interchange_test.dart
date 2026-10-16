import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Italic and bold text marks survive MEI and MuseScore, and styled text in
/// either format is read at all (its words sit inside `<rend>` / `<i>`, which
/// the readers once skipped, dropping the mark).
void main() {
  Score marked() {
    final score = Score.simple(notes: 'c4:q d4 e4 f4');
    final ids = [
      for (final e in score.measures.first.elements)
        if (e is NoteElement) e.id!,
    ];
    return score.copyWith(annotations: [
      Annotation(ids[0], 'dolce', italic: true),
      Annotation(ids[1], 'Tempo I', bold: true),
      Annotation(ids[2], 'molto',
          italic: true, bold: true, placement: AnnotationPlacement.below),
      Annotation(ids[3], 'plain'),
    ]);
  }

  List<(String, bool, bool, AnnotationPlacement)> styles(Score s) => [
        for (final a in s.annotations) (a.text, a.italic, a.bold, a.placement),
      ];

  test('MEI round-trips text style', () {
    final score = marked();
    expect(styles(scoreFromMei(scoreToMei(score))), styles(score));
  });

  test('MuseScore round-trips text style and placement', () {
    final score = marked();
    expect(styles(scoreFromMscx(scoreToMscx(score))), styles(score));
  });

  test('MEI reads a <dir> whose words are in <rend>', () {
    final mei = scoreToMei(Score.simple(notes: 'c4:w')).replaceFirst(
        '</measure>',
        '<dir startid="#e0"><rend fontstyle="italic">dolce</rend></dir>'
            '</measure>');
    final score = scoreFromMei(mei);
    final id = (score.measures.first.elements.first as NoteElement).id;
    expect(id, 'e0', reason: 'the anchor this test writes');
    expect(styles(score), [('dolce', true, false, AnnotationPlacement.above)]);
  });

  test('MuseScore reads <i> markup and the italic Expression style', () {
    final mscx = scoreToMscx(Score.simple(notes: 'c4:h d4'));
    final styled = mscx.replaceFirst(
        '<Chord>',
        '<StaffText><text><i>rit.</i></text></StaffText>'
            '<StaffText><style>Expression</style><text>dolce</text>'
            '<placement>below</placement></StaffText><Chord>');
    expect(styles(scoreFromMscx(styled)), [
      ('rit.', true, false, AnnotationPlacement.above),
      ('dolce', true, false, AnnotationPlacement.below),
    ]);
  });

  test('MusicXML keeps text style in a score with a multi-bar rest', () {
    // Folding a multi-rest re-anchors every annotation, which once rebuilt
    // them without their style.
    final notes = Score.simple(notes: 'c4:w');
    final id = (notes.measures.first.elements.first as NoteElement).id!;
    final score = Score(
      clef: Clef.treble,
      timeSignature: TimeSignature.fourFour,
      measures: [
        notes.measures.first,
        Measure([RestElement(NoteDuration.whole, id: 'r')], multiRest: 3),
      ],
      annotations: [Annotation(id, 'dolce', italic: true)],
    );
    final read = scoreFromMusicXml(scoreToMusicXml(score));
    expect(read.measures.last.multiRest, 3);
    expect(styles(read), [('dolce', true, false, AnnotationPlacement.above)]);
  });
}
