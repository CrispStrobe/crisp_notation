import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Phase 2.6: transposing instruments + concert-pitch toggle.

/// A written score tagged for a transposing instrument.
Score written(String notes,
    {KeySignature key = const KeySignature(0),
    required Transposition transposition}) {
  final base = Score.simple(
      keySignature: key, timeSignature: TimeSignature.fourFour, notes: notes);
  return Score(
    clef: base.clef,
    keySignature: base.keySignature,
    timeSignature: base.timeSignature,
    measures: base.measures,
    transposition: transposition,
  );
}

Pitch firstPitch(Score s) =>
    (s.measures.first.elements.first as NoteElement).pitches.single;

void main() {
  group('Transposition', () {
    test('common instruments are sounding-below-written', () {
      expect(Transposition.bFlat.interval, Interval.majorSecond);
      expect(Transposition.bFlat.down, isTrue);
      expect(Transposition.eFlat.interval, Interval.majorSixth);
      expect(Transposition.f.interval, Interval.perfectFifth);
      expect(Transposition.bFlatTenor.octaves, 1);
    });

    test('value equality', () {
      expect(const Transposition(Interval.majorSecond), Transposition.bFlat);
      expect(Transposition.bFlat, isNot(Transposition.a));
    });
  });

  group('atConcertPitch', () {
    test('a B♭ part sounds a major second lower, key and all', () {
      // Written in D major (a B♭ trumpet part); concert is C major.
      final part = written('c5:q d5 e5 f5',
          key: const KeySignature(2), transposition: Transposition.bFlat);
      final concert = part.atConcertPitch();
      expect(concert.transposition, isNull);
      expect(concert.keySignature.fifths, 0); // D major → C major
      final p = firstPitch(concert);
      expect(p.step, Step.b); // C5 → B♭4
      expect(p.alter, -1);
      expect(p.octave, 4);
    });

    test('an E♭ part sounds a major sixth lower', () {
      // Written in A major (an E♭ alto sax part); concert is C major.
      final part = written('a4:q',
          key: const KeySignature(3), transposition: Transposition.eFlat);
      final concert = part.atConcertPitch();
      expect(concert.keySignature.fifths, 0); // A major → C major
      final p = firstPitch(concert);
      expect(p.step, Step.c); // A4 → C4
      expect(p.octave, 4);
    });

    test('octaves compound the interval (tenor sax, down a ninth)', () {
      final part = written('c5:q', transposition: Transposition.bFlatTenor);
      final p = firstPitch(part.atConcertPitch());
      expect(p.step, Step.b); // C5 → B♭3
      expect(p.alter, -1);
      expect(p.octave, 3);
    });

    test('a concert-pitch part is returned unchanged', () {
      final part = Score.simple(notes: 'c5:q d5');
      expect(part.atConcertPitch(), same(part));
    });
  });

  group('transposedBy interaction', () {
    test('keeps the transposition tag by default', () {
      final part = written('c5:q', transposition: Transposition.bFlat);
      expect(part.transposedBy(Interval.majorSecond).transposition,
          Transposition.bFlat);
    });

    test('keepTransposition: false clears it', () {
      final part = written('c5:q', transposition: Transposition.bFlat);
      expect(
          part
              .transposedBy(Interval.majorSecond, keepTransposition: false)
              .transposition,
          isNull);
    });
  });

  group('MusicXML interchange', () {
    test('writes <transpose> with signed diatonic/chromatic', () {
      final xml = scoreToMusicXml(
          written('c5:q d5 e5 f5', transposition: Transposition.bFlat));
      expect(
          xml,
          contains('<transpose><diatonic>-1</diatonic>'
              '<chromatic>-2</chromatic></transpose>'));
    });

    test('writes an octave-change for compound transpositions', () {
      final xml = scoreToMusicXml(
          written('c5:q', transposition: Transposition.bFlatTenor));
      expect(xml, contains('<octave-change>-1</octave-change>'));
    });

    test('round-trips the transposition', () {
      final part = written('c5:q d5 e5 f5',
          key: const KeySignature(2), transposition: Transposition.bFlat);
      final back = scoreFromMusicXml(scoreToMusicXml(part));
      expect(back, part);
      expect(back.transposition, Transposition.bFlat);
    });

    test('round-trips an E♭ (major sixth) transposition', () {
      final part = written('c5:q', transposition: Transposition.eFlat);
      final back = scoreFromMusicXml(scoreToMusicXml(part));
      expect(back.transposition, Transposition.eFlat);
    });
  });

  group('StaffSystem concert-pitch toggle', () {
    test('maps every transposing staff to concert pitch', () {
      final system = StaffSystem([
        written('c5:q', transposition: Transposition.bFlat),
        Score.simple(clef: Clef.bass, notes: 'c3:q'), // non-transposing
      ]);
      final concert = system.atConcertPitch();
      expect(concert.staves[0].transposition, isNull);
      expect(firstPitch(concert.staves[0]).step, Step.b); // C5 → B♭4
      expect(concert.staves[1], same(system.staves[1])); // unchanged
    });
  });
}
