import 'models.dart';

enum GenreGroup {
  pop,
  rock,
  hipHop,
  electronic,
  indie,
  metal,
  jazz,
  blues,
  folkWorld,
  classical,
  ambient,
  soundtrack;

  String get label => switch (this) {
    pop => 'Поп',
    rock => 'Рок',
    hipHop => 'Хип-хоп и рэп',
    electronic => 'Электроника',
    indie => 'Инди',
    metal => 'Метал',
    jazz => 'Джаз',
    blues => 'Блюз',
    folkWorld => 'Фолк и этника',
    classical => 'Классика',
    ambient => 'Эмбиент',
    soundtrack => 'Саундтреки',
  };
}

// Exact normalized aliases, rather than substring guesses. Unknown styles stay
// in Track.genres and remain playable when no genre filter is selected.
const _genreNames = <GenreGroup, Set<String>>{
  GenreGroup.pop: {
    'pop',
    'russianpop',
    'poprock',
    'indiepop',
    'dancepop',
    'electropop',
    'synthpop',
    'europop',
    'kpop',
    'jpop',
    'поп',
  },
  GenreGroup.rock: {
    'rock',
    'russianrock',
    'alternativerock',
    'indierock',
    'poprock',
    'punk',
    'punkrock',
    'postpunk',
    'hardrock',
    'folkrock',
    'bluesrock',
    'progressiverock',
    'postrock',
    'classicrock',
    'garagerock',
    'grunge',
    'rockroll',
    'rocknroll',
    'rockandroll',
    'psychedelicrock',
    'artrock',
    'рок',
  },
  GenreGroup.hipHop: {
    'hiphop',
    'rap',
    'russianrap',
    'hiphoprap',
    'raprb',
    'raprnb',
    'trap',
    'emorap',
    'gangstarap',
    'cloudrap',
    'alternativerap',
    'boombap',
    'хипхоп',
    'рэп',
  },
  GenreGroup.electronic: {
    'electronic',
    'electronica',
    'danceelectronic',
    'dance',
    'edm',
    'house',
    'deephouse',
    'techno',
    'trance',
    'dubstep',
    'drumandbass',
    'drumnbass',
    'drumbass',
    'dnb',
    'downtempo',
    'disco',
    'electropop',
    'synthpop',
    'электроника',
  },
  GenreGroup.indie: {'indie', 'indierock', 'indiepop', 'инди'},
  GenreGroup.metal: {
    'metal',
    'heavymetal',
    'alternativemetal',
    'numetal',
    'metalcore',
    'deathmetal',
    'blackmetal',
    'thrashmetal',
    'progressivemetal',
    'folkmetal',
    'powermetal',
    'symphonicmetal',
    'deathcore',
    'метал',
  },
  GenreGroup.jazz: {'jazz', 'smoothjazz', 'jazzfusion', 'джаз'},
  GenreGroup.blues: {'blues', 'bluesrock', 'блюз'},
  GenreGroup.folkWorld: {
    'folk',
    'world',
    'worldmusic',
    'folkworldcountry',
    'country',
    'ethnic',
    'folkrock',
    'folkmetal',
    'фолк',
    'этника',
    'кантри',
  },
  GenreGroup.classical: {'classical', 'opera', 'baroque', 'классика', 'опера'},
  GenreGroup.ambient: {'ambient', 'darkambient', 'эмбиент'},
  GenreGroup.soundtrack: {
    'soundtrack',
    'soundtracks',
    'score',
    'filmscore',
    'stagescreen',
    'stageandscreen',
    'саундтрек',
    'саундтреки',
  },
};

final _genrePunctuation = RegExp(r'[^a-z0-9а-яё]');

/// A track may match several groups; unknown labels do not imply any group.
Set<GenreGroup> genreGroupsFor(Track track) {
  final names = track.genres
      .map((g) => g.name.toLowerCase().replaceAll(_genrePunctuation, ''))
      .toSet();
  return Set.unmodifiable(
    GenreGroup.values.where((group) => names.any(_genreNames[group]!.contains)),
  );
}

/// OR within genre groups, AND with the inclusive score range. Keeps source
/// order and occurrences so callers can choose sorting or shuffling afterwards.
List<Track> filterTracksByGenreAndScore(
  Iterable<Track> source,
  Map<String, Rating> ratings, {
  Set<GenreGroup> groups = const {},
  int? minScore,
  int? maxScore,
}) {
  if (minScore != null && maxScore != null && minScore > maxScore) {
    throw ArgumentError('Начало диапазона больше конца');
  }
  return source.where((track) {
    final score = trackScore(track.id, ratings);
    if ((minScore != null && score < minScore) ||
        (maxScore != null && score > maxScore)) {
      return false;
    }
    return groups.isEmpty || genreGroupsFor(track).any(groups.contains);
  }).toList();
}
