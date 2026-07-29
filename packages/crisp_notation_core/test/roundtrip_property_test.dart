import 'dart:math';

import 'package:crisp_notation_core/crisp_notation_core.dart';
import 'package:test/test.dart';

/// Property-based round-trip fidelity: generate many diverse, valid scores from
/// fixed seeds (deterministic, so a failure reproduces exactly) and assert two
/// invariants survive each interchange codec —
///
///  * **note multiset**: the bag of (midi, written-duration) pairs, and
///  * **sounding total**: the tuplet-scaled total duration of the score.
///
/// The multiset alone misses tuplet/timing bugs (a dropped triplet keeps the
/// note values but changes how long they sound); the sounding-total invariant
/// is what surfaced the multi-voice kern tuplet regression. This complements the
/// example-based probes in roundtrip_fidelity_test.dart with broad coverage:
/// unusual meters, the full duration range, dots, ties, tuplets and a second
/// voice.

// (midi, written-duration) across every voice, order-independent.
List<(int, String)> _multiset(Score s) {
  final out = <(int, String)>[];
  for (final m in s.measures) {
    for (final voice in [m.elements, m.voice2, m.voice3, m.voice4]) {
      for (final e in voice) {
        if (e is NoteElement) {
          for (final p in e.pitches) {
            final f = e.duration.toFraction();
            out.add((p.midiNumber, '${f.numerator}/${f.denominator}'));
          }
        }
      }
    }
  }
  out.sort(
      (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return out;
}

// Tuplet-scaled total sounding duration of voice 1 across the score.
String _soundingTotal(Score s) {
  var num = 0, den = 1;
  for (final m in s.measures) {
    final f = m.totalDuration;
    num = num * f.denominator + f.numerator * den;
    den = den * f.denominator;
    final g = num.gcd(den == 0 ? 1 : den);
    if (g > 1) {
      num ~/= g;
      den ~/= g;
    }
  }
  return '$num/$den';
}

// The effective (clef, key) as it evolves measure-by-measure — catches a
// mid-score change that is dropped or a change back to the initial value that a
// reader mistakes for "no change". (Meter changes would alter measure capacity,
// so the generator injects only capacity-neutral clef/key changes.)
List<String> _stateSeq(Score s) {
  var clef = s.clef;
  var key = s.keySignature;
  final out = <String>[];
  for (final m in s.measures) {
    if (m.clefChange != null) clef = m.clefChange!;
    if (m.keyChange != null) key = m.keyChange!;
    out.add('${clef.name}/${key.fifths}');
  }
  return out;
}

// Written duration in 64ths of a whole note.
int _units(NoteDuration d) {
  const base = {
    DurationBase.breve: 128,
    DurationBase.whole: 64,
    DurationBase.half: 32,
    DurationBase.quarter: 16,
    DurationBase.eighth: 8,
    DurationBase.sixteenth: 4,
    DurationBase.thirtySecond: 2,
    DurationBase.sixtyFourth: 1,
  };
  final b = base[d.base]!;
  return d.dots == 0
      ? b
      : d.dots == 1
          ? b + b ~/ 2
          : b + b ~/ 2 + b ~/ 4;
}

Pitch _pitch(Random rng) => Pitch(
      Step.values[rng.nextInt(7)],
      alter: const [0, 0, 0, 1, -1, 2, -2][rng.nextInt(7)],
      octave: 2 + rng.nextInt(5),
    );

// Fill one voice to [capacityUnits] with a random rhythm, occasionally a
// triplet (returned as a TupletSpan over the emitted notes) or a tie.
(List<MusicElement>, List<TupletSpan>) _voice(
    Random rng, int capacityUnits, int Function() nextId) {
  final els = <MusicElement>[];
  final tuplets = <TupletSpan>[];
  var remaining = capacityUnits;
  final durs = <NoteDuration>[
    NoteDuration.whole,
    NoteDuration.half,
    NoteDuration.quarter,
    NoteDuration.eighth,
    NoteDuration.sixteenth,
    const NoteDuration(DurationBase.thirtySecond),
    const NoteDuration(DurationBase.half, dots: 1),
    const NoteDuration(DurationBase.quarter, dots: 1),
    const NoteDuration(DurationBase.eighth, dots: 1),
    const NoteDuration(DurationBase.quarter, dots: 2),
  ];
  while (remaining > 0) {
    if (rng.nextInt(5) == 0) {
      final tb =
          const [DurationBase.eighth, DurationBase.sixteenth][rng.nextInt(2)];
      final u = _units(NoteDuration(tb));
      if (2 * u <= remaining) {
        final start = els.length;
        for (var k = 0; k < 3; k++) {
          els.add(NoteElement(
              pitches: [_pitch(rng)],
              duration: NoteDuration(tb),
              id: 'e${nextId()}'));
        }
        tuplets.add(TupletSpan(start, start + 2, actual: 3, normal: 2));
        remaining -= 2 * u;
        continue;
      }
    }
    final choices = durs.where((d) => _units(d) <= remaining).toList();
    if (choices.isEmpty) {
      els.add(NoteElement(
          pitches: [_pitch(rng)],
          duration: const NoteDuration(DurationBase.sixtyFourth),
          id: 'e${nextId()}'));
      remaining -= 1;
      continue;
    }
    final pick = choices[rng.nextInt(choices.length)];
    remaining -= _units(pick);
    final id = 'e${nextId()}';
    if (rng.nextInt(7) == 0) {
      els.add(RestElement(pick, id: id));
    } else {
      final n = 1 + (rng.nextInt(9) == 0 ? rng.nextInt(3) : 0);
      final pitches = <Pitch>{};
      var guard = 0;
      while (pitches.length < n && guard++ < 20) {
        pitches.add(_pitch(rng));
      }
      final list = pitches.toList();
      if (rng.nextInt(6) == 0 &&
          els.isNotEmpty &&
          els.last is NoteElement &&
          (els.last as NoteElement).pitches.length == 1 &&
          list.length == 1 &&
          (els.last as NoteElement).pitches.first == list.first) {
        final prev = els.removeLast() as NoteElement;
        els.add(NoteElement(
            pitches: prev.pitches,
            duration: prev.duration,
            id: prev.id,
            tieToNext: true));
      }
      els.add(NoteElement(pitches: list, duration: pick, id: id));
    }
  }
  return (els, tuplets);
}

const _meters = <(int, int)>[
  (4, 4), (3, 4), (2, 4), (6, 8), (9, 8), (5, 4), (7, 8), (2, 2), (3, 8),
  (5, 8), (12, 8), //
];

Score _generate(int seed) {
  final rng = Random(seed);
  var counter = 0;
  int nextId() => counter++;
  final clef =
      const [Clef.treble, Clef.bass, Clef.alto, Clef.tenor][rng.nextInt(4)];
  final key = KeySignature(rng.nextInt(15) - 7);
  final meter = _meters[rng.nextInt(_meters.length)];
  final ts = TimeSignature(meter.$1, meter.$2);
  final cap = ts.measureCapacity;
  final capUnits = 64 * cap.$1 ~/ cap.$2;
  final nBars = 1 + rng.nextInt(4);
  var runningClef = clef;
  var runningKey = key;
  final measures = <Measure>[];
  for (var b = 0; b < nBars; b++) {
    final (els, tups) = _voice(rng, capUnits, nextId);
    // Capacity-neutral mid-score changes on inner bars. 1/3 of the time the
    // change targets the *initial* clef/key — the case that exposed the
    // reader's running-vs-leading bug.
    Clef? clefChange;
    KeySignature? keyChange;
    if (b > 0 && rng.nextInt(3) == 0) {
      final target = rng.nextInt(3) == 0
          ? clef
          : const [Clef.treble, Clef.bass][rng.nextInt(2)];
      if (target != runningClef) {
        clefChange = target;
        runningClef = target;
      }
    }
    if (b > 0 && rng.nextInt(3) == 0) {
      final target =
          rng.nextInt(3) == 0 ? key : KeySignature(rng.nextInt(7) - 3);
      if (target != runningKey) {
        keyChange = target;
        runningKey = target;
      }
    }
    if (rng.nextInt(3) == 0) {
      final (v2, _) = _voice(rng, capUnits, nextId);
      measures.add(Measure(els,
          voice2: v2,
          tuplets: tups,
          clefChange: clefChange,
          keyChange: keyChange));
    } else {
      measures.add(Measure(els,
          tuplets: tups, clefChange: clefChange, keyChange: keyChange));
    }
  }
  return Score(
      clef: clef, keySignature: key, timeSignature: ts, measures: measures);
}

void main() {
  // Notation codecs that claim a lossless note/duration round-trip.
  final codecs = <String, (String Function(Score), Score Function(String))>{
    'MusicXML': (scoreToMusicXml, scoreFromMusicXml),
    'MEI': (scoreToMei, scoreFromMei),
    'kern': (scoreToKern, scoreFromKern),
    'ABC': (scoreToAbc, scoreFromAbc),
    'MuseScore': (scoreToMscx, scoreFromMscx),
    'LilyPond': (scoreToLilyPond, scoreFromLilyPond),
  };

  const seeds = 150;

  // ABC is a folk-tune subset: mid-tune clef/key changes are a documented loss,
  // so the clef/key-sequence invariant applies to the full codecs only.
  const fullCodecs = {'MusicXML', 'MEI', 'kern', 'MuseScore'};

  // ⚠️ A round-trip only exercises what OUR OWN WRITER emits, so it is blind to
  // read-only syntax. The `\<` chord-swallow bug emptied 17 real LilyPond
  // scores and silently truncated 23 more, and no round-trip could have caught
  // it — our writer never emits `\<`. Reader-only constructs need fixture or
  // corpus tests instead; see lilypond_named_context_test.dart.

  codecs.forEach((name, codec) {
    test('$name preserves note content over $seeds generated scores', () {
      final checkState = fullCodecs.contains(name);
      for (var seed = 1; seed <= seeds; seed++) {
        final score = _generate(seed);
        final want = _multiset(score);
        if (want.isEmpty) continue;
        final wantSound = _soundingTotal(score);
        final wantState = _stateSeq(score);

        final Score back;
        try {
          back = codec.$2(codec.$1(score));
        } catch (e) {
          fail('seed $seed: round-trip threw: $e');
        }

        expect(_multiset(back), want,
            reason: 'seed $seed: note multiset changed');
        expect(_soundingTotal(back), wantSound,
            reason: 'seed $seed: sounding total drifted '
                '(a tuplet or duration was mis-encoded)');
        if (checkState) {
          expect(_stateSeq(back), wantState,
              reason: 'seed $seed: mid-score clef/key sequence drifted '
                  '(a change was dropped or a change back to the initial value '
                  'was missed)');
        }
      }
    });
  });
}
