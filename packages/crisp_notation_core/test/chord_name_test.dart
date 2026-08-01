import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseChordName accepts', () {
    void ok(String text, Step step, int alter, ChordSymbolKind kind,
        {Step? bass}) {
      test(text, () {
        final p = parseChordName(text);
        expect(p, isNotNull, reason: '$text should read as a chord');
        expect(p!.root.step, step);
        expect(p.root.alter, alter);
        expect(p.kind, kind);
        if (bass == null) {
          expect(p.bass, isNull);
        } else {
          expect(p.bass!.step, bass);
        }
      });
    }

    ok('C', Step.c, 0, ChordSymbolKind.major);
    ok('Eb', Step.e, -1, ChordSymbolKind.major);
    ok('F#', Step.f, 1, ChordSymbolKind.major);
    ok('Am', Step.a, 0, ChordSymbolKind.minor);
    ok('Bbm', Step.b, -1, ChordSymbolKind.minor);
    ok('G7', Step.g, 0, ChordSymbolKind.dominantSeventh);
    ok('Ebmaj7', Step.e, -1, ChordSymbolKind.majorSeventh);
    ok('Dm7', Step.d, 0, ChordSymbolKind.minorSeventh);
    ok('C#m7b5', Step.c, 1, ChordSymbolKind.halfDiminishedSeventh);
    ok('Bdim7', Step.b, 0, ChordSymbolKind.diminishedSeventh);
    ok('Caug', Step.c, 0, ChordSymbolKind.augmented);
    ok('Fdim', Step.f, 0, ChordSymbolKind.diminished);
    ok('C6', Step.c, 0, ChordSymbolKind.sixth);
    ok('Am6', Step.a, 0, ChordSymbolKind.minorSixth);
    ok('G9', Step.g, 0, ChordSymbolKind.dominantNinth);
    ok('Dsus4', Step.d, 0, ChordSymbolKind.suspendedFourth);
    ok('Asus2', Step.a, 0, ChordSymbolKind.suspendedSecond);
    ok('CmMaj7', Step.c, 0, ChordSymbolKind.minorMajorSeventh);
    ok('G/B', Step.g, 0, ChordSymbolKind.major, bass: Step.b);
    ok('Am7/G', Step.a, 0, ChordSymbolKind.minorSeventh, bass: Step.g);
    ok('Eb/Bb', Step.e, -1, ChordSymbolKind.major, bass: Step.b);

    test('case is not significant in the suffix', () {
      expect(parseChordName('EbMaj7')!.kind, ChordSymbolKind.majorSeventh);
      expect(parseChordName('cmaj7')!.kind, ChordSymbolKind.majorSeventh);
    });
    test('the bass keeps its own accidental', () {
      expect(parseChordName('Eb/Bb')!.bass!.alter, -1);
    });
  });

  // Rejecting matters more than accepting: this runs over free text, where a
  // chord symbol and a performance direction arrive through the same channel.
  group('parseChordName rejects prose', () {
    for (final text in [
      'Fine',
      'D.C.',
      'D.C. al Coda',
      'Dal Segno',
      'Allegro',
      'Coda',
      'Bridge',
      'Adagio',
      'Andante',
      'Bass',
      'Chorus',
      'Am I right',
      'and/or',
      'Guitar',
      'Fingerstyle',
      'Cello',
      'Gently',
      'Bb major throughout',
      '',
      '   ',
      'x',
      '7',
      'N.C.',
      'A/B/C',
      'Ebbb',
      'bB',
      // The `o` and `-` aliases must not eat ordinary words.
      'Go',
      // Bare `o` for diminished is deliberately unsupported (see the map).
      'Eo',
      'Gone',
      'Din',
      'Ago',
      'Bass-heavy',
      'Fast',
      'Grave',
      'Am7b5x',
    ]) {
      test('"$text"', () => expect(parseChordName(text), isNull));
    }
  });

  // Case is not decoration here: CM7 and Cm7 are different chords, and a
  // blind toLowerCase() turns every major seventh minor.
  group('case distinguishes major from minor', () {
    test('CM7 is a major seventh, Cm7 a minor one', () {
      expect(parseChordName('CM7')!.kind, ChordSymbolKind.majorSeventh);
      expect(parseChordName('Cm7')!.kind, ChordSymbolKind.minorSeventh);
    });
    test('CM is major, Cm is minor', () {
      expect(parseChordName('CM')!.kind, ChordSymbolKind.major);
      expect(parseChordName('Cm')!.kind, ChordSymbolKind.minor);
    });
    test('CM6 is a sixth, Cm6 a minor sixth', () {
      expect(parseChordName('CM6')!.kind, ChordSymbolKind.sixth);
      expect(parseChordName('Cm6')!.kind, ChordSymbolKind.minorSixth);
    });
    test('an unambiguous spelling still folds case', () {
      expect(parseChordName('CDIM')!.kind, ChordSymbolKind.diminished);
      expect(parseChordName('CSus4')!.kind, ChordSymbolKind.suspendedFourth);
      expect(parseChordName('cAuG')!.kind, ChordSymbolKind.augmented);
    });
  });

  group('alternate spellings real charts use', () {
    void ok(String text, ChordSymbolKind kind) => test(
        text, () => expect(parseChordName(text)?.kind, kind, reason: text));
    ok('Ami', ChordSymbolKind.minor);
    ok('Amin', ChordSymbolKind.minor);
    ok('A-', ChordSymbolKind.minor);
    ok('E\u00b0', ChordSymbolKind.diminished);
    ok('C+', ChordSymbolKind.augmented);
    ok('Bb5+', ChordSymbolKind.augmented);
    ok('Cmaj', ChordSymbolKind.major);
    ok('C\u0394', ChordSymbolKind.major);
    ok('Bmin7', ChordSymbolKind.minorSeventh);
    ok('B\u00f8', ChordSymbolKind.halfDiminishedSeventh);
    ok('Bo7', ChordSymbolKind.diminishedSeventh);
    ok('Dsus', ChordSymbolKind.suspendedFourth);
    ok('CmM7', ChordSymbolKind.minorMajorSeventh);
  });

  _formatterTests();

  test('every kind the model has round-trips through its own suffix', () {
    for (final kind in ChordSymbolKind.values) {
      final p = parseChordName('C${kind.suffix}');
      expect(p, isNotNull, reason: 'C${kind.suffix} (${kind.name})');
      expect(p!.kind, kind, reason: 'C${kind.suffix}');
      expect(p.root.step, Step.c);
    }
  });
}

