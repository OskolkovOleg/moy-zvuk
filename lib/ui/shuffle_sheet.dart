import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/genre_filter.dart';
import '../data/library_filter.dart';
import '../playback/shuffle_tracks.dart';

class ShuffleSelection {
  ShuffleSelection(
    this.scores,
    Set<GenreGroup> genres, {
    this.limitScores = true,
    this.censoredOnly = false,
    this.scoreFreeze = ScoreFreezeFilter.all,
  }) : genres = Set.unmodifiable(genres);
  final ScoreRange scores;
  final Set<GenreGroup> genres;
  final bool limitScores;
  final bool censoredOnly;
  final ScoreFreezeFilter scoreFreeze;
  LibraryFilter get filter => LibraryFilter(
    minScore: limitScores ? scores.min : null,
    maxScore: limitScores ? scores.max : null,
    genres: genres,
    censoredOnly: censoredOnly,
    scoreFreeze: scoreFreeze,
  );

  String titleFor(String title) => [
    title,
    if (scoreFreeze != ScoreFreezeFilter.all) scoreFreeze.label,
    if (censoredOnly) 'Цензурные',
    if (genres.isNotEmpty) genres.map((g) => g.label).join(', '),
  ].join(' · ');
}

class ShuffleSheet extends StatefulWidget {
  const ShuffleSheet({
    super.key,
    required this.tracks,
    required this.ratings,
    required this.title,
    this.libraryMode = false,
    this.initialFilter = LibraryFilter.all,
  });
  final List<Track> tracks;
  final Map<String, Rating> ratings;
  final String title;
  final bool libraryMode;
  final LibraryFilter initialFilter;
  @override
  State<ShuffleSheet> createState() => _ShuffleSheetState();
}

class _ShuffleSheetState extends State<ShuffleSheet> {
  late final int lowest, highest;
  late final int actualLowest, actualHighest;
  late bool limitScores;
  late bool censoredOnly;
  late ScoreFreezeFilter scoreFreeze;
  late ScoreRange range;
  final selectedGenres = <GenreGroup>{};
  late final Set<GenreGroup> availableGenres;
  @override
  void initState() {
    super.initState();
    final scores = widget.tracks
        .map((t) => trackScore(t.id, widget.ratings))
        .toList();
    actualLowest = scores.isEmpty ? initialTrackScore : scores.reduce(math.min);
    actualHighest = scores.isEmpty
        ? initialTrackScore
        : scores.reduce(math.max);
    final initial = widget.initialFilter;
    censoredOnly = initial.censoredOnly;
    scoreFreeze = initial.scoreFreeze;
    lowest = [
      actualLowest,
      initial.minScore ?? actualLowest,
      initial.maxScore ?? actualLowest,
    ].reduce(math.min);
    highest = [
      actualHighest,
      initial.minScore ?? actualHighest,
      initial.maxScore ?? actualHighest,
    ].reduce(math.max);
    range = ScoreRange(initial.minScore ?? lowest, initial.maxScore ?? highest);
    limitScores = !widget.libraryMode || initial.hasScores;
    selectedGenres.addAll(initial.genres);
    availableGenres = {
      ...widget.tracks.expand(genreGroupsFor),
      ...initial.genres,
    };
  }

  void reset() => setState(() {
    selectedGenres.clear();
    censoredOnly = false;
    scoreFreeze = ScoreFreezeFilter.all;
    range = ScoreRange(actualLowest, actualHighest);
    limitScores = !widget.libraryMode;
  });

