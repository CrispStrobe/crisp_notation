import 'dart:convert';
import 'dart:io';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Linked parts: an edit to one part's score-wide structure reaches the whole
/// score; its music stays its own.
void main() {
  NoteElement n(String id, Step step,
          {int octave = 4, DurationBase d = DurationBase.quarter}) =>
      NoteElement(
        id: id,
        pitches: [Pitch(step, octave: octave)],
        duration: NoteDuration(d),
      );

  /// A 3/4 bar of three quarter Cs (or [step]s) with ids `<p>.<bar>.<i>`.
  Measure bar(String p, int b, {Step step = Step.c}) =>
      Measure([for (var i = 0; i < 3; i++) n('$p.$b.$i', step)]);

  Score part(String p, {Transposition? t, Clef clef = Clef.treble}) => Score(
        clef: clef,
        timeSignature: const TimeSignature(3, 4),
        transposition: t,
        measures: [for (var b = 0; b < 4; b++) bar(p, b)],
      );

  final doc = MultiPartScore([part('a'), part('b', clef: Clef.bass)]);

  List<int?> pitches(Score s, int b) => [
        for (final e in s.measures[b].elements)
          if (e is NoteElement) e.pitches.first.midiNumber else null,
      ];

  group('bars', () {
    test('a bar inserted into one part is a rest bar in the others', () {
      final edited = doc.linkedPart(0).copyWith(measures: [
        ...doc.parts[0].measures.take(2),
        bar('new', 0, step: Step.g),
        ...doc.parts[0].measures.skip(2),
      ]);
      final linked = doc.withLinkedPart(0, edited);
      expect(linked.parts.map((p) => p.measures.length), [5, 5]);
      final inserted = linked.parts[1].measures[2];
      expect(inserted.elements, everyElement(isA<RestElement>()));
      // A 3/4 bar of rests holds exactly three quarters.
      expect(
          inserted.elements
              .fold(Fraction.zero, (a, e) => a + e.duration.toFraction()),
          Fraction(3, 4));
      // The neighbours are untouched.
      expect(linked.parts[1].measures[3], doc.parts[1].measures[2]);
    });

    test('a bar deleted from one part is deleted from all', () {
      final edited = doc.parts[1].copyWith(measures: [
        doc.parts[1].measures[0],
        ...doc.parts[1].measures.skip(2),
      ]);
      final linked = doc.withLinkedPart(1, edited);
      expect(linked.parts.map((p) => p.measures.length), [3, 3]);
      expect(linked.parts[0].measures[1], doc.parts[0].measures[2]);
    });

    test('a bar whose notes were all replaced keeps its place', () {
      final edited = doc.parts[0].copyWith(measures: [
        doc.parts[0].measures[0],
        bar('fresh', 1, step: Step.e), // new ids throughout
        ...doc.parts[0].measures.skip(2),
      ]);
      final linked = doc.withLinkedPart(0, edited);
      expect(linked.parts[1].measures.length, 4);
      expect(linked.parts[1], doc.parts[1]);
    });

    test('editing notes only leaves the other parts as they were', () {
      final edited = doc.parts[0].copyWith(measures: [
        Measure([n('a.0.0', Step.d), n('a.0.1', Step.e), n('a.0.2', Step.f)]),
        ...doc.parts[0].measures.skip(1),
      ]);
      final linked = doc.withLinkedPart(0, edited);
      expect(linked.parts[0], edited);
      expect(linked.parts[1], doc.parts[1]);
    });
  });

  group('score-wide fields', () {
    test('meter, tempo, repeats, voltas and navigation reach every part', () {
      final m = doc.parts[0].measures;
      final edited = doc.parts[0].copyWith(measures: [
        m[0].copyWith(startRepeat: true),
        m[1].copyWith(
            endRepeat: true,
            volta: 1,
            tempoChange: const Tempo(90),
            barline: BarlineStyle.doubleBar),
        m[2].copyWith(
            volta: 2,
            timeChange: const TimeSignature(2, 4),
            navigation: NavigationMark.fine),
        m[3],
      ]);
      final other = doc.withLinkedPart(0, edited).parts[1].measures;
      expect(other[0].startRepeat, isTrue);
      expect(other[1].endRepeat, isTrue);
      expect(other.map((x) => x.volta), [null, 1, 2, null]);
      expect(other[1].tempoChange?.bpm, 90);
      expect(other[1].barline, BarlineStyle.doubleBar);
      expect(other[2].timeChange, const TimeSignature(2, 4));
      expect(other[2].navigation, NavigationMark.fine);
    });

    test('clefs and notes stay with their own part', () {
      final m = doc.parts[0].measures;
      final edited = doc.parts[0].copyWith(measures: [
        m[0],
        m[1].copyWith(clefChange: Clef.alto),
        ...m.skip(2),
      ]);
      final other = doc.withLinkedPart(0, edited).parts[1];
      expect(other.measures[1].clefChange, isNull);
      expect(pitches(other, 0), pitches(doc.parts[1], 0));
    });

    test('clearing a mark in one part clears it everywhere', () {
      final marked = doc.withLinkedPart(
          0,
          doc.parts[0].copyWith(measures: [
            doc.parts[0].measures[0].copyWith(startRepeat: true),
            ...doc.parts[0].measures.skip(1),
          ]));
      final cleared = marked.withLinkedPart(
          1,
          marked.parts[1].copyWith(measures: [
            Measure(marked.parts[1].measures[0].elements),
            ...marked.parts[1].measures.skip(1),
          ]));
      expect(cleared.parts[0].measures[0].startRepeat, isFalse);
    });
  });

  group('transposing instruments', () {
    // Score order: flute (concert), B-flat clarinet, horn in F.
    final band = MultiPartScore([
      part('fl'),
      part('cl', t: Transposition.bFlat),
      part('hn', t: Transposition.f),
    ]);

    test('a key change takes each part\'s written key', () {
      // The clarinet writes D major (+2): the band sounds C major.
      final m = band.parts[1].measures;
      final edited = band.parts[1].copyWith(measures: [
        m[0],
        m[1].copyWith(keyChange: const KeySignature(2)),
        ...m.skip(2),
      ]);
      final linked = band.withLinkedPart(1, edited);
      expect(linked.parts[0].measures[1].keyChange, const KeySignature(0));
      expect(linked.parts[1].measures[1].keyChange, const KeySignature(2));
      expect(linked.parts[2].measures[1].keyChange, const KeySignature(1));
    });

    test('a part edited at concert pitch comes back written', () {
      final concert = band.linkedPart(1, concertPitch: true);
      expect(concert.transposition, isNull);
      expect(pitches(concert, 0).first, 58); // written C4 sounds B-flat 3
      // Write a concert C4 into the first beat.
      final m = concert.measures;
      final edited = concert.copyWith(measures: [
        Measure([n('cl.0.0', Step.c), ...m[0].elements.skip(1)]),
        ...m.skip(1),
      ]);
      final back = band.withLinkedPart(1, edited, concertPitch: true).parts[1];
      expect(back.transposition, Transposition.bFlat);
      expect(pitches(back, 0).first, 62); // D4 written
      expect(pitches(back.atConcertPitch(), 0).first, 60);
    });
  });

  group('robustness', () {
    test('a part that lost bars still lays out, plays and exports', () {
      final withSpans = MultiPartScore([
        part('a'),
        part('b').copyWith(slurs: const [Slur('b.1.0', 'b.1.2')]),
      ]);
      final edited = withSpans.parts[0].copyWith(measures: [
        withSpans.parts[0].measures[0],
        ...withSpans.parts[0].measures.skip(2),
      ]);
      final other = withSpans.withLinkedPart(0, edited).parts[1];
      expect(other.measures.length, 3);
      final metadata =
          File('../crisp_notation/assets/smufl/bravura_metadata.json')
              .readAsStringSync();
      final settings = LayoutSettings(
          metadata: SmuflMetadata.fromJson(
              jsonDecode(metadata) as Map<String, Object?>));
      expect(
          () => const LayoutEngine().layout(other, settings), returnsNormally);
      expect(playbackTimeline(other), isNotEmpty);
      expect(scoreFromMusicXml(scoreToMusicXml(other)).measures.length, 3);
    });
  });

  group('the pieces it is built from', () {
    test('KeySignature.transposedBy moves the tonic and wraps', () {
      expect(const KeySignature(0).transposedBy(Interval.majorSecond),
          const KeySignature(2));
      expect(
          const KeySignature(0)
              .transposedBy(Interval.majorSecond, descending: true),
          const KeySignature(-2));
      // B major up a major third is D-sharp major — nine sharps — so it is
      // written as E-flat major.
      expect(const KeySignature(5).transposedBy(Interval.majorThird),
          const KeySignature(-3));
    });

    test('atWrittenPitch is the inverse of atConcertPitch', () {
      final concert = part('x');
      for (final t in [
        Transposition.bFlat,
        Transposition.eFlat,
        Transposition.f,
        const Transposition(Interval.perfectUnison, octaves: 1),
      ]) {
        final written = concert.atWrittenPitch(t);
        expect(written.transposition, t);
        expect(written.atConcertPitch(), concert, reason: '$t');
      }
    });

    test('transposedBy keeps every per-bar field', () {
      final s = part('y').copyWith(measures: [
        Measure(bar('y', 0).elements,
            tempoChange: const Tempo(72),
            actualDuration: Fraction(3, 4),
            inlineClefs: [InlineClefChange(Fraction(1, 4), Clef.bass)]),
        Measure(const [], measureRepeat: 1),
      ]);
      final moved = s.transposedBy(Interval.majorSecond);
      expect(moved.measures[0].tempoChange?.bpm, 72);
      expect(moved.measures[0].actualDuration, Fraction(3, 4));
      expect(moved.measures[0].inlineClefs, hasLength(1));
      expect(moved.measures[1].measureRepeat, 1);
    });
  });
}
