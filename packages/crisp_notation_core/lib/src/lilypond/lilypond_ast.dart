/// The parse tree produced by the LilyPond lexer/parser and consumed by the
/// importer. A deliberately small, untyped-value AST: it captures LilyPond's
/// block / command / music structure verbatim (pitches and durations stay as
/// their source strings) and leaves interpretation to the importer.
library;

/// Base type for every node in a parsed LilyPond tree.
abstract class LyNode {
  /// Const base constructor (nodes are immutable).
  const LyNode();
}

/// A brace-delimited group `{ … }` — a sequential run of music/commands.
class LyBlock extends LyNode {
  /// The nodes inside the braces, in source order.
  final List<LyNode> children;

  /// Wraps the [children] of a `{ … }` block.
  const LyBlock(this.children);
}

/// A simultaneous group `<< … >>` — its [children] sound together (e.g. staves
/// or voices played at once).
class LySimultaneous extends LyNode {
  /// The nodes inside the `<< … >>`, in source order.
  final List<LyNode> children;

  /// Wraps the [children] of a `<< … >>` group.
  const LySimultaneous(this.children);
}

/// A backslash command such as `\key`, `\relative`, `\time` or `\new`, with its
/// following arguments.
class LyCommand extends LyNode {
  /// The command name without the leading backslash (e.g. `key`, `relative`).
  final String name;

  /// The argument nodes that follow the command, in source order.
  final List<LyNode> args;

  /// Builds a command [name] with its [args].
  const LyCommand(this.name, this.args);
}

/// A variable assignment `key = value` (e.g. `melody = { … }`).
class LyAssignment extends LyNode {
  /// The identifier on the left of the `=`.
  final String key;

  /// The node assigned to [key].
  final LyNode value;

  /// Builds an assignment of [value] to [key].
  const LyAssignment(this.key, this.value);
}

/// A single note token, its pitch and duration kept as their source strings so
/// the importer can resolve them against the current key/octave state.
class LyNote extends LyNode {
  /// The pitch text, e.g. `c'` or `fis,`.
  final String pitch; // e.g. c'

  /// The duration text, e.g. `4.`, or null to inherit the previous duration.
  final String? duration; // e.g. 4.

  /// Attached scripts/articulations, e.g. `-.`, `->`, `(`, `)`, `~`.
  final List<String> scripts; // e.g. -., ->, (, ), ~

  /// Builds a note from its [pitch], optional [duration] and [scripts].
  const LyNote(this.pitch, this.duration, this.scripts);
}

/// A rest token (`r`), its duration kept as its source string.
class LyRest extends LyNode {
  /// The duration text, or null to inherit the previous duration.
  final String? duration;

  /// Builds a rest of the given [duration].
  const LyRest(this.duration);
}

/// A chord token `< … >`, its member [pitches] and shared [duration] kept as
/// source strings.
class LyChord extends LyNode {
  /// The chord's pitch texts, in source order.
  final List<String> pitches;

  /// The chord's duration text, or null to inherit the previous duration.
  final String? duration;

  /// Attached scripts/articulations shared by the chord.
  final List<String> scripts;

  /// Builds a chord from its [pitches], optional [duration] and [scripts].
  const LyChord(this.pitches, this.duration, this.scripts);
}

/// A double-quoted string literal (its [value] already unquoted).
class LyString extends LyNode {
  /// The literal text without the surrounding quotes.
  final String value;

  /// Wraps a string literal [value].
  const LyString(this.value);
}

/// A bare word / identifier token (e.g. a mode name or unquoted argument).
class LyWord extends LyNode {
  /// The word's text.
  final String value;

  /// Wraps a bare word [value].
  const LyWord(this.value);
}

/// A `\score { … }` block — the [contents] engraved as one score.
class LyScore extends LyNode {
  /// The nodes inside the `\score` block, in source order.
  final List<LyNode> contents;

  /// Wraps the [contents] of a `\score` block.
  const LyScore(this.contents);
}