  void submit(BuildContext context) => Navigator.pop(
    context,
    ShuffleSelection(
      range,
      selectedGenres,
      limitScores: limitScores,
      censoredOnly: censoredOnly,
      scoreFreeze: scoreFreeze,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filter = LibraryFilter(
      genres: selectedGenres,
      censoredOnly: censoredOnly,
      scoreFreeze: scoreFreeze,
      minScore: limitScores ? range.min : null,
      maxScore: limitScores ? range.max : null,
    );
    final matches = widget.tracks
        .where((t) => filter.matches(t, widget.ratings))
        .length;
    final unknownCount = widget.tracks.where((t) => t.explicit == null).length;
    Widget bound(String title, int value, Key key) => Expanded(
      child: Column(
        crossAxisAlignment: title == 'От'
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Text(title, style: TextStyle(color: scheme.onSurfaceVariant)),
          Text(
            '$value',
            key: key,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ],
      ),
    );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.libraryMode ? 'Фильтры' : 'Перемешать',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (widget.libraryMode)
                        TextButton(
                          key: const Key('reset-filter-draft'),
                          onPressed: reset,
                          child: const Text('Сбросить'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      'Диапазон баллов',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (widget.libraryMode) ...[
                      const SizedBox(height: 8),
                      FilterChip(
                        key: const Key('filter-any-score'),
                        label: const Text('Любые баллы'),
                        selected: !limitScores,
                        onSelected: (_) => setState(() {
                          limitScores = false;
                          range = ScoreRange(actualLowest, actualHighest);
                        }),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        bound('От', range.min, const Key('shuffle-min')),
                        bound('До', range.max, const Key('shuffle-max')),
                      ],
                    ),
                    RangeSlider(
                      key: const Key('shuffle-score-slider'),
                      min: lowest.toDouble(),
                      max: (highest == lowest ? highest + 1 : highest)
                          .toDouble(),
                      divisions: (highest - lowest).clamp(1, 200),
                      values: RangeValues(
                        range.min.toDouble(),
                        range.max.toDouble(),
                      ),
                      labels: RangeLabels('${range.min}', '${range.max}'),
                      onChanged: highest == lowest
                          ? null
                          : (v) => setState(() {
                              limitScores = true;
                              range = ScoreRange(
                                v.start.round(),
                                v.end.round(),
                              );
                            }),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Фиксация баллов',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final value in ScoreFreezeFilter.values)
                          ChoiceChip(
                            key: ValueKey('filter-freeze-${value.name}'),
                            label: Text(value.label),
                            selected: scoreFreeze == value,
                            onSelected: (_) =>
                                setState(() => scoreFreeze = value),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Удержи цифру балла у песни, чтобы зафиксировать или снять фиксацию.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (availableGenres.isNotEmpty || widget.libraryMode) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Жанры',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      if (availableGenres.isEmpty)
                        Text(
                          'Для этого списка нет доступных жанров.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        )
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilterChip(
                              key: const Key('shuffle-genre-all'),
                              label: const Text('Все жанры'),
                              selected: selectedGenres.isEmpty,
                              onSelected: (_) => setState(selectedGenres.clear),
                            ),
                            for (final genre in GenreGroup.values.where(
                              availableGenres.contains,
                            ))
                              FilterChip(
                                key: ValueKey('shuffle-genre-${genre.name}'),
                                label: Text(genre.label),
                                selected: selectedGenres.contains(genre),
                                onSelected: (selected) => setState(() {
                                  if (selected) {
                                    selectedGenres.add(genre);
                                  } else {
                                    selectedGenres.remove(genre);
                                  }
                                }),
                              ),
                          ],
                        ),
                    ],
                    const SizedBox(height: 24),
                    Text(
                      'Содержание',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    FilterChip(
                      key: const Key('filter-censored-only'),
                      label: const Text('Цензурные'),
                      selected: censoredOnly,
                      onSelected: (value) =>
                          setState(() => censoredOnly = value),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Треки без метки E в Звуке.',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (censoredOnly && unknownCount > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Временно скрыто: ${trackCountLabel(unknownCount)} без данных о метке. Обнови библиотеку.',
                        key: const Key('censored-metadata-missing'),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    matches == 0
                        ? selectedGenres.isEmpty &&
                                  !censoredOnly &&
                                  scoreFreeze == ScoreFreezeFilter.all
                              ? 'В этом диапазоне нет песен'
                              : 'Нет песен с такими параметрами'
                        : 'Подходит ${trackCountLabel(matches)}',
                    key: const Key('shuffle-matches'),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  if (widget.libraryMode)
                    FilledButton(
                      key: const Key('apply-library-filter'),
                      onPressed: () => submit(context),
                      child: const Text('Показать'),
                    )
                  else
                    FilledButton.icon(
                      key: const Key('start-shuffle'),
                      onPressed: matches == 0 ? null : () => submit(context),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Слушать'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
