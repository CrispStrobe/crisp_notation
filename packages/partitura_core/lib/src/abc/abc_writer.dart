/// ABC notation export.
///
/// Serializes a [Score] to an ABC tune string — the inverse of
/// [scoreFromAbc]. Emits the `M`/`L`/`K` header then a body with pitched notes
/// (accidental, octave marks, `L`-relative length), rests, chords, ties,
/// tuplets, slurs, grace notes, staccato, `"C"` chord symbols and bar lines
/// (repeats, double/final). A single lyric verse is written as a `w:` line.
/// Because both codecs funnel through the one [Score] model, a score
/// round-trips through ABC for the data ABC can represent.
library;

import '../model/element.dart';
import '../model/measure.dart';
import '../model/score.dart';
import '../theory/duration.dart';
import '../theory/fraction.dart';
import '../theory/key_signature.dart';
import '../theory/pitch.dart';

/// Serializes [score] to an ABC tune. [unitLength] is the `L:` field (default
/// 1/8); [index] is the `X:` tune number; [title] the optional `T:` field.
String scoreToAbc(
  Score score, {
  Fraction? unitLength,
  int index = 1,
  String? title,
}) {
  final unit = unitLength ?? Fraction(1, 8);
  final b = StringBuffer();
  b.writeln('X:$index');
  if (title != null) b.writeln('T:$title');
  final ts = score.timeSignature;
  // TimeSignature.toString() is C / C| / beats/beatUnit — exactly the ABC form.
  if (ts != null) b.writeln('M:$ts');
  b.writeln('L:${unit.numerator}/${unit.denominator}');
  b.writeln('K:${_keyName(score.keySignature)}');

  final chordSymbols = {
    for (final a in score.annotations) a.elementId: a.text,
  };
  final dynamicsById = {
    for (final d in score.dynamics) d.elementId: d.level,
  };
  final slurStarts = <String, int>{};
  final slurEnds = <String, int>{};
  for (final s in score.slurs) {
    slurStarts[s.startId] = (slurStarts[s.startId] ?? 0) + 1;
    slurEnds[s.endId] = (slurEnds[s.endId] ?? 0) + 1;
  }

  final body = StringBuffer();
  for (var m = 0; m < score.measures.length; m++) {
    final measure = score.measures[m];
    if (measure.startRepeat) body.write('|:');
    if (measure.volta != null) body.write('[${measure.volta}');
    if (measure.navigation != null) {
      body.write(switch (measure.navigation!) {
        NavigationMark.segno => '!segno!',
        NavigationMark.coda => '!coda!',
        NavigationMark.toCoda => '!dacoda!',
        NavigationMark.daCapo => '!D.C.!',
        NavigationMark.daCapoAlFine => '!D.C.alfine!',
        NavigationMark.daCapoAlCoda => '!D.C.alcoda!',
        NavigationMark.dalSegno => '!D.S.!',
        NavigationMark.dalSegnoAlFine => '!D.S.alfine!',
        NavigationMark.dalSegnoAlCoda => '!D.S.alcoda!',
        NavigationMark.fine => '!fine!',
      });
    }
    // Mid-tune key / meter / unit changes, and multi-measure rests.
    if (measure.keyChange != null) {
      body.write('[K:${_keyName(measure.keyChange!)}]');
    }
    if (measure.timeChange != null) {
      body.write('[M:${measure.timeChange}]');
    }
    if (measure.multiRest != null) {
      body.write('Z${measure.multiRest} |');
      continue;
    }
    // Which element index each tuplet starts/ends at.
    // A tuplet in ABC is marked by `(p` before its first note and closes
    // implicitly after p notes, so only the start index is needed.
    final tupletStart = {for (final t in measure.tuplets) t.startIndex: t};

    final acc = <String, int>{}; // measure accidental state, by letter
    for (var i = 0; i < measure.elements.length; i++) {
      final element = measure.elements[i];
      if (tupletStart.containsKey(i)) {
        final t = tupletStart[i]!;
        body.write(t.actual == 3 && t.normal == 2 ? '(3' : '(${t.actual}');
      }
      if (element is RestElement) {
        body.write('z${_lengthOf(element.duration, unit)}');
      } else if (element is NoteElement) {
        final id = element.id;
        if (id != null && chordSymbols.containsKey(id)) {
          body.write('"${chordSymbols[id]}"');
        }
        if (id != null && element.graceNotes.isNotEmpty) {
          body.write('{${element.graceNotes.map(_bareNote).join()}}');
        }
        if (id != null && dynamicsById.containsKey(id)) {
          body.write('!${dynamicsById[id]!.name}!');
        }
        // Decorations: `.` for staccato, `!…!` for the rest and ornaments.
        for (final a in element.articulations) {
          body.write(switch (a) {
            Articulation.staccato => '.',
            Articulation.accent => '!accent!',
            Articulation.tenuto => '!tenuto!',
            Articulation.marcato => '!marcato!',
            Articulation.fermata => '!fermata!',
            Articulation.upBow => 'u',
            Articulation.downBow => 'v',
          });
        }
        final orn = switch (element.ornament) {
          Ornament.trill => '!trill!',
          Ornament.shortTrill => '!uppermordent!',
          Ornament.mordent => '!lowermordent!',
          Ornament.turn => '!turn!',
          Ornament.invertedTurn => '!invertedturn!',
          // ABC has no trill-with-accidental sign; fall back to a plain trill.
          Ornament.trillSharp ||
          Ornament.trillFlat ||
          Ornament.trillNatural =>
            '!trill!',
          null => '',
        };
        body.write(orn);
        for (var k = 0; k < (id == null ? 0 : slurStarts[id] ?? 0); k++) {
          body.write('(');
        }
        final len = _lengthOf(element.duration, unit);
        if (element.pitches.length == 1) {
          body.write(
              '${_noteToken(element.pitches.single, acc, score.keySignature)}$len');
        } else {
          final inner = element.pitches
              .map((p) => _noteToken(p, acc, score.keySignature))
              .join();
          body.write('[$inner]$len');
        }
        if (element.tieToNext) body.write('-');
        for (var k = 0; k < (id == null ? 0 : slurEnds[id] ?? 0); k++) {
          body.write(')');
        }
      }
      body.write(' ');
    }
    if (measure.endRepeat) {
      body.write(':|');
    } else {
      body.write(switch (measure.barline) {
        BarlineStyle.doubleBar => '||',
        BarlineStyle.finalBar => m == score.measures.length - 1 ? '|]' : '|',
        BarlineStyle.dotted => '.|',
        _ => '|',
      });
    }
    // Wrap bodies at a sensible width by breaking every 4 bars.
    if ((m + 1) % 4 == 0) body.write('\n');
  }
  b.writeln(body.toString().trimRight());

  final verse1 = score.lyrics.where((l) => l.verse == 1).toList();
  if (verse1.isNotEmpty) {
    b.writeln(
        'w:${verse1.map((l) => l.text + (l.hyphenToNext ? '-' : '')).join(' ')}');
  }
  return b.toString();
}

