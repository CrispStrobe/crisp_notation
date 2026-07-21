import 'package:crisp_notation_core/crisp_notation_core.dart';
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

  test('infers Drop-D tuning from the string labels', () {
    // The low string is labelled D, so the low note is D2 (fret 0), not E2 —
    // reading it as standard would be two semitones sharp.
    final score = asciiTabToScore('''
e|-------|
B|-------|
G|-------|
D|-------|
A|-------|
D|-0-----|
''');
    expect(pitches(score).single.toString(), 'D2');
  });

  test('a held-note = and repeat * no longer disqualify a tab line', () {
    // A single = used to reject the whole line, dropping the block to nothing.
    final score = asciiTabToScore('''
e|--------------|
B|--------------|
G|*---0=======0-|
D|--------------|
A|--------------|
E|--3=======----|
''');
    // The fretted attacks survive (E-string fret 3, G-string fret 0 twice).
    expect(pitches(score).length, 3);
  });

  test('a 4-line bass tab is detected, not forced to 6 strings', () {
    final score = asciiTabToScore('''
G|-------|
D|-------|
A|-------|
E|-0-----|
''');
    expect(pitches(score).single.toString(), 'E1'); // low E of a bass
  });

  test('a runaway digit run does not overflow (fret capped at two digits)', () {
    // Regression: two real ClassTab files crashed int.parse on a long digit run.
    final score = asciiTabToScore('e|-0000000000000000000-|');
    expect(score.measures, isNotEmpty); // parsed, did not throw
  });

  test('an explicit tuning argument still overrides label inference', () {
    final score = asciiTabToScore('''
D|-0-----|
A|-------|
D|-------|
G|-------|
B|-------|
E|-------|
''', tuning: Tuning.standardGuitar);
    expect(pitches(score).single.toString(), 'E4'); // forced standard: top = E4
  });

  test('a bar-number / rhythm-reference row is not read as a string', () {
    // Regression from ClassTab: a counting row like "25 |-3-| |-3-|" is
    // dash-dominated, so it used to pass as a tab line, get grouped with the
    // six strings, and read the bar number 55 as fret 55 (MIDI 119, impossible
    // on a guitar). It must be rejected — a string line never starts with a
    // number followed by whitespace.
    final score = asciiTabToScore('''
25 |-3-| |-3-| |-3-|
e|-0-2-3--------------|
B|--------------------|
G|--------------------|
D|--------------------|
A|--------------------|
E|--------------------|
''');
    final midis = score.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((e) => e.pitches)
        .map((p) => p.midiNumber)
        .toList();
    // Only the three real high-E notes; no fret-55 garbage.
    expect(midis, everyElement(lessThanOrEqualTo(88)));
    expect(pitches(score).map((p) => p.toString()), ['E4', 'F#4', 'G4']);
  });

  test('a mostly-sustained string line keeps the block (guitar, not bass)', () {
    // Regression from ClassTab: the A line is one open note held with `=`, so it
    // has a single dash. The old >=2-dash rule rejected it, splitting the six
    // strings into four and mis-inferring BASS tuning -> every pitch an octave
    // low (low E read as E1=28, not E2=40). `=` is sustain fill like `-`.
    final score = asciiTabToScore('''
e|-0------------------|
B|--------------------|
G|--------------------|
D|--------------------|
A|-0==================|
E|--------------------|
''');
    final midis = score.measures
        .expand((m) => m.elements)
        .whereType<NoteElement>()
        .expand((e) => e.pitches)
        .map((p) => p.midiNumber);
    // Open A on a guitar is A2 = 45, not A1 = 33 (which a bass mis-read gives).
    expect(midis, everyElement(greaterThanOrEqualTo(40)));
    expect(midis, contains(45)); // A2 present
  });

  test('adjacent single-digit frets forming >24 are split, not one fret', () {
    // Regression from ClassTab: fast figures are written with no separator —
    // "797" is frets 7,9,7, not fret 79 (MIDI 143, impossible). A two-digit run
    // is one fret only when <= 24.
    final score = asciiTabToScore('''
e|-797-|
B|-----|
G|-----|
D|-----|
A|-----|
E|-----|
''');
    expect(
      pitches(score).map((p) => p.toString()).toList(),
      ['B4', 'C#5', 'B4'], // 7, 9, 7 on the high E
    );
    // A real two-digit fret (<= 24) is still read whole.
    final twelve = asciiTabToScore('''
e|-12-|
B|----|
G|----|
D|----|
A|----|
E|----|
''');
    expect(pitches(twelve).single.toString(), 'E5'); // 12th fret = octave
  });

  test('an explicit tuning: line overrides the nominal string labels', () {
    // A Drop-D tab labels its low string by its nominal name E, but the tuning
    // line says D — and that line is authoritative. The label alone put the low
    // note two semitones sharp (E2 not D2).
    final score = asciiTabToScore('''
tuning: D A D G B E

e|-------|
B|-------|
G|-------|
D|-------|
A|-------|
E|-0-----|
''');
    expect(pitches(score).single.toString(), 'D2'); // Drop-D low string
  });
}
