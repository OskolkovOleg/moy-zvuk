part of 'zvuk_api.dart';

extension ZvukDiscovery on ZvukApi {
  Future<List<ArtistRelease>> discoveryReleases(List<String> artistIds) async {
    if (artistIds.isEmpty) return [];
    final data = await _graph(
      'discoveryReleases',
      'query discoveryReleases(\$ids: [ID!]!) { getArtists(ids: \$ids) { id title releases(offset: 0, limit: 10) { id title date image { src } artists { id title } tracks { ${ZvukApi._fields} } } } }',
      {'ids': artistIds.take(12).toList()},
    );
    final found = <String, ArtistRelease>{};
    for (final artist
        in (data['getArtists'] as List? ?? [])
            .whereType<Map<String, dynamic>>()) {
      for (final release
          in (artist['releases'] as List? ?? [])
              .whereType<Map<String, dynamic>>()) {
        if (release['id'] == null) continue;
        final album = CatalogItem.fromApi(release, CatalogKind.album);
        found[album.id] = ArtistRelease(
          album,
          DateTime.tryParse(release['date']?.toString() ?? ''),
          (release['tracks'] as List? ?? [])
              .whereType<Map<String, dynamic>>()
              .where((t) => t['id'] != null)
              .map(Track.fromApi)
              .toList(),
        );
      }
    }
    return found.values.toList()..sort(
      (a, b) => (b.date ?? DateTime(0)).compareTo(a.date ?? DateTime(0)),
    );
  }
}
