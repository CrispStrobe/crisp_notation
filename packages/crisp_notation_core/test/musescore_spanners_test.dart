import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// MuseScore voice-level spanners: HairPin, Pedal, Ottava.
///
/// All three were absent from both sides while the model and MusicXML already
/// carried them — measured over 4,000 corpus `.mscx`: HairPin in 2,723 files,
/// Pedal in 1,284, Ottava in 586.
///
/// ⚠️ Two traps, and BOTH only showed up against real files or a real round
/// trip, never against a synthetic case built the way our own writer emits:
///  1. A `Slur` spanner is a CHILD of `<Chord>`; HairPin/Pedal/Ottava are
///     SIBLINGS of it. Reading from inside the chord found every spanner we
///     wrote and none of the corpus's; writing inside the chord produced files
///     our own reader could not read back.
///  2. A pedal or ottava commonly anchors on a REST — a pedal is held through
///     rests by definition — so attaching only on `<Chord>` misses them.
void main() {
  NoteElement n(int midi, String id) => NoteElement(
        pitches: [Pitch.fromMidi(midi)],
        duration: const NoteDuration(DurationBase.quarter),
        id: id,
      );

  Score withSpans({
    List<Pedal> pedals = const [],
    List<Ottava> ottavas = const [],
    List<Hairpin> hairpins = const [],
  }) =>
      Score(
        clef: Clef.treble,
        measures: [
          Measure([
            n(60, 'a'),
            const RestElement(NoteDuration(DurationBase.quarter), id: 'r'),
            n(64, 'b'),
            n(65, 'c'),
          ]),
        ],
        pedals: pedals,
        ottavas: ottavas,
        hairpins: hairpins,
      );

  test('a pedal round-trips', () {
    final back = scoreFromMscx(
      scoreToMscx(withSpans(pedals: const [Pedal('a', 'b')])),
    );
    expect(back.pedals, hasLength(1));
  });

  test('an ottava round-trips, keeping its direction', () {
    for (final down in [true, false]) {
      final back = scoreFromMscx(
        scoreToMscx(withSpans(ottavas: [Ottava('a', 'b', down: down)])),
      );
      expect(back.ottavas, hasLength(1), reason: 'down=$down');
      expect(back.ottavas.single.down, down, reason: 'down=$down');
    }
  });

  test('a spanner anchored on a REST survives', () {
    // Trap 2. `r` is a rest, and it is where the corpus file that surfaced this
    // opens its pedal.
    final back = scoreFromMscx(
      scoreToMscx(withSpans(ottavas: const [Ottava('r', 'c', down: true)])),
    );
    expect(back.ottavas, hasLength(1));
  });

  test('spanners are written as SIBLINGS of the element, not children', () {
    // Trap 1, pinned on the markup itself so a regression is unambiguous.
    final mscx = scoreToMscx(withSpans(pedals: const [Pedal('a', 'b')]));
    expect(mscx, contains('<Spanner type="Pedal">'));
    expect(
        mscx,
        isNot(contains('<Chord><durationType>quarter</durationType>'
            '<Spanner type="Pedal"')));
  });

  test('all three coexist in one score', () {
    final back = scoreFromMscx(scoreToMscx(withSpans(
      pedals: const [Pedal('a', 'b')],
      ottavas: const [Ottava('r', 'c', down: true)],
      hairpins: const [Hairpin('a', 'c', HairpinType.diminuendo)],
    )));
    expect(back.pedals, hasLength(1));
    expect(back.ottavas, hasLength(1));
    expect(back.hairpins, hasLength(1));
    expect(back.hairpins.single.type, HairpinType.diminuendo);
  });

  test('they reach MusicXML too — neutral, not MuseScore-only', () {
    final back = scoreFromMusicXml(scoreToMusicXml(withSpans(
      pedals: const [Pedal('a', 'b')],
      ottavas: const [Ottava('r', 'c', down: true)],
    )));
    expect(back.pedals, hasLength(1));
    expect(back.ottavas, hasLength(1));
  });
}