void _formatterTests() {
  group('chordName writes a name back', () {
    void ok(String text) => test(text, () {
          final p = parseChordName(text)!;
          final c = ChordSymbol('e0', p.root, p.kind, bass: p.bass);
          expect(chordName(c), text);
        });
    for (final t in [
      'C',
      'Eb',
      'F#',
      'Am',
      'Bbm',
      'G7',
      'Ebmaj7',
      'Dm7',
      'C#m7b5',
      'Bdim7',
      'Caug',
      'Fdim',
      'C6',
      'Am6',
      'G9',
      'Dsus4',
      'Asus2',
      'CmMaj7',
      'G/B',
      'Am7/G',
      'Eb/Bb',
    ]) {
      ok(t);
    }
    test('an alternate spelling comes back canonical', () {
      for (final (input, canonical) in [
        ('Ami', 'Am'),
        ('Amin', 'Am'),
        ('A-', 'Am'),
        ('Cmaj', 'C'),
        ('CM7', 'Cmaj7'),
        ('Dsus', 'Dsus4'),
        ('Bo7', 'Bdim7'),
      ]) {
        final p = parseChordName(input)!;
        expect(chordName(ChordSymbol('e0', p.root, p.kind, bass: p.bass)),
            canonical,
            reason: input);
      }
    });
    test('every kind survives name -> parse -> name', () {
      for (final kind in ChordSymbolKind.values) {
        final c = ChordSymbol('e0', Pitch(Step.e, octave: 4, alter: -1), kind);
        final name = chordName(c);
        final back = parseChordName(name);
        expect(back, isNotNull, reason: name);
        expect(back!.kind, kind, reason: name);
        expect(back.root.step, Step.e, reason: name);
        expect(back.root.alter, -1, reason: name);
      }
    });
  });
}
