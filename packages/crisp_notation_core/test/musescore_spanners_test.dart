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

  // MuseScore 3 writes an ending as a `<Spanner type="Volta">` in the voice of
  // the bar it opens, with `<next><location><measures>N` reaching the bar
  // after its last, where a `<prev>` closes it — the shape of the Lieder
  // corpus (Gabriel, "Only": a two-verse ending "1, 2" over six bars). Only a
  // Measure-level `<Volta>`, which no MuseScore writes, was read.
  group('MuseScore 3 volta spanners', () {
    String rest() => '<Rest><durationType>measure</durationType>'
        '<duration>4/4</duration></Rest>';
    String start(String volta, int bars) => '<Spanner type="Volta"><Volta>'
        '$volta</Volta><next><location><measures>$bars</measures>'
        '</location></next></Spanner>';
    String stop(int bars) => '<Spanner type="Volta"><prev><location>'
        '<measures>-$bars</measures></location></prev></Spanner>';
    String measure(String voice, {String flags = ''}) =>
        '<Measure>$flags<voice>$voice${rest()}</voice></Measure>';
    String doc(List<String> measures, {int staves = 1}) =>
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<museScore version="3.02"><Score>'
        '${[
          for (var s = 1; s <= staves; s++)
            '<Staff id="$s">${[
              for (final (i, m) in measures.indexed)
                // Endings live on the top staff only.
                s == 1
                    ? m
                    : measure(i == 0
                        ? '<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>'
                        : '')
            ].join()}</Staff>'
        ].join()}'
        '</Score></museScore>';
    final bars = [
      measure('<TimeSig><sigN>4</sigN><sigD>4</sigD></TimeSig>',
          flags: '<startRepeat/>'),
      measure(start(
          '<endHookType>1</endHookType><beginText>1st and 2nd Verses'
          '</beginText><endings>1, 2</endings>',
          2)),
      measure('', flags: '<endRepeat>3</endRepeat>'),
      measure(
          stop(2) + start('<beginText>3.</beginText><endings>3</endings>', 1)),
      measure(stop(1)),
    ];

    test('marks every bar an ending covers, with its passes and text', () {
      final score = scoreFromMscx(doc(bars));
      expect([for (final m in score.measures) m.volta], [null, 1, 1, 3, null]);
      expect(score.measures[1].voltaPasses, [1, 2]);
      expect(score.measures[2].voltaPasses, [1, 2]);
      expect(score.measures[1].voltaText, '1st and 2nd Verses');
      // "3." only restates the number.
      expect(score.measures[3].voltaText, isNull);
      // A hooked end closes; an end with no hook type is MuseScore's open one.
      expect([for (final m in score.measures) m.voltaOpenEnd],
          [false, false, false, true, false]);
      expect(score.measures[1].voltaContinuesInto(score.measures[2]), isTrue);
      expect([for (final n in playbackTimeline(score)) n.measureIndex],
          [0, 1, 2, 0, 1, 2, 0, 3, 4]);
    });

    test('every staff takes the endings from the top staff', () {
      final system = staffSystemFromMscx(doc(bars, staves: 2));
      for (final staff in system.staves) {
        expect(
            [for (final m in staff.measures) m.volta], [null, 1, 1, 3, null]);
      }
    });

    test('our own writer round-trips them', () {
      final back = scoreFromMscx(scoreToMscx(scoreFromMscx(doc(bars))));
      expect([for (final m in back.measures) m.volta], [null, 1, 1, 3, null]);
      expect(back.measures[2].voltaPasses, [1, 2]);
      expect(back.measures[1].voltaText, '1st and 2nd Verses');
      expect([for (final m in back.measures) m.voltaOpenEnd],
          [false, false, false, true, false]);
    });
  });
}
