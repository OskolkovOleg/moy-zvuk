part of 'zvuk_api.dart';

extension ZvukRadio on ZvukApi {
  Future<RadioPage> recommendations(
    WaveSource source, {
    int cursor = 0,
    int count = 15,
    WaveOptions options = const WaveOptions(),
  }) async {
    if (count < 1 || count > 50 || cursor < 0) {
      throw ArgumentError('Invalid recommendation page');
    }
    WaveSource.fromJson(source.toJson());
    if (source.kind == WaveKind.personal ||
        source.kind == WaveKind.favorites ||
        source.kind == WaveKind.playlist) {
      return RadioPage(
        await personalWave(
          count: count,
          options: source.kind == WaveKind.personal
              ? options
              : const WaveOptions(),
          waveInput: switch (source.kind) {
            WaveKind.favorites => {'waveType': 'FAVTRACKS'},
            WaveKind.playlist => {
              'waveType': 'PLAYLIST',
              'waveId': int.parse(source.id),
            },
            _ => null,
          },
        ),
      );
    }
    final data = await _graph(
      'contextRadio',
      'query contextRadio(\$id: ID!, \$type: RecommenderRadioEntityType!, \$first: NonNegativeInt!, \$cursor: NonNegativeInt) { recommenderRadio(onEntity: {id: \$id, type: \$type}, first: \$first, cursor: \$cursor) { cursor tracks { ${ZvukApi._fields} } } }',
      {
        'id': source.id,
        'type': switch (source.kind) {
          WaveKind.track => 'TRACK',
          WaveKind.artist => 'ARTIST',
          WaveKind.album => 'RELEASE',
          _ => throw StateError('Unsupported radio source'),
        },
        'first': count,
        'cursor': cursor,
      },
    );
    final radio = data['recommenderRadio'];
    if (radio is! Map || radio['tracks'] is! List) {
      throw const ZvukException(
        'Не удалось подобрать похожую музыку. Попробуй снова.',
      );
    }
    final next = radio['cursor'];
    return RadioPage(
      (radio['tracks'] as List)
          .whereType<Map<String, dynamic>>()
          .where((j) => j['id'] != null)
          .map(Track.fromApi)
          .toList(),
      cursor: next is int && next >= 0 ? next : cursor,
    );
  }
}
