/// The printed heading of a score — title, subtitle, credits — and its
/// copyright footer, placed once and drawn by every page renderer (SVG, PDF)
/// so they agree.
library;

import '../model/score.dart';

/// Where a [TitleLine] hangs from its x.
enum TitleAnchor {
  /// Text starts at x.
  start,

  /// Text is centred on x.
  middle,

  /// Text ends at x.
  end,
}

/// One line of the title block or footer: [y] is its baseline, in staff
/// spaces from the block's top; [size] is the em size in staff spaces.
class TitleLine {
  /// The line's text.
  final String text;

  /// Anchor x, baseline y and em size, in staff spaces.
  final double x, y, size;

  /// How the line hangs from [x].
  final TitleAnchor anchor;

  /// CSS-style weight: 400 regular, 500 medium, 600 the title.
  final int weight;

  /// Creates a line.
  const TitleLine(this.text, this.x, this.y, this.size,
      {this.anchor = TitleAnchor.middle, this.weight = 400});
}

/// The title block between [left] and [right] (staff spaces): title,
/// subtitle, then the lyricist on the left and the composer (and arranger)
/// on the right, as a printed song heads its first page. [height] is 0 when
/// there is nothing to show.
({List<TitleLine> lines, double height}) titleBlockOf(ScoreMetadata metadata,
    {required double left, required double right}) {
  final titleLines = metadataLines(metadata.title);
  final subtitleLines = metadataLines(metadata.subtitle);
  final composerLines = metadataLines(metadata.composer);
  final arrangerLines = metadataLines(metadata.arranger);
  final lyricistLines = metadataLines(metadata.lyricist);
  final lines = <TitleLine>[];
  if (titleLines.isEmpty &&
      subtitleLines.isEmpty &&
      composerLines.isEmpty &&
      lyricistLines.isEmpty &&
      arrangerLines.isEmpty) {
    return (lines: lines, height: 0);
  }
  final centerX = (left + right) / 2;
  var y = 1.8;
  for (var i = 0; i < titleLines.length; i++) {
    lines.add(TitleLine(titleLines[i], centerX, y, i == 0 ? 1.55 : 1.05,
        weight: i == 0 ? 600 : 400));
    y += i == 0 ? 1.45 : 1.25;
  }
  for (final line in subtitleLines) {
    lines.add(TitleLine(line, centerX, y, 1.15, weight: 500));
    y += 1.35;
  }
  // The credits row: words on the left, music on the right.
  final credits = [...composerLines, ...arrangerLines];
  if (lyricistLines.isNotEmpty || credits.isNotEmpty) {
    y += 0.35;
    final rows = lyricistLines.length > credits.length
        ? lyricistLines.length
        : credits.length;
    for (var i = 0; i < rows; i++) {
      if (i < lyricistLines.length) {
        lines.add(TitleLine(lyricistLines[i], left, y, 0.9,
            anchor: TitleAnchor.start));
      }
      if (i < credits.length) {
        final arranger = i >= composerLines.length;
        lines.add(TitleLine(credits[i], right, y, arranger ? 0.8 : 0.9,
            anchor: TitleAnchor.end));
      }
      y += 1.05;
    }
  }
  return (lines: lines, height: y + 1.4);
}

/// The copyright lines, centred on [centerX], from a block top at 0.
({List<TitleLine> lines, double height}) footerOf(ScoreMetadata metadata,
    {required double centerX}) {
  final lines = <TitleLine>[];
  var y = 1.4;
  for (final line in metadataLines(metadata.copyright)) {
    lines.add(TitleLine(line, centerX, y, 0.75));
    y += 0.95;
  }
  return (lines: lines, height: lines.isEmpty ? 0 : y);
}

/// [text]'s non-blank lines, trimmed.
List<String> metadataLines(String? text) => (text ?? '')
    .split('\n')
    .map((line) => line.trim())
    .where((line) => line.isNotEmpty)
    .toList();

/// Height in staff spaces of [metadata]'s title block (0 without one) — what
/// to reserve as `firstPageTop` when paginating a score that prints it.
double titleBlockHeight(ScoreMetadata metadata) =>
    titleBlockOf(metadata, left: 0, right: 0).height;
