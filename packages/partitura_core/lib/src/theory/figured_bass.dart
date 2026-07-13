/// Figured-bass realization (Phase 4.6).
///
/// Turns a figured bass (bass pitches + figures such as `6`, `6/4`, `7`, `#`)
/// in a key into a four-part (SATB) texture, choosing each chord's voicing to
/// minimise motion and part-writing errors (graded by [checkVoiceLeading], the
/// Phase 4.2 engine). Pure theory (no rendering).
library;

import 'key.dart';
import 'pitch.dart';
import 'voice_leading.dart';

// SATB comfortable ranges in MIDI: tenor C3–A4, alto F3–D5, soprano C4–A5.
const _tenorRange = (48, 69);
const _altoRange = (53, 74);
const _sopranoRange = (60, 81);

/// The pitch classes of the chord a [figure] specifies above [bass] in [key].
/// The figure's numbers are diatonic intervals above the bass (`6` = a sixth,
/// etc.); an accidental (`#`, `b`, `n`, `+`) raises/lowers/naturalises that
/// degree, and a lone accidental applies to the third. An empty figure is a
/// root-position triad (`5/3`).
Set<int> figuredChordPitchClasses(Pitch bass, String figure, Key key) =>
    {for (final p in _chordPitches(bass, figure, key)) p.midiNumber % 12};

/// Realises [figuredBass] — a list of `(bassPitch, figure)` pairs — into SATB
/// chords in [key]. Each result is `[soprano, alto, tenor, bass]` (top to
/// bottom). The first chord is voiced in close-ish position; each later chord
/// is the voicing minimising `Σ|motion| + 100·(voice-leading errors)` from the
/// previous one, so common tones are held and parallels avoided where possible.
List<List<Pitch>> realizeFiguredBass(
    List<(Pitch bass, String figure)> figuredBass, Key key) {
  final result = <List<Pitch>>[];
  List<Pitch>? prev;
  for (final (bass, figure) in figuredBass) {
    final chordPitches = _chordPitches(bass, figure, key);
    final chordPcs = {for (final p in chordPitches) p.midiNumber % 12};
    final sopranos = _voiceCandidates(chordPitches, _sopranoRange);
    final altos = _voiceCandidates(chordPitches, _altoRange);
    final tenors = _voiceCandidates(chordPitches, _tenorRange);

    List<Pitch>? best;
    var bestScore = double.infinity;
    for (final s in sopranos) {
      for (final a in altos) {
        if (a.midiNumber > s.midiNumber) continue;
        for (final t in tenors) {
          if (t.midiNumber > a.midiNumber || t.midiNumber < bass.midiNumber) {
            continue;
          }
          final voicing = [s, a, t, bass];
          // Every chord tone must be present across the four voices.
          final pcs = {for (final p in voicing) p.midiNumber % 12};
          if (pcs.length != chordPcs.length) continue;
          final double score;
          if (prev == null) {
            score = (s.midiNumber - t.midiNumber).toDouble(); // close position
          } else {
            var motion = 0;
            for (var i = 0; i < 4; i++) {
              motion += (voicing[i].midiNumber - prev[i].midiNumber).abs();
            }
            final errs = checkVoiceLeading([prev, voicing]).length;
            score = motion + errs * 100.0;
          }
          if (score < bestScore) {
            bestScore = score;
            best = voicing;
          }
        }
      }
    }
    // Fallback (a chord with no in-range complete voicing): stack the tones.
    best ??= _stack(chordPitches, bass);
    result.add(best);
    prev = best;
  }
  return result;
}

/// The bass plus the pitches at each figured interval above it (spelled).
List<Pitch> _chordPitches(Pitch bass, String figure, Key key) {
  final pitches = <Pitch>[bass];
  for (final (interval, acc) in _figureIntervals(figure)) {
    pitches.add(_diatonicAbove(bass, interval, key, acc));
  }
  return pitches;
}

