part of 'zvuk_api.dart';

extension ZvukPersonal on ZvukApi {
  Future<List<CatalogItem>> savedCatalog() async {
    final data = await _graph(
      'savedCatalog',
      'query savedCatalog { collection { artists { id } releases { id } } }',
    );
    final result = <CatalogItem>[];
    for (final kind in [CatalogKind.album, CatalogKind.artist]) {
      final ids = (data['collection'][kind.field] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((j) => j['id'].toString())
          .toList();
      final field = kind == CatalogKind.album ? 'getReleases' : 'getArtists';
      final extra = kind == CatalogKind.album ? 'artists { id title }' : '';
      final found = <String, CatalogItem>{};
      for (var i = 0; i < ids.length; i += 50) {
        final batch = await _graph(
          'savedMetadata',
          'query savedMetadata(\$ids: [ID!]!) { $field(ids: \$ids) { id title image { src } $extra } }',
          {'ids': ids.sublist(i, (i + 50).clamp(0, ids.length))},
        );
        for (final row
            in (batch[field] as List? ?? [])
                .whereType<Map<String, dynamic>>()) {
          final item = CatalogItem.fromApi(row, kind);
          found[item.id] = item;
        }
      }
      result.addAll(ids.where(found.containsKey).map((id) => found[id]!));
    }
    return result;
  }

  Future<HistoryPage> listeningHistory({int offset = 0, int limit = 50}) async {
    final data = await _graph(
      'recentHistory',
      'query recentHistory(\$limit: Int, \$offset: Int) { listeningHistory(limit: \$limit, offset: \$offset) { lastListeningDttm mediaContent { __typename ... on Track { ${ZvukApi._fields} } } } }',
      {'limit': limit, 'offset': offset},
    );
    final rows = data['listeningHistory'] as List? ?? [];
    final entries = <ListeningEntry>[];
    for (final row in rows.whereType<Map<String, dynamic>>()) {
      final media = row['mediaContent'];
      final at = DateTime.tryParse(row['lastListeningDttm']?.toString() ?? '');
      if (media is Map<String, dynamic> &&
          media['__typename'] == 'Track' &&
          at != null) {
        entries.add(ListeningEntry(Track.fromApi(media), at));
      }
    }
    return HistoryPage(
      entries,
      rows.length < limit ? null : offset + rows.length,
    );
  }

  Future<SongLyrics?> lyrics(String trackId) async {
    final data = await _request(
      '/api/tiny/lyrics',
      params: {'track_id': trackId},
    );
    final result = data['result'] ?? data;
    final text = result['lyrics'] as String?;
    if (text == null || text.trim().isEmpty) return null;
    final parsed = SongLyrics.parse(
      text,
      translation: result['translation'] as String?,
    );
    return parsed.lines.any((line) => line.text.isNotEmpty) ? parsed : null;
  }
}
