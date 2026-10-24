import 'genre_metadata.dart';

export 'genre_metadata.dart';

class Track {
  const Track({
    required this.id,
    required this.title,
    this.artists = '',
    this.duration = 0,
    this.imageUrl,
    this.artistIds = const [],
    this.artistNames = const [],
    this.releaseId,
    this.genres = const [],
    this.genreSource,
  });
  final String id, title, artists;
  final int duration;
  final String? imageUrl, releaseId;
  final List<String> artistIds;
  final List<String> artistNames;
  final List<TrackGenre> genres;
  final GenreSource? genreSource;

  factory Track.fromApi(Map<String, dynamic> json) {
    final ownGenres = TrackGenre.listFromJson(json['genres']);
    final releaseGenres = TrackGenre.listFromJson(json['release']?['genres']);
    final genres = ownGenres.isNotEmpty ? ownGenres : releaseGenres;
    return Track(
      id: json['id'].toString(),
      title: json['title'] as String? ?? 'Недоступный трек',
      artists: (json['artists'] as List? ?? [])
          .map((a) => a['title'] ?? '')
          .join(', '),
      duration: (json['duration'] as num? ?? 0).toInt(),
      imageUrl: artwork(json['release']?['image']?['src']),
      releaseId: json['release']?['id']?.toString(),
      artistIds: (json['artists'] as List? ?? [])
          .where((a) => a['id'] != null)
          .map((a) => a['id'].toString())
          .toList(),
      artistNames: (json['artists'] as List? ?? [])
          .where((a) => a['id'] != null)
          .map((a) => a['title']?.toString() ?? 'Артист')
          .toList(),
      genres: genres,
      genreSource: genres.isEmpty
          ? null
          : ownGenres.isNotEmpty
          ? GenreSource.track
          : GenreSource.release,
    );
  }

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: json['title'] as String,
    artists: json['artists'] as String? ?? '',
    duration: json['duration'] as int? ?? 0,
    imageUrl: json['imageUrl'] as String?,
    releaseId: json['releaseId'] as String?,
    artistIds: (json['artistIds'] as List? ?? []).cast<String>(),
    artistNames: (json['artistNames'] as List? ?? []).cast<String>(),
    genres: TrackGenre.listFromJson(json['genres']),
    genreSource: GenreSource.values
        .where((source) => source.name == json['genreSource'])
        .firstOrNull,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'duration': duration,
    'imageUrl': imageUrl,
    'releaseId': releaseId,
    'artistIds': artistIds,
    'artistNames': artistNames,
    'genres': genres.map((g) => g.toJson()).toList(),
    'genreSource': genreSource?.name,
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

String trackCountLabel(int count) {
  final lastTwo = count % 100, last = count % 10;
  final word = lastTwo >= 11 && lastTwo <= 14
      ? 'треков'
      : last == 1
      ? 'трек'
      : last >= 2 && last <= 4
      ? 'трека'
      : 'треков';
  return '$count $word';
}

class Account {
  const Account(this.id, this.name);
  final String id, name;
  Map<String, dynamic> toJson() => {'id': id, 'name': name};
  factory Account.fromJson(Map<String, dynamic> j) =>
      Account(j['id'] as String, j['name'] as String);
}

class PlaylistInfo {
  const PlaylistInfo(
    this.id,
    this.title, {
    this.ownerId,
    this.imageUrl,
    this.isPublic = false,
    this.trackCount = 0,
    this.description = '',
  });
  final String id, title, description;
  final String? ownerId, imageUrl;
  final bool isPublic;
  final int trackCount;
  factory PlaylistInfo.fromJson(Map<String, dynamic> j) => PlaylistInfo(
    j['id'].toString(),
    j['title'] as String? ?? 'Плейлист',
    ownerId: (j['ownerId'] ?? j['userId'])?.toString(),
    imageUrl: j['imageUrl'] as String? ?? artwork(j['image']?['src']),
    isPublic: j['isPublic'] == true,
    trackCount: j['trackCount'] as int? ?? (j['tracks'] as List? ?? []).length,
    description: j['description'] as String? ?? '',
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'ownerId': ownerId,
    'imageUrl': imageUrl,
    'isPublic': isPublic,
    'trackCount': trackCount,
    'description': description,
  };
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
const initialTrackScore = 9;

int trackScore(String id, Map<String, Rating> ratings) =>
    ratings[id]?.score ?? initialTrackScore;

class RatingPosition {
  const RatingPosition(this.start, this.end, this.total);
  final int start, end, total;

  String get label => start == end ? '$start' : '$start–$end';
}

RatingPosition? ratingPosition(
  List<Track> tracks,
  Map<String, Rating> ratings,
  String trackId,
) {
  if (!tracks.any((track) => track.id == trackId)) return null;
  final score = trackScore(trackId, ratings);
  var higher = 0, equal = 0;
  for (final track in tracks) {
    final other = trackScore(track.id, ratings);
    if (other > score) higher++;
    if (other == score) equal++;
  }
  return RatingPosition(higher + 1, higher + equal, tracks.length);
}

List<Track> rankedTracks(List<Track> tracks, Map<String, Rating> ratings) {
  final indexed = tracks.asMap().entries.toList();
  indexed.sort((a, b) {
    final score = trackScore(
      b.value.id,
      ratings,
    ).compareTo(trackScore(a.value.id, ratings));
    return score != 0 ? score : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}
