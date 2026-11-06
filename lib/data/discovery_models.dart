import 'catalog_models.dart';
import 'models.dart';

enum DiscoveryMode { best, song, releases, explore }

extension DiscoveryModeLabel on DiscoveryMode {
  String get label => switch (this) {
    DiscoveryMode.best => 'По моим лучшим',
    DiscoveryMode.song => 'Похоже на песню',
    DiscoveryMode.releases => 'Свежие релизы',
    DiscoveryMode.explore => 'Расширить вкус',
  };
  String get description => switch (this) {
    DiscoveryMode.best => 'Новое рядом с песнями, которые ты ценишь',
    DiscoveryMode.song => 'Продолжить настроение одного трека',
    DiscoveryMode.releases => 'Новые работы знакомых артистов',
    DiscoveryMode.explore => 'Хиты разных направлений за пределами привычного',
  };
}

class DiscoveryDirection {
  const DiscoveryDirection(this.id, this.label, this.playlistIds);
  final String id, label;
  final List<String> playlistIds;
}

// Verified against Zvuk playlist metadata on 2026-11-06. These describe the
// source playlists, not inferred genre labels for their individual recordings.
const discoveryDirections = [
  DiscoveryDirection('club', 'Клубная', ['8404268']),
  DiscoveryDirection('electronic', 'Электроника', ['7037269']),
  DiscoveryDirection('rock', 'Рок', ['8203400']),
  DiscoveryDirection('hiphop', 'Хип-хоп', ['5446828']),
  DiscoveryDirection('pop', 'Поп', ['8404344', '6477976']),
  DiscoveryDirection('indie', 'Инди', ['15607236']),
];

class DiscoveryCandidate {
  const DiscoveryCandidate(this.track, this.reason, {this.source});
  final Track track;
  final String reason;
  final CatalogItem? source;
}

class ArtistRelease {
  const ArtistRelease(this.album, this.date, this.tracks);
  final CatalogItem album;
  final DateTime? date;
  final List<Track> tracks;
}

Set<String> discoveryIdentity(Track track) => {
  track.id,
  if (track.canonicalTrackId case final id? when id.isNotEmpty) id,
};

bool isRecentRelease(DateTime? date, DateTime now) =>
    date != null &&
    !date.isAfter(now) &&
    !date.isBefore(now.subtract(const Duration(days: 90)));

List<Track> discoverySeeds(
  List<Track> library,
  Map<String, Rating> ratings, {
  int offset = 0,
  int limit = 5,
}) {
  final ranked = rankedTracks(library, ratings)
      .where((t) => trackScore(t.id, ratings) >= initialTrackScore)
      .take(60)
      .toList();
  final artists = <String>{};
  final unique = ranked
      .where((t) => artists.add(t.artistIds.firstOrNull ?? 'track:${t.id}'))
      .toList();
  if (unique.isEmpty) return [];
  final start = offset % unique.length;
  return [...unique.skip(start), ...unique.take(start)].take(limit).toList();
}

List<DiscoveryCandidate> selectDiscoveries(
  List<List<DiscoveryCandidate>> pools, {
  List<Track> library = const [],
  Set<String> excluded = const {},
  bool censoredOnly = false,
  int limit = 20,
  int artistLimit = 3,
}) {
  final seen = {...excluded, ...library.expand(discoveryIdentity)};
  final artists = <String, int>{}, positions = List.filled(pools.length, 0);
  final result = <DiscoveryCandidate>[];
  var moved = true;
  while (result.length < limit && moved) {
    moved = false;
    for (var pool = 0; pool < pools.length && result.length < limit; pool++) {
      while (positions[pool] < pools[pool].length) {
        moved = true;
        final candidate = pools[pool][positions[pool]++], t = candidate.track;
        final keys = discoveryIdentity(t);
        if (keys.any(seen.contains) || (censoredOnly && t.explicit != false)) {
          continue;
        }
        if (t.artistIds.any((id) => (artists[id] ?? 0) >= artistLimit)) {
          continue;
        }
        seen.addAll(keys);
        for (final id in t.artistIds) {
          artists[id] = (artists[id] ?? 0) + 1;
        }
        result.add(candidate);
        break;
      }
    }
  }
  return result;
}
