import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Voices 2-4 kept their notes but lost their identity and their rhythm.
///
/// The cross-format sweep only compares voice 1 by default, and these still
/// surfaced there — an inner voice's tuplet was being stamped onto VOICE 1,
/// where its endIndex is usually out of range, so the group never closed and
/// swallowed the rest of the layer.

String shape(Score s, int voice) {
  final out = <String>[];
  for (final m in s.measures) {
    final scale = <int, Fraction>{};
    for (final t in m.tuplets) {
      if (t.voice != voice) continue;
      for (var i = t.startIndex; i <= t.endIndex; i++) {
        scale[i] = Fraction(t.normal, t.actual);
      }
    }
    final elements = m.voices[voice];
    for (var i = 0; i < elements.length; i++) {
      final e = elements[i];
      final d = e.duration.toFraction() * (scale[i] ?? Fraction(1, 1));
      out.add(e is NoteElement ? '${e.pitches.first.midiNumber}@$d' : 'r@$d');
    }
  }
  return out.join(' ');
}

NoteElement n(int midi, String id) => NoteElement(
      pitches: [Pitch.fromMidi(midi)],
      duration: const NoteDuration(DurationBase.eighth),
      id: id,
    );

Score through(String format, Score s) => switch (format) {
      'mei' => scoreFromMei(scoreToMei(s)),
      'musescore' => scoreFromMscx(scoreToMscx(s)),
      _ => scoreFromMusicXml(scoreToMusicXml(s)),
    };

void main() {
  const formats = ['mei', 'musescore', 'musicxml'];

  group('a tuplet in an inner voice', () {
    // Voice 1 used to be handed the WHOLE tuplet list, including voice 2's,
    // and the inner voices were handed none at all.
    Score both() => Score(
          clef: Clef.treble,
          timeSignature: const TimeSignature(4, 4),
          measures: [
            Measure([
              n(69, 'a'),
              const RestElement(NoteDuration(DurationBase.eighth), id: 'r1'),
              n(71, 'b'),
              n(72, 'c'),
            ], voice2: [
              n(60, 'g'),
              n(62, 'h'),
              n(64, 'i'),
              n(65, 'j'),
              n(67, 'k'),
            ], tuplets: [
              const TupletSpan(1, 3, actual: 3, normal: 2),
              const TupletSpan(2, 4, actual: 3, normal: 2, voice: 1),
            ]),
          ],
        );

    for (final f in formats) {
      test('$f keeps both voices intact', () {
        final back = through(f, both());
        expect(shape(back, 0), shape(both(), 0), reason: '$f voice 1');
        expect(shape(back, 1), shape(both(), 1), reason: '$f voice 2');
      });
    }
  });

  group('an EMPTY voice does not collapse the ones after it', () {
    // MEI names its layers (`<layer n="4">`) but the reader went by position;
    // a MuseScore `<voice>` carries no number at all, so position IS its
    // identity and skipping an empty one moves every later voice up a slot.
    Score gap() => Score(clef: Clef.treble, measures: [
          Measure(
            [n(69, 'a')],
            voice2: [n(61, 'b')],
            voice4: [n(66, 'd')],
          ),
        ]);

    for (final f in formats) {
      test('$f keeps voice 4 in voice 4', () {
        final back = through(f, gap());
        expect(back.measures[0].voice3, isEmpty, reason: '$f voice 3');
        expect(
          back.measures[0].voice4
              .whereType<NoteElement>()
              .map((e) => e.pitches.first.midiNumber),
          [66],
          reason: '$f voice 4',
        );
      });
    }

    test('trailing empty voices are not invented', () {
      final s = Score(clef: Clef.treble, measures: [
        Measure([n(69, 'a')], voice2: [n(61, 'b')]),
      ]);
      final back = through('musescore', s);
      expect(back.measures[0].voice3, isEmpty);
      expect(back.measures[0].voice4, isEmpty);
    });
  });
}