/// The pitch a diatonic [n]th above [bass] in [key], with an optional figure
/// [acc] raising/lowering/naturalising it.
Pitch _diatonicAbove(Pitch bass, int n, Key key, String? acc) {
  final targetDiatonic = bass.diatonicIndex + (n - 1);
  final step = Step.values[targetDiatonic % 7];
  final octave = targetDiatonic ~/ 7;
  var alter = key.signature.alterFor(step);
  switch (acc) {
    case '#' || '+':
      alter += 1;
    case 'b':
      alter -= 1;
    case 'n':
      alter = 0;
  }
  return Pitch(step, alter: alter.clamp(-2, 2), octave: octave);
}

/// Parses [figure] into `(interval, accidental?)` pairs above the bass,
/// expanding the standard shorthands to full chords.
List<(int, String?)> _figureIntervals(String figure) {
  final tokens = <(int, String?)>[];
  String? looseAcc; // a lone accidental → the third
  // Each figured-bass number is a single digit (stacked, not a multi-digit
  // number): `64` is a sixth over a fourth, not "sixty-four".
  for (final m in RegExp(r'([#b+n]?)(\d)|([#b+n])').allMatches(figure)) {
    if (m.group(3) != null) {
      looseAcc = m.group(3);
      continue;
    }
    tokens
        .add((int.parse(m.group(2)!), m.group(1)!.isEmpty ? null : m.group(1)));
  }
  final nums = {for (final t in tokens) t.$1};
  final accOf = {for (final t in tokens) t.$1: t.$2};

  List<int> full;
  bool has(Set<int> x) => nums.length == x.length && nums.containsAll(x);
  if (nums.isEmpty || has({3}) || has({5}) || has({5, 3})) {
    full = [3, 5];
  } else if (has({6}) || has({6, 3})) {
    full = [3, 6];
  } else if (has({6, 4})) {
    full = [4, 6];
  } else if (has({7}) || has({7, 3}) || has({7, 5}) || has({7, 5, 3})) {
    full = [3, 5, 7];
  } else if (has({6, 5}) || has({6, 5, 3})) {
    full = [3, 5, 6];
  } else if (has({4, 3}) || has({6, 4, 3})) {
    full = [3, 4, 6];
  } else if (has({2}) || has({4, 2}) || has({6, 4, 2})) {
    full = [2, 4, 6];
  } else {
    full = nums.toList()..sort();
  }
  return [
    for (final iv in full) (iv, accOf[iv] ?? (iv == 3 ? looseAcc : null))
  ];
}

/// Octave-shifted copies of [chordPitches] that land within [range].
List<Pitch> _voiceCandidates(List<Pitch> chordPitches, (int, int) range) {
  final out = <Pitch>[];
  for (final cp in chordPitches) {
    for (var oct = -3; oct <= 3; oct++) {
      final p = Pitch(cp.step, alter: cp.alter, octave: cp.octave + oct);
      if (p.midiNumber >= range.$1 && p.midiNumber <= range.$2) out.add(p);
    }
  }
  return out;
}

/// A last-resort voicing: the chord tones stacked just above the bass.
List<Pitch> _stack(List<Pitch> chordPitches, Pitch bass) {
  final upper = [
    for (final cp in chordPitches)
      if (cp.midiNumber % 12 != bass.midiNumber % 12)
        _lift(cp, bass.midiNumber),
  ]..sort((a, b) => a.midiNumber.compareTo(b.midiNumber));
  while (upper.length < 3) {
    upper.add(_lift(chordPitches.first, (upper.lastOrNull ?? bass).midiNumber));
  }
  return [upper[2], upper[1], upper[0], bass];
}

Pitch _lift(Pitch p, int above) {
  var q = p;
  while (q.midiNumber <= above) {
    q = Pitch(q.step, alter: q.alter, octave: q.octave + 1);
  }
  return q;
}
