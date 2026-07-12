import 'package:partitura_core/partitura_core.dart';
import 'package:test/test.dart';

/// Property-style tests: instead of hand-picked examples these sweep the
/// whole (reasonable) input space and assert invariants that must hold
/// everywhere.
void main() {
  // Steps x alters -1..1 x octaves 2..6: 315 pitches games actually use.
  final pitches = [
    for (final step in Step.values)
      for (var alter = -1; alter <= 1; alter++)
        for (var octave = 2; octave <= 6; octave++)
          Pitch(step, alter: alter, octave: octave),
  ];

  final allIntervals = <Interval>[
    Interval.perfectUnison,
    Interval.minorSecond,
    Interval.majorSecond,
    Interval.minorThird,
    Interval.majorThird,
    Interval.perfectFourth,
    Interval.augmentedFourth,
    Interval.diminishedFifth,
    Interval.perfectFifth,
    Interval.augmentedFifth,
    Interval.minorSixth,
    Interval.majorSixth,
    Interval.minorSeventh,
    Interval.majorSeventh,
    Interval.perfectOctave,
  ];

  group('pitch invariants', () {
    test('midiNumber is strictly monotonic in diatonic+alter order', () {
      for (final pitch in pitches) {
        expect(
          Pitch(pitch.step, alter: pitch.alter, octave: pitch.octave + 1)
              .midiNumber,
          pitch.midiNumber + 12,
          reason: 'octave shift of $pitch',
        );
      }
    });

    test('parse(toString) round-trips every pitch', () {
      for (final pitch in pitches) {
        expect(Pitch.parse(pitch.toString()), pitch, reason: '$pitch');
      }
    });

    test('staffPosition differs by exactly the clef offset', () {
      for (final pitch in pitches) {
        expect(
          pitch.staffPosition(Clef.bass) - pitch.staffPosition(Clef.treble),
          12,
          reason: '$pitch',
        );
      }
    });
  });

  group('transposition invariants', () {
    test('semitone delta always equals interval.semitones', () {
      var checked = 0;
      for (final pitch in pitches) {
        for (final interval in allIntervals) {
          final Pitch up;
          try {
            up = pitch.transposeBy(interval);
          } on ArgumentError {
            continue; // beyond double alterations; fine
          }
          checked++;
          expect(
            up.midiNumber - pitch.midiNumber,
            interval.semitones,
            reason: '$pitch + $interval',
          );
          expect(
            up.diatonicIndex - pitch.diatonicIndex,
            interval.number - 1,
            reason: '$pitch + $interval spells diatonically',
          );
        }
      }
      // 7 steps x 3 alters x 5 octaves x 15 intervals = 1575 combinations;
      // only a handful (B# + A5 and friends) are legitimately unspellable.
      expect(checked, greaterThan(1560), reason: 'sweep must be broad');
    });

    test('up then down is the identity', () {
      for (final pitch in pitches) {
        for (final interval in allIntervals) {
          final Pitch up;
          try {
            up = pitch.transposeBy(interval);
          } on ArgumentError {
            continue;
          }
          expect(
            up.transposeBy(interval, descending: true),
            pitch,
            reason: '$pitch +- $interval',
          );
        }
      }
    });

    test('Interval.between recovers the interval used to transpose', () {
      for (final pitch in pitches) {
        for (final interval in allIntervals) {
          final Pitch up;
          try {
            up = pitch.transposeBy(interval);
          } on ArgumentError {
            continue;
          }
          if (interval == Interval.perfectUnison &&
              up.diatonicIndex == pitch.diatonicIndex) {
            // Unison of identical pitches; trivially P1.
          }
          expect(
            Interval.between(pitch, up),
            interval,
            reason: '$pitch -> $up',
          );
        }
      }
    });
  });

  group('scale invariants', () {
    final tonics = [
      for (final step in Step.values)
        for (var alter = -1; alter <= 1; alter++) Pitch(step, alter: alter),
    ];

    test('degree steps match the type pattern for every buildable scale', () {
      const patterns = {
        ScaleType.major: [0, 2, 4, 5, 7, 9, 11, 12],
        ScaleType.naturalMinor: [0, 2, 3, 5, 7, 8, 10, 12],
        ScaleType.harmonicMinor: [0, 2, 3, 5, 7, 8, 11, 12],
        ScaleType.melodicMinor: [0, 2, 3, 5, 7, 9, 11, 12],
      };
      for (final tonic in tonics) {
        for (final type in ScaleType.values) {
          final List<Pitch> scale;
          try {
            scale = Scale(tonic, type).pitches;
          } on ArgumentError {
            continue; // unbuildable extreme (e.g. needs triple sharp)
          }
          final semis = [
            for (final p in scale) p.midiNumber - scale.first.midiNumber,
          ];
          expect(semis, patterns[type], reason: '$tonic ${type.name}');
          // Diatonic spelling: consecutive letter names.
          for (var d = 1; d < 8; d++) {
            expect(
              scale[d].diatonicIndex - scale[d - 1].diatonicIndex,
              1,
              reason: 'degree $d of $tonic ${type.name}',
            );
          }
        }
      }
    });

    test('major and natural minor scales agree with the key signature', () {
      for (final tonic in tonics) {
        for (final isMajor in [true, false]) {
          final key = isMajor ? Key.major(tonic) : Key.minor(tonic);
          final KeySignature signature;
          try {
            signature = key.signature;
          } on ArgumentError {
            continue; // no standard signature
          }
          final scale = Scale(
            tonic,
            isMajor ? ScaleType.major : ScaleType.naturalMinor,
          );
          for (final pitch in scale.pitches) {
            expect(
              pitch.alter,
              signature.alterFor(pitch.step),
              reason:
                  '$pitch in $tonic ${isMajor ? 'major' : 'minor'} ($signature)',
            );
          }
        }
      }
    });
  });

  group('triad invariants', () {
    const structures = {
      ChordQuality.major: (4, 7),
      ChordQuality.minor: (3, 7),
      ChordQuality.diminished: (3, 6),
      ChordQuality.augmented: (4, 8),
    };

    test('semitone structure and spelling for all roots and qualities', () {
      final roots = [
        for (final step in Step.values)
          for (var alter = -1; alter <= 1; alter++) Pitch(step, alter: alter),
      ];
      for (final root in roots) {
        for (final quality in ChordQuality.values) {
          final List<Pitch> notes;
          try {
            notes = Triad(root, quality).pitches;
          } on ArgumentError {
            continue;
          }
          final (third, fifth) = structures[quality]!;
          expect(notes[0], root);
          expect(notes[1].midiNumber - notes[0].midiNumber, third,
              reason: '$root ${quality.name}');
          expect(notes[2].midiNumber - notes[0].midiNumber, fifth,
              reason: '$root ${quality.name}');
          // Spelled in thirds: root, +2 letters, +4 letters.
          expect(notes[1].diatonicIndex - notes[0].diatonicIndex, 2);
          expect(notes[2].diatonicIndex - notes[0].diatonicIndex, 4);
        }
      }
    });

    test('inversions rotate pitch content and stay ascending', () {
      for (final quality in ChordQuality.values) {
        for (var inversion = 0; inversion <= 2; inversion++) {
          final notes =
              Triad(const Pitch(Step.f), quality, inversion: inversion).pitches;
          expect(notes, hasLength(3));
          expect(notes[0].midiNumber, lessThan(notes[1].midiNumber));
          expect(notes[1].midiNumber, lessThan(notes[2].midiNumber));
        }
      }
    });
  });

  group('key invariants', () {
    test('T/S/D triads of a major key use only scale notes', () {
      const majors = ['c4', 'g4', 'd4', 'a4', 'e4', 'f4', 'bb4', 'eb4'];
      for (final source in majors) {
        final tonic = Pitch.parse(source);
        final key = Key.major(tonic);
        final scaleClasses = Scale(tonic, ScaleType.major)
            .pitches
            .map((p) => (p.step, p.alter))
            .toSet();
        for (final function in HarmonicFunction.values) {
          for (final pitch in key.triadFor(function).pitches) {
            expect(
              scaleClasses.contains((pitch.step, pitch.alter)),
              isTrue,
              reason: '$pitch of ${function.name} in $source major',
            );
          }
        }
      }
    });

    test('dominant of a minor key contains the raised leading tone', () {
      const minors = ['a4', 'e4', 'd4', 'g4', 'c4', 'b3'];
      for (final source in minors) {
        final tonic = Pitch.parse(source);
        final dominant = Key.minor(tonic).triadFor(HarmonicFunction.dominant);
        final leadingTone = Scale(tonic, ScaleType.harmonicMinor).pitches[6];
        expect(
          dominant.pitches
              .map((p) => (p.step, p.alter))
              .contains((leadingTone.step, leadingTone.alter)),
          isTrue,
          reason: '$source minor: D should contain $leadingTone',
        );
      }
    });
  });

  group('fraction algebra', () {
    final samples = [
      for (var n = -4; n <= 4; n++)
        for (final d in [1, 2, 3, 4, 8, 16]) Fraction(n, d),
    ];

    test('addition commutes and subtraction inverts', () {
      for (final a in samples) {
        for (final b in samples) {
          expect(a + b, b + a);
          expect(a + b - b, a);
        }
      }
    });

    test('comparison agrees with toDouble', () {
      for (final a in samples) {
        for (final b in samples) {
          expect(a < b, a.toDouble() < b.toDouble(), reason: '$a vs $b');
          expect(
            a.compareTo(b).sign,
            a.toDouble().compareTo(b.toDouble()).sign,
          );
        }
      }
    });

    test('equal values hash equally', () {
      for (final a in samples) {
        final same = Fraction(a.numerator * 6, a.denominator * 6);
        expect(a, same);
        expect(a.hashCode, same.hashCode);
      }
    });
  });

  group('duration invariants', () {
    test('every base x dots matches the dot-factor formula', () {
      for (final base in DurationBase.values) {
        var expected = base == DurationBase.breve
            ? Fraction(2, 1)
            : Fraction(1, base.denominator);
        var dotValue = expected * Fraction(1, 2);
        for (var dots = 0; dots <= 2; dots++) {
          final duration = NoteDuration(base, dots: dots);
          expect(duration.toFraction(), expected,
              reason: '${base.name} dots=$dots');
          final (n, d) = duration.fraction;
          expect(Fraction(n, d), expected);
          expected += dotValue;
          dotValue = Fraction(
            dotValue.numerator,
            dotValue.denominator * 2,
          );
        }
      }
    });
  });
}
