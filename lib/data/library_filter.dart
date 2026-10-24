import 'genre_filter.dart';
import 'models.dart';

class LibraryFilter {
  factory LibraryFilter({
    int? minScore,
    int? maxScore,
    Set<GenreGroup> genres = const {},
  }) {
    if (minScore != null && maxScore != null && minScore > maxScore) {
      throw ArgumentError('Начало диапазона больше конца');
    }
    return LibraryFilter._(minScore, maxScore, Set.unmodifiable(genres));
  }
  const LibraryFilter._(this.minScore, this.maxScore, this.genres);
  static const all = LibraryFilter._(null, null, {});
  final int? minScore, maxScore;
  final Set<GenreGroup> genres;
  bool get hasScores => minScore != null || maxScore != null;
  bool get isActive => hasScores || genres.isNotEmpty;

  bool matches(Track track, Map<String, Rating> ratings) {
    final score = trackScore(track.id, ratings);
    return (minScore == null || score >= minScore!) &&
        (maxScore == null || score <= maxScore!) &&
        (genres.isEmpty || genreGroupsFor(track).any(genres.contains));
  }

  String get label => [
    if (genres.isNotEmpty)
      GenreGroup.values.where(genres.contains).map((g) => g.label).join(', '),
    if (minScore != null && maxScore != null)
      '$minScore–$maxScore баллов'
    else if (minScore != null)
      'От $minScore баллов'
    else if (maxScore != null)
      'До $maxScore баллов',
  ].join(' · ');

  @override
  bool operator ==(Object other) =>
      other is LibraryFilter &&
      minScore == other.minScore &&
      maxScore == other.maxScore &&
      genres.length == other.genres.length &&
      genres.containsAll(other.genres);
  @override
  int get hashCode => Object.hash(
    minScore,
    maxScore,
    Object.hashAll(GenreGroup.values.where(genres.contains)),
  );
}
