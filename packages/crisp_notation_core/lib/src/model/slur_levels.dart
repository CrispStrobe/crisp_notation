import 'score.dart';

/// Assigns each slur a nesting LEVEL, so a format that marks slurs with bare
/// delimiters can tell two concurrent ones apart.
///
/// ⚠️ Both `**kern` and LilyPond mark slurs with a delimiter that carries no
/// identity of its own — `(`/`)` in kern, the same in LilyPond. That is
/// ambiguous the moment two slurs are open at once, and the two failure modes
/// are silent: a NESTED pair loses its outer slur (the inner close consumes the
/// outer start), and a CHAIN sharing a boundary note collapses into a slur from
/// that note to itself. Both formats provide a numbered form for exactly this
/// — kern's `&(`/`&)` and LilyPond's `\=1(`/`\=1)` — and this is what decides
/// which slurs need one.
///
/// Two slurs get different levels when their spans overlap **strictly**.
/// Merely TOUCHING — one ending on the note the next begins — needs no level,
/// because both readers take every CLOSE before any OPEN, which is the same
/// close-before-open rule the writers follow. Numbering those too would be
/// correct but noisy, and `c4)( d` is the idiomatic LilyPond for a chain.
///
/// Returns the level per slur, in the order [score].slurs holds them. A slur
/// whose endpoints are not both found is given level 0 and left to the caller.
List<int> slurLevels(Score score) {
  final index = <String, int>{};
  var i = 0;
  for (final m in score.measures) {
    for (final voice in [m.elements, m.voice2, m.voice3, m.voice4]) {
      for (final e in voice) {
        if (e.id != null) index[e.id!] = i++;
      }
    }
  }
  final placed = <int, List<(int, int)>>{};
  final levels = <int>[];
  for (final s in score.slurs) {
    final a = index[s.startId];
    final b = index[s.endId];
    if (a == null || b == null) {
      levels.add(0);
      continue;
    }
    final span = a <= b ? (a, b) : (b, a);
    var level = 0;
    while ((placed[level] ?? const [])
        .any((o) => span.$1 < o.$2 && o.$1 < span.$2)) {
      level++;
    }
    (placed[level] ??= []).add(span);
    levels.add(level);
  }
  return levels;
}
