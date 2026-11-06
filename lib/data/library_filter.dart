import 'genre_filter.dart';
import 'models.dart';

class LibraryFilter {
  factory LibraryFilter({
    int? minScore,
    int? maxScore,
    Set<GenreGroup> genres = const {},
    bool censoredOnly = false,
  }) {
    if (minScore != null && maxScore != null && minScore > maxScore) {
      throw ArgumentError('Начало диапазона больше конца');
    }
    return LibraryFilter._(
      minScore,
      maxScore,
      Set.unmodifiable(genres),
      censoredOnly,
    );
  }
  const LibraryFilter._(
    this.minScore,
    this.maxScore,
    this.genres,
    this.censoredOnly,
  );
  static const all = LibraryFilter._(null, null, {}, false);
  final int? minScore, maxScore;
  final Set<GenreGroup> genres;
  final bool censoredOnly;
  bool get hasScores => minScore != null || maxScore != null;
  bool get isActive => hasScores || genres.isNotEmpty || censoredOnly;

  bool matches(Track track, Map<String, Rating> ratings) {
    final score = trackScore(track.id, ratings);
    return (minScore == null || score >= minScore!) &&
        (maxScore == null || score <= maxScore!) &&
        (genres.isEmpty || genreGroupsFor(track).any(genres.contains)) &&
        (!censoredOnly || track.explicit == false);
  }

  String get label => [
    if (censoredOnly) 'Цензурные',
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
      censoredOnly == other.censoredOnly &&
      genres.length == other.genres.length &&
      genres.containsAll(other.genres);
  @override
  int get hashCode => Object.hash(
    minScore,
    maxScore,
    censoredOnly,
    Object.hashAll(GenreGroup.values.where(genres.contains)),
  );
}
