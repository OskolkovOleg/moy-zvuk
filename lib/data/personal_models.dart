import 'models.dart';

class ListeningEntry {
  const ListeningEntry(this.track, this.at);
  final Track track;
  final DateTime at;
  Map<String, dynamic> toJson() => {
    'track': track.toJson(),
    'at': at.toUtc().toIso8601String(),
  };
  factory ListeningEntry.fromJson(Map<String, dynamic> j) =>
      ListeningEntry(Track.fromJson(j['track']), DateTime.parse(j['at']));
}

class HistoryPage {
  const HistoryPage(this.entries, this.nextOffset);
  final List<ListeningEntry> entries;
  final int? nextOffset;
}

List<ListeningEntry> recentUnique(
  Iterable<ListeningEntry> entries, {
  int limit = 200,
}) {
  final ordered = entries.toList()..sort((a, b) => b.at.compareTo(a.at));
  final seen = <String>{};
  return ordered.where((e) => seen.add(e.track.id)).take(limit).toList();
}

class LyricsLine {
  const LyricsLine(this.text, [this.at]);
  final String text;
  final Duration? at;
}

class SongLyrics {
  const SongLyrics(this.lines, {this.translation});
  final List<LyricsLine> lines;
  final String? translation;
  bool get synced => lines.isNotEmpty && lines.every((l) => l.at != null);
  int activeLine(Duration position) {
    if (!synced) return -1;
    var low = 0, high = lines.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (lines[middle].at! <= position) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low - 1;
  }

  static SongLyrics parse(String source, {String? translation}) {
    final timestamp = RegExp(r'\[(\d+):(\d{2})(?:[.:](\d{1,3}))?\]');
    final offsetMatch = RegExp(
      r'\[offset:([+-]?\d+)\]',
      caseSensitive: false,
    ).firstMatch(source);
    final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
    final timed = <LyricsLine>[], plain = <LyricsLine>[];
    for (final row in source.split(RegExp(r'\r?\n'))) {
      final tags = timestamp.allMatches(row).toList();
      if (tags.isEmpty) {
        if (!RegExp(
          r'^\s*\[[a-z]+:.*\]\s*$',
          caseSensitive: false,
        ).hasMatch(row)) {
          plain.add(LyricsLine(row.trimRight()));
        }
        continue;
      }
      final text = row.replaceAll(timestamp, '').trim();
      for (final tag in tags) {
        final seconds = int.parse(tag.group(2)!);
        if (seconds >= 60) continue;
        final fraction = (tag.group(3) ?? '').padRight(3, '0');
        final ms =
            int.parse(tag.group(1)!) * 60000 +
            seconds * 1000 +
            int.parse(fraction) +
            offset;
        timed.add(LyricsLine(text, Duration(milliseconds: ms < 0 ? 0 : ms)));
      }
    }
    timed.sort((a, b) => a.at!.compareTo(b.at!));
    while (plain.isNotEmpty && plain.first.text.isEmpty) {
      plain.removeAt(0);
    }
    while (plain.isNotEmpty && plain.last.text.isEmpty) {
      plain.removeLast();
    }
    return SongLyrics(timed.isEmpty ? plain : timed, translation: translation);
  }
}
