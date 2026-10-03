part of 'zvuk_api.dart';

extension ZvukSearch on ZvukApi {
  Future<List<SearchHit>> quickSearch(String query) async {
    if (query.trim().isEmpty) return [];
    final data = await _graph(
      'quickSearch',
      'query quickSearch(\$query: String, \$limit: Int) { quickSearch(query: \$query, limit: \$limit) { content { __typename ... on Track { ${ZvukApi._fields} } ... on Artist { id title image { src } } ... on Release { id title image { src } artists { id title } } ... on Playlist { id title image { src } } } } }',
      {'query': query.trim(), 'limit': 12},
    );
    final result = data['quickSearch'];
    if (result is! Map || result['content'] is! List) {
      throw const ZvukException('Поиск сейчас недоступен. Попробуй ещё раз.');
    }
    final hits = <SearchHit>[], seen = <String>{};
    for (final j
        in (result['content'] as List).whereType<Map<String, dynamic>>()) {
      if (j['id'] == null ||
          j['id'].toString().isEmpty ||
          j['title'] is! String) {
        continue;
      }
      final hit = switch (j['__typename']) {
        'Track' => SearchHit.track(Track.fromApi(j)),
        'Artist' => SearchHit.item(CatalogItem.fromApi(j, CatalogKind.artist)),
        'Release' => SearchHit.item(CatalogItem.fromApi(j, CatalogKind.album)),
        'Playlist' => SearchHit.item(
          CatalogItem.fromApi(j, CatalogKind.playlist),
        ),
        _ => null,
      };
      if (hit != null && seen.add(hit.key)) hits.add(hit);
    }
    return hits;
  }
}
