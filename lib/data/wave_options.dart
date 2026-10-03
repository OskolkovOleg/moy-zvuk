enum WaveMood { any, energetic, happy, calm, sad }

enum WaveLanguage { any, russian, foreign }

enum WavePopularity { any, hits, discoveries }

const waveGenres = <String, String>{
  'pop': 'Поп',
  'rock': 'Рок',
  'hip_hop': 'Хип-хоп',
  'electronic': 'Электроника',
  'indie': 'Инди',
  'metal': 'Метал',
  'folk_world_country': 'Фолк',
  'classical': 'Классика',
  'ambient': 'Эмбиент',
  'instrumental_acoustic': 'Инструментальная',
  'soundtrack': 'Саундтреки',
};

extension WaveMoodLabel on WaveMood {
  String get label => switch (this) {
    WaveMood.any => 'Любое',
    WaveMood.energetic => 'Энергичное',
    WaveMood.happy => 'Радостное',
    WaveMood.calm => 'Спокойное',
    WaveMood.sad => 'Грустное',
  };
}

extension WaveLanguageLabel on WaveLanguage {
  String get label => switch (this) {
    WaveLanguage.any => 'Любой',
    WaveLanguage.russian => 'На русском',
    WaveLanguage.foreign => 'Зарубежное',
  };
}

extension WavePopularityLabel on WavePopularity {
  String get label => switch (this) {
    WavePopularity.any => 'Всё вместе',
    WavePopularity.hits => 'Хиты',
    WavePopularity.discoveries => 'Новые открытия',
  };
}

class WaveOptions {
  const WaveOptions({
    this.mood = WaveMood.any,
    this.language = WaveLanguage.any,
    this.popularity = WavePopularity.any,
    this.genres = const [],
  });
  final WaveMood mood;
  final WaveLanguage language;
  final WavePopularity popularity;
  final List<String> genres;

  bool get isDefault =>
      mood == WaveMood.any &&
      language == WaveLanguage.any &&
      popularity == WavePopularity.any &&
      genres.isEmpty;

  String get summary => isDefault
      ? 'По твоему вкусу'
      : [
          if (mood != WaveMood.any) mood.label,
          ...genres.map((g) => waveGenres[g]!).take(2),
          if (genres.length > 2) '+${genres.length - 2} жанра',
          if (language != WaveLanguage.any) language.label,
          if (popularity != WavePopularity.any) popularity.label,
        ].join(' · ');

  Map<String, dynamic> toApi() => {
    if (mood != WaveMood.any)
      'mood': switch (mood) {
        WaveMood.energetic => 'energy:1,fun:0.5',
        WaveMood.happy => 'energy:0.5,fun:1',
        WaveMood.calm => 'energy:0,fun:0.5',
        WaveMood.sad => 'energy:0.5,fun:0',
        _ => throw StateError('Default mood has no filter'),
      },
    if (language != WaveLanguage.any) 'language': language.name,
    if (popularity != WavePopularity.any)
      'popular': popularity == WavePopularity.hits ? 1 : 0,
    if (genres.isNotEmpty) 'genre': genres.map((g) => {'name': g}).toList(),
  };

  Map<String, dynamic> toJson() => {
    'mood': mood.name,
    'language': language.name,
    'popularity': popularity.name,
    'genres': genres,
  };

  factory WaveOptions.fromJson(dynamic j) {
    if (j is! Map) return const WaveOptions();
    return WaveOptions(
      mood:
          WaveMood.values.where((v) => v.name == j['mood']).firstOrNull ??
          WaveMood.any,
      language:
          WaveLanguage.values
              .where((v) => v.name == j['language'])
              .firstOrNull ??
          WaveLanguage.any,
      popularity:
          WavePopularity.values
              .where((v) => v.name == j['popularity'])
              .firstOrNull ??
          WavePopularity.any,
      genres: List.unmodifiable(
        (j['genres'] is List ? j['genres'] as List : const [])
            .whereType<String>()
            .where(waveGenres.containsKey)
            .toSet(),
      ),
    );
  }
}
