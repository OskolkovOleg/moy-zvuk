class Track {
  const Track({
    required this.id,
    required this.title,
    this.artists = '',
    this.duration = 0,
    this.imageUrl,
  });
  final String id, title, artists;
  final int duration;
  final String? imageUrl;

  factory Track.fromApi(Map<String, dynamic> json) => Track(
    id: json['id'].toString(),
    title: json['title'] as String? ?? 'Недоступный трек',
    artists: (json['artists'] as List? ?? [])
        .map((a) => a['title'] ?? '')
        .join(', '),
    duration: (json['duration'] as num? ?? 0).toInt(),
    imageUrl: artwork(json['release']?['image']?['src']),
  );
  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String,
    artists: json['artists'] as String? ?? '',
    duration: json['duration'] as int? ?? 0,
    imageUrl: json['imageUrl'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'duration': duration,
    'imageUrl': imageUrl,
  };
}

String? artwork(dynamic value) {
  if (value is! String || value.isEmpty) return null;
  final uri = Uri.tryParse(
    value.startsWith('/') ? 'https://zvuk.com$value' : value,
  );
  if (uri == null || uri.scheme != 'https') return null;
  return uri
      .replace(queryParameters: {...uri.queryParameters, 'size': '600x600'})
      .toString();
}

class Account {
  const Account(this.id, this.name);
  final String id, name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Account.fromJson(Map<String, dynamic> j) =>
      Account(j['id'] as String, j['name'] as String);
}

class PlaylistInfo {
  const PlaylistInfo(this.id, this.title);
  final String id, title;
  factory PlaylistInfo.fromJson(Map<String, dynamic> j) =>
      PlaylistInfo(j['id'].toString(), j['title'] as String? ?? 'Плейлист');
  Map<String, dynamic> toJson() => {'id': id, 'title': title};
}

class SearchPage {
  const SearchPage(this.tracks, this.next);
  final List<Track> tracks;
  final String? next;
}

class Rating {
  const Rating(this.score, this.count);
  final int score, count;
}

// A fixed baseline, not a vote: reopening or importing must never add it again.
const initialTrackScore = 10;

int trackScore(String id, Map<String, Rating> ratings) =>
    ratings[id]?.score ?? initialTrackScore;

class RatingPosition {
  const RatingPosition(this.position, this.total);
  final int position, total;
}

RatingPosition? ratingPosition(
  List<Track> tracks,
  Map<String, Rating> ratings,
  String trackId,
) {
  final sorted = rankedTracks(tracks, ratings);
  final index = sorted.indexWhere((track) => track.id == trackId);
  return index < 0 ? null : RatingPosition(index + 1, sorted.length);
}

/// Keep saved positions, drop missing entries and append new songs in source
/// order. Consume each occurrence once: playlists may contain duplicates.
List<Track> manuallyOrderedTracks(List<Track> source, List<String> order) {
  final byId = <String, List<Track>>{};
  for (final track in source) {
    byId.putIfAbsent(track.id, () => []).add(track);
  }
  final used = <String, int>{};
  final result = <Track>[];
  for (final id in order) {
    final index = used[id] ?? 0;
    final copies = byId[id];
    if (copies != null && index < copies.length) {
      result.add(copies[index]);
      used[id] = index + 1;
    }
  }
  final seen = <String, int>{};
  for (final track in source) {
    final occurrence = seen.update(track.id, (n) => n + 1, ifAbsent: () => 1);
    if (occurrence > (used[track.id] ?? 0)) result.add(track);
  }
  return result;
}

List<Track> rankedTracks(
  List<Track> tracks,
  Map<String, Rating> ratings, {
  bool ranked = true,
  bool unrated = false,
}) {
  final indexed = tracks
      .asMap()
      .entries
      .where((e) => !unrated || (ratings[e.value.id]?.count ?? 0) == 0)
      .toList();
  if (ranked) {
    indexed.sort((a, b) {
      final score = trackScore(
        b.value.id,
        ratings,
      ).compareTo(trackScore(a.value.id, ratings));
      return score != 0 ? score : a.key.compareTo(b.key);
    });
  }
  return indexed.map((e) => e.value).toList();
}
