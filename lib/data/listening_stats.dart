import 'models.dart';

enum LibrarySort { scores, oldest, leastPlayed }

extension LibrarySortLabel on LibrarySort {
  String get label => switch (this) {
    LibrarySort.scores => 'По баллам',
    LibrarySort.oldest => 'Давно не слушал',
    LibrarySort.leastPlayed => 'Реже за 7 дней',
  };
}

class ListeningStart {
  const ListeningStart(this.id, this.track, this.at);
  final String id, track;
  final DateTime at;
  Map<String, dynamic> toJson() => {
    'id': id,
    'track': track,
    'at': at.toUtc().toIso8601String(),
  };
}

class ListeningStats {
  ListeningStats(
    this.since, {
    Map<String, DateTime>? last,
    List<ListeningStart>? starts,
  }) : last = last ?? {},
       starts = starts ?? [];
  final DateTime since;
  final Map<String, DateTime> last;
  final List<ListeningStart> starts;
  int weeklyCount(String id, DateTime now) => starts
      .where(
        (e) =>
            e.track == id &&
            e.at.isAfter(now.subtract(const Duration(days: 7))) &&
            !e.at.isAfter(now),
      )
      .length;
  bool fullWeek(DateTime now) =>
      !since.isAfter(now.subtract(const Duration(days: 7)));
  factory ListeningStats.fromJson(dynamic json, DateTime now) {
    if (json is! Map) return ListeningStats(now);
    final last = <String, DateTime>{};
    if (json['last'] case final Map values) {
      for (final e in values.entries) {
        final at = DateTime.tryParse(e.value.toString());
        if (at != null) last[e.key.toString()] = at;
      }
    }
    return ListeningStats(
      DateTime.tryParse(json['since']?.toString() ?? '') ?? now,
      last: last,
      starts: [
        for (final row in (json['starts'] as List? ?? []).whereType<Map>())
          if (row['id'] is String && row['track'] is String)
            if (DateTime.tryParse(row['at']?.toString() ?? '') case final at?)
              ListeningStart(row['id'] as String, row['track'] as String, at),
      ],
    );
  }
  Map<String, dynamic> toJson() => {
    'since': since.toUtc().toIso8601String(),
    'last': last.map((id, at) => MapEntry(id, at.toUtc().toIso8601String())),
    'starts': starts.map((e) => e.toJson()).toList(),
  };
}

List<Track> sortedLibraryTracks(
  List<Track> tracks,
  Map<String, Rating> ratings, {
  LibrarySort sort = LibrarySort.scores,
  ListeningStats? stats,
  DateTime? now,
}) {
  final ranked = rankedTracks(tracks, ratings);
  if (sort == LibrarySort.scores || stats == null) return ranked;
  final time = now ?? DateTime.now();
  final counts = <String, int>{};
  for (final start in stats.starts) {
    if (start.at.isAfter(time.subtract(const Duration(days: 7))) &&
        !start.at.isAfter(time)) {
      counts[start.track] = (counts[start.track] ?? 0) + 1;
    }
  }
  final indexed = ranked.asMap().entries.toList();
  indexed.sort((a, b) {
    if (sort == LibrarySort.leastPlayed) {
      final count = (counts[a.value.id] ?? 0).compareTo(
        counts[b.value.id] ?? 0,
      );
      if (count != 0) return count;
    }
    final aDate = stats.last[a.value.id], bDate = stats.last[b.value.id];
    // Missing dates remain unknown and follow dated songs; they are never
    // represented as ancient dates or as evidence of never having listened.
    if (aDate == null && bDate != null) return 1;
    if (aDate != null && bDate == null) return -1;
    final date = aDate == null ? 0 : aDate.compareTo(bDate!);
    return date != 0 ? date : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}
