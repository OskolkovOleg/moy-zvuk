import 'genre_filter.dart';
import 'models.dart';

enum ScoreFreezeFilter {
  all,
  unfrozen,
  frozen;

  String get label => switch (this) {
    all => 'Все',
    unfrozen => 'Не зафиксированы',
    frozen => 'Зафиксированы',
  };
}

class LibraryFilter {
  factory LibraryFilter({
    int? minScore,
    int? maxScore,
    Set<GenreGroup> genres = const {},
    bool censoredOnly = false,
    ScoreFreezeFilter scoreFreeze = ScoreFreezeFilter.all,
  }) {
    if (minScore != null && maxScore != null && minScore > maxScore) {
      throw ArgumentError('Начало диапазона больше конца');
    }
    return LibraryFilter._(
      minScore,
      maxScore,
      Set.unmodifiable(genres),
      censoredOnly,
      scoreFreeze,
    );
  }
  const LibraryFilter._(
    this.minScore,
    this.maxScore,
    this.genres,
    this.censoredOnly,
    this.scoreFreeze,
  );
  static const all = LibraryFilter._(
    null,
    null,
    {},
    false,
    ScoreFreezeFilter.all,
  );
  final int? minScore, maxScore;
  final Set<GenreGroup> genres;
  final bool censoredOnly;
  final ScoreFreezeFilter scoreFreeze;
  bool get hasScores => minScore != null || maxScore != null;
  bool get isActive =>
      hasScores ||
      genres.isNotEmpty ||
      censoredOnly ||
      scoreFreeze != ScoreFreezeFilter.all;

  bool matchesFreeze(Track track, Map<String, Rating> ratings) {
    final frozen = ratings[track.id]?.frozen ?? false;
    return switch (scoreFreeze) {
      ScoreFreezeFilter.all => true,
      ScoreFreezeFilter.unfrozen => !frozen,
      ScoreFreezeFilter.frozen => frozen,
    };
  }

  bool matches(Track track, Map<String, Rating> ratings) =>
      matchesConditions(track, ratings) && matchesFreeze(track, ratings);

  bool matchesConditions(Track track, Map<String, Rating> ratings) {
    final score = trackScore(track.id, ratings);
    return (minScore == null || score >= minScore!) &&
        (maxScore == null || score <= maxScore!) &&
        (genres.isEmpty || genreGroupsFor(track).any(genres.contains)) &&
        (!censoredOnly || track.explicit == false);
  }

  String get label => [
    if (scoreFreeze != ScoreFreezeFilter.all) scoreFreeze.label,
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
      scoreFreeze == other.scoreFreeze &&
      genres.length == other.genres.length &&
      genres.containsAll(other.genres);
  @override
  int get hashCode => Object.hash(
    minScore,
    maxScore,
    censoredOnly,
    scoreFreeze,
    Object.hashAll(GenreGroup.values.where(genres.contains)),
  );
}