/// The ABC token for [pitch] — octave letter with an explicit accidental only
/// when it differs from the running accidental ([acc], by letter) or the [key].
String _noteToken(Pitch pitch, Map<String, int> acc, KeySignature key) {
  final letter = _letter(pitch.step);
  final keyAlter =
      key.alteredSteps.contains(pitch.step) ? (key.fifths >= 0 ? 1 : -1) : 0;
  final effective = acc[letter] ?? keyAlter;
  var prefix = '';
  if (pitch.alter != effective) {
    prefix = switch (pitch.alter) {
      2 => '^^',
      1 => '^',
      0 => '=',
      -1 => '_',
      _ => '__',
    };
    acc[letter] = pitch.alter;
  }
  return '$prefix${_octaveLetter(pitch)}';
}

/// The pitch as a bare octave letter with an always-explicit accidental
/// (for grace notes, where measure state is not tracked).
String _bareNote(Pitch pitch) {
  final prefix = switch (pitch.alter) {
    2 => '^^',
    1 => '^',
    0 => '',
    -1 => '_',
    _ => '__',
  };
  return '$prefix${_octaveLetter(pitch)}';
}

String _octaveLetter(Pitch pitch) {
  final letter = _letter(pitch.step);
  if (pitch.octave >= 5) {
    return letter.toLowerCase() + "'" * (pitch.octave - 5);
  }
  return letter + ',' * (4 - pitch.octave);
}

String _letter(Step step) => switch (step) {
      Step.c => 'C',
      Step.d => 'D',
      Step.e => 'E',
      Step.f => 'F',
      Step.g => 'G',
      Step.a => 'A',
      Step.b => 'B',
    };

/// The ABC length suffix for [duration] relative to the [unit] note length.
String _lengthOf(NoteDuration duration, Fraction unit) {
  final whole = _wholeFraction(duration);
  final mult = whole * Fraction(unit.denominator, unit.numerator);
  final n = mult.numerator, d = mult.denominator;
  if (n == 1 && d == 1) return '';
  if (d == 1) return '$n';
  if (n == 1) return '/$d';
  return '$n/$d';
}

Fraction _wholeFraction(NoteDuration duration) {
  final base = switch (duration.base) {
    DurationBase.breve => Fraction(2, 1),
    DurationBase.whole => Fraction(1, 1),
    DurationBase.half => Fraction(1, 2),
    DurationBase.quarter => Fraction(1, 4),
    DurationBase.eighth => Fraction(1, 8),
    DurationBase.sixteenth => Fraction(1, 16),
    DurationBase.thirtySecond => Fraction(1, 32),
    DurationBase.sixtyFourth => Fraction(1, 64),
  };
  // Dots: 1 → ×3/2, 2 → ×7/4.
  final dotMul = switch (duration.dots) {
    1 => Fraction(3, 2),
    2 => Fraction(7, 4),
    _ => Fraction(1, 1),
  };
  return base * dotMul;
}

const _fifthsToKey = {
  0: 'C', 1: 'G', 2: 'D', 3: 'A', 4: 'E', 5: 'B', 6: 'F#', 7: 'C#', //
  -1: 'F', -2: 'Bb', -3: 'Eb', -4: 'Ab', -5: 'Db', -6: 'Gb', -7: 'Cb',
};

String _keyName(KeySignature key) => _fifthsToKey[key.fifths] ?? 'C';
