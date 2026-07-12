import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

List<Pitch> pitches(Score s) => s.measures
    .expand((m) => m.elements)
    .whereType<NoteElement>()
    .expand((n) => n.pitches)
    .toList();

void main() {
  test('parses a single-string melody into pitches', () {
    final score = asciiTabToScore('''
e|-0-2-3-|
B|-------|
G|-------|
D|-------|
A|-------|
E|-------|
''');
    expect(pitches(score).map((p) => p.toString()), ['E4', 'F#4', 'G4']);
  });

  test('aligned columns across strings form a chord', () {
    final score = asciiTabToScore('''
e|-0-|
B|-1-|
G|-0-|
D|-2-|
A|-3-|
E|-0-|
''');
    final notes =
        score.measures.expand((m) => m.elements).whereType<NoteElement>();
    expect(notes, hasLength(1));
    // An open E-minor-ish shape: 6 tones, lowest E2, highest E4.
    expect(notes.single.pitches, hasLength(6));
    expect(notes.single.pitches.first.toString(), 'E2');
    expect(notes.single.pitches.last.toString(), 'E4');
  });

  test('two-digit frets are read whole', () {
    final score = asciiTabToScore('''
e|-12-|
B|----|
G|----|
D|----|
A|----|
E|----|
''');
    // 12th-fret high E = one octave up = E5.
    expect(pitches(score).single.toString(), 'E5');
  });

  test('a dead note x becomes a TabNoteMark.dead', () {
    final score = asciiTabToScore('''
e|-x-|
B|---|
G|---|
D|---|
A|---|
E|---|
''');
    expect(score.tabNoteMarks, hasLength(1));
    expect(score.tabNoteMarks.single.style, TabNoteStyle.dead);
  });

  test('h / p map to slurs', () {
    final score = asciiTabToScore('''
e|-5h7p5-|
B|-------|
G|-------|
D|-------|
A|-------|
E|-------|
''');
    expect(score.slurs, hasLength(2)); // 5->7 and 7->5
    expect(score.slurs.first.startId, 'e0');
    expect(score.slurs.first.endId, 'e1');
  });

  test('slides map to glissandos', () {
    final score = asciiTabToScore(r'''
e|-5/7-|
B|-----|
G|-----|
D|-----|
A|-----|
E|-----|
''');
    expect(score.glissandos, hasLength(1));
  });

  test('b maps to a bend, ~ to a vibrato', () {
    final score = asciiTabToScore('''
e|-5b-7~-|
B|-------|
G|-------|
D|-------|
A|-------|
E|-------|
''');
    expect(score.bends, hasLength(1));
    expect(score.bends.single.noteId, 'e0');
    expect(score.vibratos, hasLength(1));
    expect(score.vibratos.single.noteId, 'e1');
  });

  test('barline | splits measures', () {
    final score = asciiTabToScore('''
e|-0-|-2-|
B|---|---|
G|---|---|
D|---|---|
A|---|---|
E|---|---|
''');
    expect(score.measures, hasLength(2));
    expect(pitches(score).map((p) => p.toString()), ['E4', 'F#4']);
  });

  test('multiple blocks continue the sequence', () {
    final score = asciiTabToScore('''
e|-0-|
B|---|
G|---|
D|---|
A|---|
E|---|

e|-3-|
B|---|
G|---|
D|---|
A|---|
E|---|
''');
    expect(pitches(score).map((p) => p.toString()), ['E4', 'G4']);
  });

  test('a custom tuning changes the pitches', () {
    final score = asciiTabToScore('''
G|-0-|
D|---|
A|---|
E|---|
''', tuning: Tuning.standardBass);
    // Top bass string open = G2.
    expect(pitches(score).single.toString(), 'G2');
  });

  test('non-tab text yields one empty measure', () {
    final score = asciiTabToScore('just some prose\nnot a tab at all');
    expect(score.measures, hasLength(1));
    expect(score.measures.single.elements.single, isA<RestElement>());
  });

  List<NoteDuration> durations(Score s) => s.measures
      .expand((m) => m.elements)
      .whereType<NoteElement>()
      .map((n) => n.duration)
      .toList();

  test('inferRhythm reads durations from horizontal spacing', () {
    // Gaps of 2, 4, 2 columns → the smallest (2) is an eighth, so the second
    // note (gap 4 = 2×) is a quarter.
    final score = asciiTabToScore('''
e|-0--2----3--5-|
B|--------------|
G|--------------|
D|--------------|
A|--------------|
E|--------------|
''', inferRhythm: true);
    final d = durations(score);
    expect(d[0], NoteDuration.eighth); // gap 2 = base
    expect(d[1], NoteDuration.quarter); // gap 4 = 2×
    expect(d[2], NoteDuration.eighth); // gap 2
  });

  test('without inferRhythm every event is the fixed duration', () {
    final score = asciiTabToScore('''
e|-0--2----3-|
B|-----------|
G|-----------|
D|-----------|
A|-----------|
E|-----------|
''', duration: NoteDuration.quarter);
    expect(durations(score), everyElement(NoteDuration.quarter));
  });

  test('a wide gap infers a longer (dotted/whole) value', () {
    // First gap is the unit (2); the big gap (8 = 4×) → a half note.
    final score = asciiTabToScore('''
e|-0--2--------------3-|
B|--------------------|
G|--------------------|
D|--------------------|
A|--------------------|
E|--------------------|
''', inferRhythm: true);
    expect(durations(score)[1], NoteDuration.half);
  });

  test('the result renders as tab (pitches recover frets)', () {
    // Round-trip the pitches through the tab engine: fret 3 on the high E.
    final score = asciiTabToScore('''
e|-3-|
B|---|
G|---|
D|---|
A|---|
E|---|
''');
    final place = Tuning.standardGuitar.fretFor(pitches(score).single);
    expect(place, isNotNull);
    expect(place!.$2, 3); // recovered fret 3 on the top string
  });
}
